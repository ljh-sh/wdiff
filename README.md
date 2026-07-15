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

### v0.3.0 matrix status

| target | runner | linkage | v0.3.0? | blocked by |
|---|---|---|---|---|
| `x86_64-linux-musl`  | `ubuntu-latest` + Alpine 3.20 docker | fully static musl | ❌ | diffutils 3.10 makeinfo/help2man dep drift; deferred to v0.4.0 |
| `aarch64-linux-musl` | `ubuntu-24.04-arm` + Alpine 3.20 docker | fully static musl | ❌ | same as x86_64-linux-musl |
| `aarch64-macos`      | `macos-14` | static, system libc/libSystem | ✅ | — |
| `x86_64-macos`       | `macos-14` (cross from aarch64) | static, system libc/libSystem | ❌ | diffutils 3.10 gnulib `sys_socket.h` redefines `socklen_t` and conflicts with the new Xcode 15.4 `<sys/_types/_socklen_t.h>`; deferred to v0.4.0 (downgrade diffutils to 3.8 or apply a local gnulib patch) |
| `x86_64-windows`     | `windows-latest` + MSYS2 + mingw64 | fully static (no DLLs) | ❌ | ICU's `runConfigureICU Linux` checks for `clang++`; mingw64 doesn't ship clang++; deferred to v0.4.0 (will switch to GCC config) |

**v0.2.4 → v0.3.0:** same matrix (1 of 5). v0.3.0 marks the
socklen_t / mingw deps fixes-tried milestone.

**v0.4.0 plan:**

1. Downgrade `upstream/diffutils/` to **3.8** (predates the
   `_socklen_t.h` gnulib conflict). Trade-off: lose 3.10
   security patches; re-vendor 3.11+ when upstream fixes it.
2. Add `upstream/diffutils/patches/0001-*.patch` that disables
   gnulib's `sys_socket.h` redefinition of `socklen_t` when
   `<sys/_types/_socklen_t.h>` (Apple SDK 14+) is present.
3. For Windows: pass `CC=x86_64-w64-mingw32-gcc` + the same
   for `CXX` to `runConfigureICU`, with the
   `--host=x86_64-w64-mingw32` triplet so ICU's clang++ probe
   is bypassed.
4. For linux-musl: pin Alpine apk versions in a `Dockerfile`
   to lock the toolchain (avoid the dep drift).

The current v0.3.0 ships **aarch64-macos** only; the
matrix-completion work is in v0.4.0.

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
