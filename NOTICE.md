# NOTICE

This repository (`ljh-sh/wdiff`) provides self-contained, statically-linked
builds of **GNU wdiff** (1.2.2) and the build/packaging layer around it.
The binary is a front-end to GNU `diff`, so the repo also vendors
**GNU diffutils** (3.10) and statically links it into the same archive.

## Wrapper license (this repo's own files)

`scripts/`, `.github/workflows/`, `README.md`, `NOTICE.md`, `AUDIT-2026-07-15.md`,
`.gitignore`, and the top-level `LICENSE` symlink are

    Copyright (c) 2026 Li Junhao
    Licensed under the MIT License — see LICENSE (MIT half).

The top-level `LICENSE` is the GPL-3.0 text — this is the licence
that ships with the binary (per upstream). The wrapper code is
MIT; the upstream code is GPL-3.0; both are tracked separately.

## Upstream license (`upstream/wdiff/` and the `wdiff` artifact)

`upstream/wdiff/` is a verbatim copy of
[ftp.gnu.org/gnu/wdiff/wdiff-1.2.2.tar.gz](https://ftp.gnu.org/gnu/wdiff/wdiff-1.2.2.tar.gz)
(the GNU wdiff front-end, by François Pinard, 1992; current
maintenance by the GNU Project). Upstream license is GPL-3.0:

    Copyright (C) 1992, 1997, 1998, 1999, 2009, 2010, 2011, 2012 Free Software
    Foundation, Inc.
    Licensed under the GNU General Public License, version 3 — see LICENSE.

## Upstream license (`upstream/diffutils/` and the `diff` artifact)

`upstream/diffutils/` is a verbatim copy of
[ftp.gnu.org/gnu/diffutils/diffutils-3.10.tar.xz](https://ftp.gnu.org/gnu/diffutils/diffutils-3.10.tar.xz)
(used only as the underlying diff engine wdiff shells out to).
Upstream license is GPL-3.0 — same as wdiff, see the per-file
`COPYING` header in `upstream/diffutils/COPYING`.

## How vendoring is structured

`upstream/wdiff/` was created with:

    curl -L -o wdiff-1.2.2.tar.gz https://ftp.gnu.org/gnu/wdiff/wdiff-1.2.2.tar.gz
    tar xzf wdiff-1.2.2.tar.gz
    mv wdiff-1.2.2 upstream/wdiff
    rm -rf upstream/wdiff/.git upstream/wdiff/.gitignore

`upstream/diffutils/` was created with the same recipe against
`https://ftp.gnu.org/gnu/diffutils/diffutils-3.10.tar.xz`.

Both are clean copies — no local patches. To refresh:

    bash scripts/vendor-refresh.sh   # (planned for v0.2.0)

## Why the binary statically links both wdiff and diff

`wdiff` is a *front-end* to GNU `diff` (calls it via `popen()`).
If the user has no `diff` on `$PATH` (common on minimal images
like Alpine, Distroless, scratch), the ljh-sh dist binary is
useless. To make the dist binary self-contained, we vendor
diffutils 3.10, build a static `diff` binary from it, and ship
both `wdiff` and `diff` in the same archive. The
`scripts/build.sh` patch sets `DIFF_PROGRAM` to an absolute
path inside the dist (`$bindir/diff`) so wdiff never does
PATH lookup at runtime — closes audit finding #1
(see `AUDIT-2026-07-15.md`).
