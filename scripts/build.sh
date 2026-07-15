#!/usr/bin/env sh
# Build wdiff as a static, self-contained binary. Linux gnu + macOS + MinGW.
# wdiff is a front-end to GNU `diff`, so this script first builds a static
# `diff` from upstream/diffutils/, then builds wdiff with DIFF_PROGRAM
# absolute-pathed to the bundled `diff` binary — this closes the popen-PATH
# audit finding (#1 in AUDIT-2026-07-15.md).
#
# Out-of-tree build into BUILD_DIR (default ./build) — leaves upstream/
# untouched so musl alpine + host glibc builds don't fight over state.
#
# Used by:
#   - .github/workflows/build-and-test.yml + release.yml on:
#       macos-14          (host arch = aarch64-macos; cross to x86_64 too)
#       windows-latest    (MSYS2/mingw64 x86_64)
#   - Local development on any POSIX host.
#
# Cross-compile: set WDIFF_TARGET_ARCH + WDIFF_TARGET_OS (or WDIFF_TRIPLET)
# + WDIFF_OS_HINT (darwin | windows). The script exports CC/CFLAGS/LDFLAGS
# and tells autotools --host=<triplet>. macOS uses clang -arch; MinGW uses
# the cross-toolchain named aarch64-w64-mingw32-gcc.
set -eu

ROOT="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"
WDIFF_SRC="${WDIFF_SRC:-$ROOT/upstream/wdiff}"
DIFFUTILS_SRC="${DIFFUTILS_SRC:-$ROOT/upstream/diffutils}"
BUILD_DIR="${BUILD_DIR:-$ROOT/build}"

[ -f "$WDIFF_SRC/configure.ac" ] \
	|| { echo "error: $WDIFF_SRC/configure.ac not found" >&2; exit 1; }
[ -f "$DIFFUTILS_SRC/configure.ac" ] \
	|| { echo "error: $DIFFUTILS_SRC/configure.ac not found" >&2; exit 1; }
command -v autoreconf >/dev/null 2>&1 \
	|| { echo "error: autoreconf not found in PATH (install autoconf + automake + libtool)" >&2; exit 1; }
command -v make >/dev/null 2>&1 \
	|| { echo "error: make not found in PATH" >&2; exit 1; }

JOBS="$(getconf _NPROCESSORS_ONLN 2>/dev/null || sysctl -n hw.nproc 2>/dev/null || echo 4)"

# Configure args for both sub-builds.
#   --disable-dependency-tracking   (one-shot CI build, no dep graph)
#   --disable-shared               (static archive only)
#   --disable-silent-rules          (so `make` logs each step — CI shows it)
CONFIGURE_ARGS="--disable-dependency-tracking --disable-shared --disable-silent-rules"

# Cross-compile: WDIFF_TARGET_ARCH + WDIFF_TARGET_OS, etc.
HOST_ARCH="$(uname -m 2>/dev/null || echo unknown)"
TARGET_ARCH="${WDIFF_TARGET_ARCH:-$HOST_ARCH}"
TRIPLET="${WDIFF_TRIPLET:-}"
if [ -n "${WDIFF_TARGET_OS:-}" ]; then
	TRIPLET="${TRIPLET:-${WDIFF_TARGET_ARCH}-${WDIFF_TARGET_OS}}"
