#!/usr/bin/env sh
# Stage the built wdiff + diff into a self-contained dist archive. Linux + macOS.
#   TARGET    e.g. x86_64-linux-musl | aarch64-linux-musl | aarch64-macos
#   BUILD_DIR (default $ROOT/build)
#   WDIFF_SRC (default $ROOT/upstream/wdiff — for the man page)
#   DIFFUTILS_SRC (default $ROOT/upstream/diffutils — for the diff.1 man page)
#   DIST      (default $ROOT/dist)
#
# Stage layout inside dist/wdiff-$TARGET/:
#   bin/wdiff        (the CLI binary, +x)
#   bin/diff         (the bundled diff binary, +x)
#   man/man1/wdiff.1 (the wdiff man page, source roff)
#   man/man1/diff.1  (the diff man page, source roff)
#   README.md        (link to ljh-sh/wdiff)
#
# Output: dist/wdiff-$TARGET.tar.gz + .sha256 (basename-keyed for portability).
set -eu

ROOT="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"
BUILD_DIR="${BUILD_DIR:-$ROOT/build}"
WDIFF_SRC="${WDIFF_SRC:-$ROOT/upstream/wdiff}"
DIFFUTILS_SRC="${DIFFUTILS_SRC:-$ROOT/upstream/diffutils}"
DIST="${DIST:-$ROOT/dist}"
TARGET="${TARGET:?set TARGET, e.g. x86_64-linux-musl}"

ext_for() { [ -f "$1.exe" ] && printf '%s.exe' "$1" || printf '%s' "$1"; }
WDIFF_BIN="$(ext_for "$BUILD_DIR/wdiff/src/wdiff")"
DIFF_BIN="$(ext_for "$BUILD_DIR/diffutils/src/diff")"
[ -x "$WDIFF_BIN" ] || { echo "error: $WDIFF_BIN not built (out-of-tree BUILD_DIR=$BUILD_DIR)" >&2; exit 1; }
[ -x "$DIFF_BIN"  ] || { echo "error: $DIFF_BIN not built (out-of-tree BUILD_DIR=$BUILD_DIR)"  >&2; exit 1; }

# Man page lives under upstream/wdiff/man/wdiff.1 (upstream ships it
# as a pre-generated roff source, not the texinfo .texi). Same dir
# for mdiff.1, unify.1, wdiff2.1 — we only ship wdiff.1 in the dist.
WDIFF_MAN_SRC="$WDIFF_SRC/man/wdiff.1"
DIFF_MAN_SRC="$DIFFUTILS_SRC/man/diff.1"

STAGE="$DIST/wdiff-$TARGET"
rm -rf "$STAGE"
mkdir -p "$STAGE/bin" "$STAGE/man/man1"

cp "$WDIFF_BIN" "$STAGE/bin/wdiff"
chmod +x "$STAGE/bin/wdiff"
cp "$DIFF_BIN" "$STAGE/bin/diff"
chmod +x "$STAGE/bin/diff"

# Man pages — ship if upstream has them.
[ -f "$WDIFF_MAN_SRC" ] && cp "$WDIFF_MAN_SRC" "$STAGE/man/man1/wdiff.1"
[ -f "$DIFF_MAN_SRC"  ] && cp "$DIFF_MAN_SRC"  "$STAGE/man/man1/diff.1"

# A tiny README so the archive is self-explanatory.
cat > "$STAGE/README.md" <<'EOF'
# wdiff — single-binary release

Self-contained archive from https://github.com/ljh-sh/wdiff (release tag).
The wrapper LICENSE (MIT) and NOTICE (GPL-3.0 attribution) live there.

The `wdiff` binary is a front-end to GNU `diff`, so a `diff` binary
is bundled in the same `bin/` directory. wdiff is compiled with
`DIFF_PROGRAM` absolute-pathed to `$bindir/diff`, so the runtime
lookup of `diff` is fully predictable — no `$PATH` traversal
(mitigates the `popen()` finding in `AUDIT-2026-07-15.md`).

Install (optional, manual):

    sudo install -m 0755 bin/wdiff bin/diff /usr/local/bin/
    sudo install -m 0644 man/man1/*.1 /usr/local/share/man/man1/ 2>/dev/null || true

Then:  man wdiff
       wdiff --version     # → wdiff (GNU wdiff) 1.2.2
       diff --version      # → diff (GNU diffutils) 3.10
EOF

# Tar archive — keyed basename so downstream users can verify from any cwd.
ARCHIVE="$DIST/wdiff-$TARGET.tar.gz"
( cd "$DIST" && tar czf "$ARCHIVE" "$(basename "$STAGE")" )

# SHA256 — basename-only so `sha256sum -c FILE.sha256` works from any
# cwd. Prefer coreutils sha256sum, then macOS shasum, then OpenSSL.
if   command -v sha256sum >/dev/null 2>&1; then
	HASH_CMD='sha256sum'
elif command -v shasum     >/dev/null 2>&1; then
	HASH_CMD='shasum -a 256'
else
	HASH_CMD='openssl dgst -sha256 -r'
fi
( cd "$DIST" && $HASH_CMD "wdiff-$TARGET.tar.gz" \
	| awk '{printf "%s  wdiff-'"$TARGET"'.tar.gz\n", $1}' ) > "$ARCHIVE.sha256"

echo "==> $ARCHIVE"
echo "==> $ARCHIVE.sha256"
