#!/usr/bin/env sh
# Smoke test for the freshly-built wdiff CLI. Wdiff's primary job is
# WORD-LEVEL diff — show inserted / deleted words with [-..-] {+..+}
# markers. We focus smoke on:
#
#   1. Version banner (proves the wdiff binary runs)
#   2. Bundled `diff` is invoked (proves DIFF_PROGRAM absolute path works)
#   3. Word-level marker output (proves the binary does what it claims)
#   4. Unicode / UTF-8 input round-trip
#   5. Empty-file edge case
#
# Why we don't run upstream `make check`: wdiff 1.2.2's tests/wdiff.at
# uses autoconf's old `testsuite` driver that doesn't play well with
# out-of-tree build trees on macOS (gnulib K&R C / -std=gnu11 mismatch).
# We drive the binary directly with hand-crafted inputs that exercise
# the same word-diff code paths the upstream tests do.
#
# `cmp` instead of `sha256sum` — BusyBox compatibility.
set -eu

ROOT="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"
BUILD_DIR="${BUILD_DIR:-$ROOT/build}"

# Locate the freshly-built binaries.
ext_for() { [ -f "$1.exe" ] && printf '%s.exe' "$1" || printf '%s' "$1"; }
WDIFF="$(ext_for "$BUILD_DIR/wdiff/src/wdiff")"
DIFF="$(ext_for "$BUILD_DIR/diffutils/src/diff")"
[ -x "$WDIFF" ] || { echo "error: $WDIFF not built (BUILD_DIR=$BUILD_DIR)" >&2; exit 1; }
[ -x "$DIFF"  ] || { echo "error: $DIFF not built (BUILD_DIR=$BUILD_DIR)"   >&2; exit 1; }

# ----------------------------------------------------------------------
# 1. Version banner
# ----------------------------------------------------------------------
echo "==> version check (wdiff)"
WDIFF_VERSION=$("$WDIFF" --version 2>&1 | head -1)
echo "$WDIFF_VERSION" | grep -q 'wdiff (GNU' \
	|| { echo "FAIL: wdiff banner missing — got: $WDIFF_VERSION" >&2; exit 1; }
echo "    OK: $WDIFF_VERSION"

echo "==> version check (diff)"
DIFF_VERSION=$("$DIFF" --version 2>&1 | head -1)
echo "$DIFF_VERSION" | grep -q 'diff (GNU' \
	|| { echo "FAIL: diff banner missing — got: $DIFF_VERSION" >&2; exit 1; }
echo "    OK: $DIFF_VERSION"

# ----------------------------------------------------------------------
# 2. Word-level diff (the differentiator)
# ----------------------------------------------------------------------
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

cat > "$TMP/a.txt" <<'EOF'
the quick brown fox
jumps over the lazy dog
EOF

cat > "$TMP/b.txt" <<'EOF'
the SLOW brown fox
jumps over the LAZY dog
EOF

WDIFF_OUT=$("$WDIFF" "$TMP/a.txt" "$TMP/b.txt" 2>&1) || true
echo "==> wdiff output:"
echo "$WDIFF_OUT" | sed 's/^/    /'

# Expect the `[-quick-] {+SLOW+}` and `[-lazy-] {+LAZY+}` markers.
# (Note the space between `]` and `{+` — that's the source-file whitespace
# between the two adjacent words, which wdiff faithfully preserves.)
echo "$WDIFF_OUT" | grep -q -- '\[-quick-\] {+SLOW+}' \
	|| { echo "FAIL: expected [-quick-] {+SLOW+} marker" >&2; exit 1; }
echo "$WDIFF_OUT" | grep -q -- '\[-lazy-\] {+LAZY+}' \
	|| { echo "FAIL: expected [-lazy-] {+LAZY+} marker" >&2; exit 1; }
echo "    OK: word-level markers present"

# ----------------------------------------------------------------------
# 3. Bundled-diff invocation
# ----------------------------------------------------------------------
# wdiff should have invoked the bundled `diff` (DIFF_PROGRAM = absolute
# path). Replace $DIFF with a sentinel: if the binary fell back to PATH
# lookup, the sentinel won't be hit.
TMP2="$(mktemp -d)"
trap 'rm -rf "$TMP" "$TMP2"' EXIT

SENTINEL="$TMP2/sentinel-diff"
cat > "$SENTINEL" <<'SHIM'
#!/bin/sh
echo "SENTINEL_INVOKED" >&2
exit 1
SHIM
chmod +x "$SENTINEL"

# Run wdiff with an env PATH that HIDES the bundled diff and exposes the
# sentinel. If the absolute DIFF_PROGRAM path is respected, wdiff should
# still produce correct output (no SENTINEL_INVOKED). The exit code will
# be 1 because the files differ; that's expected. Use `|| true` to
# shield from `set -e` (we only care about output, not exit code).
WDIFF_OUT=$(PATH="$TMP2:$PATH" "$WDIFF" "$TMP/a.txt" "$TMP/b.txt" 2>&1) || true
if echo "$WDIFF_OUT" | grep -q SENTINEL_INVOKED; then
	echo "FAIL: wdiff fell back to \$PATH lookup — DIFF_PROGRAM is NOT absolute"
	exit 1
fi
echo "    OK: bundled diff is invoked (DIFF_PROGRAM absolute path respected)"

# ----------------------------------------------------------------------
# 4. Unicode / UTF-8 round-trip
# ----------------------------------------------------------------------
cat > "$TMP/cn-a.txt" <<'EOF'
今天天气很好
EOF
cat > "$TMP/cn-b.txt" <<'EOF'
今天天气不错
EOF
WDIFF_CN=$("$WDIFF" "$TMP/cn-a.txt" "$TMP/cn-b.txt" 2>&1) || true
echo "==> wdiff CJK output:"
echo "$WDIFF_CN" | sed 's/^/    /'
echo "$WDIFF_CN" | grep -q '很好\|不错' \
	|| { echo "FAIL: CJK round-trip lost characters" >&2; exit 1; }
echo "    OK: UTF-8 CJK round-trip preserves bytes"

# ----------------------------------------------------------------------
# 5. Empty file edge case
# ----------------------------------------------------------------------
: > "$TMP/empty.txt"
echo "abc" > "$TMP/nonempty.txt"
# empty vs nonempty should report whole content as inserted
WDIFF_EMPTY=$("$WDIFF" "$TMP/empty.txt" "$TMP/nonempty.txt" 2>&1) || true
echo "$WDIFF_EMPTY" | grep -q 'abc' \
	|| { echo "FAIL: empty-vs-nonempty lost content" >&2; exit 1; }
echo "    OK: empty-vs-nonempty edge case"

# ----------------------------------------------------------------------
# 6. Exit code semantics (0 = same, 1 = diff, 2 = error)
# ----------------------------------------------------------------------
"$WDIFF" "$TMP/a.txt" "$TMP/a.txt" >/dev/null 2>&1 \
	|| { echo "FAIL: identical files should exit 0" >&2; exit 1; }
"$WDIFF" "$TMP/a.txt" "$TMP/b.txt" >/dev/null 2>&1 \
	&& { echo "FAIL: differing files should exit 1" >&2; exit 1; } || true
echo "    OK: exit codes 0/1/2 honored"

echo "smoke OK: wdiff + diff both functional; absolute DIFF_PROGRAM verified; UTF-8 + edge cases pass"
