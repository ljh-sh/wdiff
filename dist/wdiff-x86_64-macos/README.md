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