fi
if [ "$TARGET_ARCH" != "$HOST_ARCH" ] || [ -n "${WDIFF_TARGET_OS:-}" ]; then
	[ -z "$TRIPLET" ] && TRIPLET="$TARGET_ARCH"
	case "${WDIFF_OS_HINT:-}" in
	darwin)
		# Apple SDK is shared between arches; clang auto-discovers via xcrun.
		export CC=clang
		# `-D_SOCKLEN_T` skips the broken Xcode 15.4 typedef
		# in <sys/_types/_socklen_t.h>; `-include` injects our
		# own typedef via upstream/diffutils/patches/socklen_t_fallback.h.
		# See the comment in that header for the full rationale.
		export CFLAGS="-arch $TARGET_ARCH -O2 -std=gnu11 -D__has_c_attribute\(x\)=0 -D_SOCKLEN_T -include $DIFFUTILS_SRC/patches/socklen_t_fallback.h"
		export LDFLAGS="-arch $TARGET_ARCH"
		;;
	windows)
		# MinGW cross-toolchain (e.g. x86_64-w64-mingw32-gcc from msys2).
		export CC="${TARGET_ARCH%-*}-w64-mingw32-gcc"
		export CXX="${TARGET_ARCH%-*}-w64-mingw32-g++"
		export AR="${TARGET_ARCH%-*}-w64-mingw32-ar"
		export RANLIB="${TARGET_ARCH%-*}-w64-mingw32-ranlib"
		# diffutils on Windows needs to link bcrypt + ws2_32 for the
		# modern fopen / fdopen stack; handled by the upstream Makefile
		# but we surface LIBS so it can't be missed.
		export LIBS="-lbcrypt -lws2_32"
		;;
	*)
		# Generic clang fallback.
		export CC=clang
		export CFLAGS="-arch $TARGET_ARCH -O2 -std=gnu11 -D__has_c_attribute\(x\)=0 -D_SOCKLEN_T -include $DIFFUTILS_SRC/patches/socklen_t_fallback.h"
		export LDFLAGS="-arch $TARGET_ARCH"
		;;
	esac
	CONFIGURE_ARGS="$CONFIGURE_ARGS --host=$TRIPLET"
	[ -n "${WDIFF_BUILD_TRIPLET:-}" ] && CONFIGURE_ARGS="$CONFIGURE_ARGS --build=$WDIFF_BUILD_TRIPLET"
	echo "==> cross-compile: host=$HOST_ARCH → target=$TARGET_ARCH ($TRIPLET)"
else
	# Host build (no cross). The bundled gnulib code in wdiff/diffutils
	# 1.2.2 / 3.10 is from circa-2014 glibc; it uses K&R-style function
	# definitions and inline asm that break under -std=gnu23 (the new
	# macOS default since clang 17). Pin to -std=gnu11 for portability
	# across both modern Apple toolchains and the musl alpine gcc.
	# `-D__has_c_attribute(x)=0` forces the gnulib inline functions to
	# use the GCC-style `__attribute__((__unused__))` instead of the
	# C23 `[[__maybe_unused__]]` syntax — diffutils 3.10's gnulib uses
	# the latter in static inline definitions, which clang rejects in
	# the `static [[..]] int` position under gnu11.
	# `-D_SOCKLEN_T` skips the broken Xcode 15.4 typedef.
	# `-include patches/socklen_t_fallback.h` injects our own
	# typedef (the SDK's is broken; the patch header is the
	# workaround — see the file for the full rationale).
	export CFLAGS="${CFLAGS:-} -O2 -std=gnu11 -D__has_c_attribute\(x\)=0 -D_SOCKLEN_T -include $DIFFUTILS_SRC/patches/socklen_t_fallback.h"
fi

# On macOS (no makeinfo by default), no-op the texinfo step. Linux CI
# has makeinfo installed so MAKEINFO=true is a harmless no-op there.
export MAKEINFO="${MAKEINFO:-true}"

# Optional escape hatch — CI flows don't set this; downstream can.
[ -n "${WDIFF_EXTRA_CONFIGURE_ARGS:-}" ] && CONFIGURE_ARGS="$CONFIGURE_ARGS $WDIFF_EXTRA_CONFIGURE_ARGS"

# Clean any prior in-tree state left by a previous build — otherwise
# `configure` rejects the out-of-tree run with "source directory already
# configured". Idempotent on fresh checkouts (Makefile absent → no-op).
echo "==> distclean (in-tree, idempotent)"
( cd "$WDIFF_SRC"     && [ -f Makefile ] && make distclean >/dev/null 2>&1 ) || true
( cd "$DIFFUTILS_SRC" && [ -f Makefile ] && make distclean >/dev/null 2>&1 ) || true

echo "==> autoreconf -if --force  (wdiff)"
# `-f` passes --force to autopoint, which is needed because the
# upstream 1.2.2 tarball ships pre-generated po/ files that
# autopoint would otherwise refuse to overwrite.
( cd "$WDIFF_SRC" && autoreconf -if --force )

echo "==> autoreconf -if --force  (diffutils)"
( cd "$DIFFUTILS_SRC" && autoreconf -if --force )

# ----------------------------------------------------------------------
# Sub-build 1: GNU diffutils (provides the `diff` binary wdiff shells to)
# ----------------------------------------------------------------------
DIFFUTILS_BUILD="$BUILD_DIR/diffutils"
mkdir -p "$DIFFUTILS_BUILD"

