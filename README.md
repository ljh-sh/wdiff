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

### v0.4.0 matrix status

| target | runner | linkage | v0.4.0? | blocked by |
|---|---|---|---|---|
| `x86_64-linux-musl`  | `ubuntu-latest` + Alpine 3.20 docker | fully static musl | ❌ | diffutils 3.10 doc/info target + makeinfo dep drift; deferred to v0.5.0 |
| `aarch64-linux-musl` | `ubuntu-24.04-arm` + Alpine 3.20 docker | fully static musl | ❌ | same as x86_64-linux-musl |
| `aarch64-macos`      | `macos-14` | static, system libc/libSystem | ✅ | — |
| `x86_64-macos`       | `macos-14` (cross from aarch64) | static, system libc/libSystem | ✅ | **unblocked in v0.4.0** via `upstream/diffutils/patches/socklen_t_fallback.h` + `make GL_CFLAG_GNULIB_WARNINGS=` |
| `x86_64-windows`     | `windows-latest` + MSYS2 + mingw64 | fully static (no DLLs) | ❌ | mingw64 ICU build needs a real fix in scripts/build.sh's windows case (and the v0.4.0 attempt didn't get the `--host=` triplet right); deferred to v0.5.0 |

**v0.3.0 → v0.4.0:** **+1 target** (wdiff x86_64-macos) via the
socklen_t fallback patch. **dwdiff** had the ICU CXXFLAGS env
var not propagating to sub-makes — needs a `sed` post-process
to the ICU Makefile to add `-Wno-error` directly. Documented
in `memory://feedback-vendored-c-diffutils-3-10-issues` and
`memory://feedback-dist-release-pipeline`.

**v0.5.0 plan:**

1. **dwdiff linux-musl ×2**: post-process the generated
   `build/icu/data/Makefile` to add `-Wno-error` to CXXFLAGS
   directly (sed-patch the Makefile after configure, before
   make). Or downgrade ICU to 76.1 (predates the C++ warnings).
2. **dwdiff x86_64-windows**: figure out the right combination
   of `CC`, `CXX`, `--host=` for `runConfigureICU` when
   cross-compiling from aarch64-macos-14 to x86_64-w64-mingw32.
3. **dwdiff x86_64-macos**: fix the `-Wno-error` CXXFLAGS
   propagation (same fix as #1).
4. **wdiff linux-musl ×2**: pin Alpine apk versions + add
   help2man + makeinfo consistently.

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
