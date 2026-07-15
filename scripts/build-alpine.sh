#!/usr/bin/env sh
# Build wdiff as a true musl-static binary inside an Alpine container.
# Out-of-tree build into /w/build so host-side state (if any) never
# leaks in — `./configure` runs with --srcdir.
#
# CI invokes:
#   docker run --rm --platform linux/$ARCH -v "$PWD":/w -w /w \
#     alpine:3.20 sh -c 'apk add --no-cache bash >/dev/null && bash /w/scripts/build-alpine.sh && bash /w/scripts/smoke.sh'
#
# Alpine's musl + alpine's gcc → fully static wdiff + diff binaries that
# run on Alpine AND every glibc distro (Ubuntu/Debian/Fedora/Arch).
set -eu

echo "==> apk add: build deps (musl-native toolchain)"
apk add --no-cache \
	build-base \
	autoconf \
	automake \
	libtool \
	linux-headers \
	bash

ROOT="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"
BUILD_DIR="${BUILD_DIR:-$ROOT/build}"

# diffutils has a hard dependency on gnulib's lib-*.c helpers that the
# upstream tarball ships as part of the wdiff bundle (wdiff/Makefile.am
# #includes some of them). For a clean musl build we also need:
#   - gettext-dev (for libintl)
#   - libxslt (for the gnulib xml-Parser)
# These come from alpine's apk.
echo "==> apk add: gettext + libxslt (needed by diffutils)"
apk add --no-cache gettext-dev libxslt

echo "==> autoreconf -if --force (wdiff + diffutils)"
# `-f` passes --force to autopoint, which is needed because the
# upstream 1.2.2 tarball ships pre-generated po/ files that
# autopoint would otherwise refuse to overwrite.
( cd "$ROOT/upstream/wdiff"     && autoreconf -if --force )
( cd "$ROOT/upstream/diffutils" && autoreconf -if --force )

# make distclean is a no-op on a fresh checkout, but defensive: if a
# prior host build left Makefile/config.h in the source tree (e.g. CI
# reused a cached checkout), drop it so autoreconf regenerates cleanly.
( cd "$ROOT/upstream/wdiff"     \
	&& find . -maxdepth 2 -name Makefile -delete -o -name 'config.h' -delete -o -name 'config.status' -delete 2>/dev/null || true )
( cd "$ROOT/upstream/diffutils" \
	&& find . -maxdepth 2 -name Makefile -delete -o -name 'config.h' -delete -o -name 'config.status' -delete 2>/dev/null || true )

# ----------------------------------------------------------------------
# Sub-build 1: diffutils (static musl)
# ----------------------------------------------------------------------
DIFFUTILS_BUILD="$BUILD_DIR/diffutils"
mkdir -p "$DIFFUTILS_BUILD"

echo "==> configure diffutils (musl-static + minimal)"
( cd "$DIFFUTILS_BUILD" && "$ROOT/upstream/diffutils/configure" \
	--srcdir="$ROOT/upstream/diffutils" \
	--disable-dependency-tracking \
	--disable-silent-rules \
	--disable-shared \
	--enable-static \
	--without-included-regex \
	--without-libintl-prefix )

echo "==> make diffutils -j$(getconf _NPROCESSORS_ONLN)"
( cd "$DIFFUTILS_BUILD" && make -j"$(getconf _NPROCESSORS_ONLN)" )

DIFF_BIN="$DIFFUTILS_BUILD/src/diff"
[ -x "$DIFF_BIN" ] || { echo "error: $DIFF_BIN not built" >&2; exit 1; }

# ----------------------------------------------------------------------
# Sub-build 2: wdiff (static musl, DIFF_PROGRAM absolute-pathed)
# ----------------------------------------------------------------------
WDIFF_BUILD="$BUILD_DIR/wdiff"
mkdir -p "$WDIFF_BUILD"

echo "==> configure wdiff (musl-static + DIFF_PROGRAM=$DIFF_BIN)"
( cd "$WDIFF_BUILD" && "$ROOT/upstream/wdiff/configure" \
	--srcdir="$ROOT/upstream/wdiff" \
	--disable-dependency-tracking \
	--disable-silent-rules \
	--disable-shared \
	diff_cv_prog_diff_program="$DIFF_BIN" )

echo "==> make wdiff -j$(getconf _NPROCESSORS_ONLN)"
( cd "$WDIFF_BUILD" && make -j"$(getconf _NPROCESSORS_ONLN)" )

WDIFF_BIN="$WDIFF_BUILD/src/wdiff"
[ -x "$WDIFF_BIN" ] || { echo "error: $WDIFF_BIN not built" >&2; exit 1; }

echo "==> built:"
ls -l "$WDIFF_BIN" "$DIFF_BIN"