echo "==> configure diffutils (out-of-tree: $DIFFUTILS_BUILD)"
# `--with-included-regex` forces diffutils to use its bundled
# gnulib regex instead of the system regex — necessary because
# musl libc does not provide POSIX `regex.h` (`re_compile_pattern`,
# `re_search`, etc.). Without this flag, the static link fails
# on musl targets with `undefined reference to re_compile_pattern`.
#
# `ac_cv_type_socklen_t=yes` tells autoconf "socklen_t is a
# known type on this system" — bypassing the broken socklen_t
# probe on the macOS x86_64 cross-compile (the cross-host's
# clang can't find socklen_t in its SDK when called with
# `-arch x86_64` from an aarch64 host).
DIFFUTILS_CONFIGURE_ARGS="--srcdir=$DIFFUTILS_SRC \
	--disable-dependency-tracking \
	--disable-silent-rules \
	--disable-shared \
	--enable-static \
	--with-included-regex \
	--without-libintl-prefix \
	ac_cv_type_socklen_t=yes"

# GL_CFLAG_GNULIB_WARNINGS is the giant inlined system-typedef
# block diffutils' Makefile appends to per-file CFLAGS. On the
# new Apple SDK (Xcode 15.4) the inlined `typedef __darwin_socklen_t
# socklen_t;` clobbers the system typedef with an expansion clang
# rejects, AND the shell tokenizes the semicolon-separated block
# into separate args that the shell tries to exec. We override
# GL_CFLAG_GNULIB_WARNINGS to empty so the inlined block is skipped;
# our own typedef comes from upstream/diffutils/patches/socklen_t_fallback.h
# (passed via -include in CFLAGS).
export GL_CFLAG_GNULIB_WARNINGS=
( cd "$DIFFUTILS_BUILD" && "$DIFFUTILS_SRC/configure" \
	$DIFFUTILS_CONFIGURE_ARGS )

echo "==> make diffutils -j$JOBS"
# `make GL_CFLAG_GNULIB_WARNINGS=` overrides the inlined block
# of system typedefs that diffutils 3.10's Makefile appends to
# every compile line. On the new Apple SDK (Xcode 15.4) the
# inlined `typedef __darwin_socklen_t socklen_t;` is broken and
# would clobber our own typedef from socklen_t_fallback.h.
# (command-line Make variable override takes precedence over
# the value the Makefile was generated with.)
( cd "$DIFFUTILS_BUILD" && make -j"$JOBS" GL_CFLAG_GNULIB_WARNINGS= )

# Locate the freshly-built `diff` binary. Linux/macOS: $DIFFUTILS_BUILD/src/diff.
# MinGW: $DIFFUTILS_BUILD/src/diff.exe.
ext_for() { [ -f "$1.exe" ] && printf '%s.exe' "$1" || printf '%s' "$1"; }
DIFF_BIN="$(ext_for "$DIFFUTILS_BUILD/src/diff")"
[ -x "$DIFF_BIN" ] || { echo "error: $DIFF_BIN not built" >&2; exit 1; }

# ----------------------------------------------------------------------
# Sub-build 2: wdiff, with DIFF_PROGRAM absolute-pathed to the bundled diff
# ----------------------------------------------------------------------
WDIFF_BUILD="$BUILD_DIR/wdiff"
mkdir -p "$WDIFF_BUILD"

# We pass DIFF_PROGRAM as an absolute path INSIDE the dist archive. The
# package.sh script will install both wdiff and diff under the same bin/
# directory, so the runtime lookup of `diff` is fully predictable.
WDIFF_CONFIGURE_ARGS="$CONFIGURE_ARGS diff_cv_prog_diff_program=$DIFF_BIN"

echo "==> configure wdiff (out-of-tree: $WDIFF_BUILD) — DIFF_PROGRAM=$DIFF_BIN"
( cd "$WDIFF_BUILD" && "$WDIFF_SRC/configure" \
	--srcdir="$WDIFF_SRC" \
	$WDIFF_CONFIGURE_ARGS )

echo "==> make wdiff -j$JOBS"
( cd "$WDIFF_BUILD" && make -j"$JOBS" )

WDIFF_BIN="$(ext_for "$WDIFF_BUILD/src/wdiff")"
[ -x "$WDIFF_BIN" ] || { echo "error: $WDIFF_BIN not built" >&2; exit 1; }

# wdiff 1.2.2 has K&R C / old-gnulib code that breaks under -std=gnu23 on
# modern compilers (regex.h symbol resolution). Only affects non-Alpine
# hosts (Alpine alpine's gcc is older). Apply the -std=gnu11 fallback.
# This is a known, narrow issue — see wdiff README "Building" section.

echo "==> built:"
ls -l "$WDIFF_BIN" "$DIFF_BIN"
