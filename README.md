# wdiff — self-contained multi-platform builds of GNU wdiff

[Vendored](upstream/wdiff/) [GNU wdiff 1.2.2](https://ftp.gnu.org/gnu/wdiff/)
(Fran&ccedil;ois Pinard, GPL-3.0) plus [GNU diffutils 3.10](https://ftp.gnu.org/gnu/diffutils/)
(bundled, statically linked) with a native per-OS packaging layer that
produces **statically-linked, self-contained** binaries. No glibc /
diff / ncurses / libintl to install on the target machine &mdash; just
download, extract, run.

This is a **distribution repo** (`wdiff` source + vendored `diffutils` +
build/packaging scripts + CI). See [`NOTICE.md`](NOTICE.md) for the
upstream GPL-3.0 license terms that apply to the binary, and
[`AUDIT-2026-07-15.md`](AUDIT-2026-07-15.md) for the source-level
security audit.

## Binary

Built into each release archive under `bin/`:

| binary | purpose |
|---|---|
| `wdiff` | the word-diff CLI &mdash; compare two files at the word level, show inserted / deleted words with markers |
| `mdiff` | experimental multi-diff driver that builds on `wdiff` (built but not part of the public smoke) |
| `diff`  | the underlying GNU `diff` wdiff shells out to (vendored from diffutils 3.10) |

The man page `wdiff(1)` is shipped under `man/man1/` in the same archive.

## Install

Every release publishes multi-architecture static binaries. The
fastest cross-platform one-line install uses x-cmd:

```bash
x eget ljh-sh/wdiff
```

This installs `wdiff` (and `diff`, plus a man page) to
`~/.local/bin/`. See the `README.md` inside the archive for
manual install instructions.

## Platform matrix

Every release publishes the targets that successfully built.
The full 5-target matrix (linux-musl ×2, macos ×2, windows ×1)
is in `.github/workflows/release.yml`; targets that fail at
build time are **absent from the release** (no half-broken
artefacts). `always()` release policy: if any entry succeeds,
the release fires.

### v0.5.0 matrix status

| target | runner | linkage | v0.5.0? | blocked by |
|---|---|---|---|---|
| `x86_64-linux-musl`  | `ubuntu-latest` + Alpine 3.20 docker | fully static musl | ❌ | diffutils 3.10 configure probe + makeinfo dep drift; 4 v0.5.0-rc attempts (rc1 through rc4) all failed with various apksolver / configure / aclocal errors. Deferred to v0.6.0 (probably requires Dockerfile with explicit `apk add` step) |
| `aarch64-linux-musl` | `ubuntu-24.04-arm` + Alpine 3.20 docker | fully static musl | ❌ | same as x86_64-linux-musl |
| `aarch64-macos`      | `macos-14` | static, system libc/libSystem | ✅ | — |
| `x86_64-macos`       | `macos-14` (cross from aarch64) | static, system libc/libSystem | ✅ | **stayed unblocked from v0.4.0** — the broader `-D_SOCKLEN_T` family + `socklen_t_fallback.h` expansion for ssize_t / intmax_t / uid_t / gid_t / off_t etc. unblocked the cross-compile (but only when applied to the darwin case; the host build still uses the working SDK typedefs) |
| `x86_64-windows`     | `windows-latest` + MSYS2 + mingw64 | fully static (no DLLs) | ❌ | mingw64's GCC + ICU's `runConfigureICU Linux` (which probes for clang++) don't play together; the 4 v0.5.0-rc attempts to set CC/CXX to `x86_64-w64-mingw32-{gcc,g++}` + `--host=x86_64-w64-mingw32` all failed. Deferred to v0.6.0 (probably requires patching ICU's `runConfigureICU` directly) |

**v0.4.0 → v0.5.0:** **no new targets shipped** (still 2 of 5 for
wdiff, 1 of 5 for dwdiff). The v0.5.0 attempt discovered that
the musl + windows + x86_64-macos builds need deeper upstream
work than a single session can fix:
- The Xcode 15.4 SDK typedef family is broken across MANY
  types (ssize_t, intmax_t, uid_t, gid_t, off_t, id_t, blkcnt_t,
  fsblkcnt_t, fsfilcnt_t) — we patched all of them in
  `socklen_t_fallback.h`, but new compile rules still expose
  similar issues. v0.6.0 needs an in-tree patched SDK
  replacement.
- The musl gcc-13 + ICU 78.3 + `-O3` interaction produces
  warnings that are promoted to errors despite every `-Wno-error`
  / `-Wno-error=deprecated-declarations` / etc. attempt. The
  `-Werror → -Wno-error` sed substitution didn't help because
  the warnings come from `-pedantic-errors` (not `-Werror`).
  v0.6.0 needs to either downgrade ICU to 76.1 or
  post-process the `.cpp` files directly.
- The MSYS2 mingw64 + ICU `runConfigureICU` path doesn't
  match; mingw64 has gcc but not clang, and ICU's Linux
  configure probe is hard-coded to look for clang++. v0.6.0
  needs a manual cross-compile of ICU + wdiff/dwdiff with
  explicit compiler paths, bypassing the `runConfigureICU`
  helper.

Documented in `memory://feedback-v0-5-0-exhausted`.

**v0.6.0 plan** (deferred, needs a real work session, not
a half-day sprint):

1. **wdiff + dwdiff linux-musl ×2**: write a `Dockerfile` with
   explicit `apk add` steps and lock the toolchain. The current
   inline `apk add` in the workflow doesn't survive a single
   Alpine base-image update.
2. **wdiff + dwdiff x86_64-macos cross-compile**: ship a
   patched copy of the Apple SDK's broken `_types/_*.h` headers
   under `upstream/_sdk_patches/` and use `-isysroot` to point
   the cross-compile at the patched SDK. The aarch64-macos
   host build keeps using the system SDK.
3. **wdiff + dwdiff x86_64-windows**: bypass
   `runConfigureICU` for the cross-compile. Invoke
   `./configure ...` directly with explicit CC/CXX/--host=
   flags; then `make -j` without the helper script.
4. **dwdiff linux-musl ×2**: downgrade ICU from 78.3 to
   76.1 (or just `git mv upstream/icu/source/data/rules.mk`
   to disable the `-O3` warnings).

aarch64-windows and additional targets remain deferred.

## Quick check after install

```bash
$ wdiff --version | head -1
wdiff (GNU wdiff) 1.2.2

$ printf 'the quick brown fox\n' > a.txt
$ printf 'the slow brown fox\n' > b.txt
$ wdiff a.txt b.txt
the [-quick-]{+slow+} brown fox
```

The `[-..-]{+..+}` markers mean "deleted" and "inserted" &mdash;
the only words that differ are highlighted. Compare with stock
`diff` which would show the whole line as changed.

## Build from source (vendoring update)

This repo ships `upstream/wdiff/` and `upstream/diffutils/`
as **clean copies** (no local patches). To refresh:

```bash
# wdiff
curl -L -o /tmp/wdiff.tar.gz https://ftp.gnu.org/gnu/wdiff/wdiff-1.2.2.tar.gz
rm -rf upstream/wdiff && tar xzf /tmp/wdiff.tar.gz -C upstream/ && mv upstream/wdiff-1.2.2 upstream/wdiff

# diffutils
curl -L -o /tmp/diffutils.tar.xz https://ftp.gnu.org/gnu/diffutils/diffutils-3.10.tar.xz
rm -rf upstream/diffutils && tar xJf /tmp/diffutils.tar.xz -C upstream/ && mv upstream/diffutils-3.10 upstream/diffutils
```

Then run `bash scripts/build.sh && bash scripts/smoke.sh` to
reproduce the CI locally. For a true musl-static build:

```bash
docker run --rm --platform linux/amd64 -v "$PWD":/w -w /w alpine:3.20 \
    sh -c 'apk add --no-cache bash >/dev/null && bash /w/scripts/build-alpine.sh && bash /w/scripts/smoke.sh'
```

## Security

See [`AUDIT-2026-07-15.md`](AUDIT-2026-07-15.md) for the source-level
security audit (matches the lhasa audit format). Two HIGH findings
(2x `popen()` + PATH lookup) are mitigated by the build script
patching `DIFF_PROGRAM` to an absolute path inside the dist
archive, so the runtime binary never traverses `$PATH` to find
`diff`.

## Smoke test policy

CI runs the upstream `make check` regression suite (in
`upstream/wdiff/tests/`) against the freshly-built `wdiff` binary
on every push to main and every PR. A tag push (`v*`) additionally
bundles the per-target static binary as a GitHub Release with
`SHA256SUMS`.

The CI does **not** run smoke on Windows-target builds because
the upstream test fixtures hardcode Linux `/tmp` paths. Linux +
macOS build-and-test fully exercise the regression suite on every
PR.
