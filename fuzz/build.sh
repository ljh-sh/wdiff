#!/usr/bin/env bash
# Build the wdiff fuzz harness.
#
# wdiff is mostly a thin front-end to GNU diff. The fuzz surface
# is wdiff's word-tokenizer + reformat path; diffutils has its own
# upstream fuzz harness (we don't fuzz it here).
#
# Usage:
#   bash fuzz/build.sh                  # build the harness
#   bash fuzz/build.sh run              # build + fuzz for ${FUZZ_TIME}s (default 60)
#
# Requires clang with libFuzzer.
set -eu

ROOT="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"
WDIFF_SRC="$ROOT/upstream/wdiff"
WDIFF_BUILD="$ROOT/build/wdiff-fuzz"
mkdir -p "$WDIFF_BUILD"

CLANG="${CLANG:-clang}"
FUZZ_CFLAGS="-O1 -g -fsanitize=address,undefined,fuzzer-no-link"
FUZZ_LDFLAGS="-fsanitize=address,undefined,fuzzer"
JOBS="$(getconf _NPROCESSORS_ONLN 2>/dev/null || sysctl -n hw.nproc 2>/dev/null || echo 4)"

build_wdiff() {
	if [ ! -f "$WDIFF_BUILD/src/wdiff.o" ]; then
		echo "==> wdiff: distclean + autoreconf + configure (sanitizers)"
		( cd "$WDIFF_SRC" && [ -f Makefile ] && make distclean >/dev/null 2>&1 ) || true
		( cd "$WDIFF_SRC" && autoreconf -if --force )
		( cd "$WDIFF_BUILD" && "$WDIFF_SRC/configure" \
			--srcdir="$WDIFF_SRC" \
			--disable-dependency-tracking \
			--disable-silent-rules \
			--disable-shared \
			--enable-static \
			CC="$CLANG" \
			CFLAGS="$FUZZ_CFLAGS" )
		echo "==> wdiff: make -j$JOBS"
		( cd "$WDIFF_BUILD" && make -j"$JOBS" )
	fi

	$CLANG $FUZZ_CFLAGS -I"$WDIFF_SRC" -I"$WDIFF_SRC/lib" \
		-fno-omit-frame-pointer \
		-c "$ROOT/fuzz/fuzz_wdiff.c" -o "$WDIFF_BUILD/fuzz_wdiff.o"
	$CLANG $FUZZ_LDFLAGS \
		"$WDIFF_BUILD/fuzz_wdiff.o" \
		$(find "$WDIFF_BUILD/src" -name '*.o' | tr '\n' ' ') \
		-lintl \
		-o "$ROOT/fuzz/wdiff_fuzz"
	echo "==> built $ROOT/fuzz/wdiff_fuzz"
}

case "${1:-build}" in
	build) build_wdiff ;;
	run)
		build_wdiff
		mkdir -p /tmp/wdiff-corpus
		TIME="${FUZZ_TIME:-60}"
		echo "==> fuzzing wdiff for ${TIME}s"
		timeout "${TIME}" "$ROOT/fuzz/wdiff_fuzz" /tmp/wdiff-corpus -max_len=65536 || true
		;;
	*) echo "usage: $0 {build|run}"; exit 1 ;;
esac
