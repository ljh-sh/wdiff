# Security Policy

## Supported versions

| version | supported          | status                                      |
|---------|--------------------|---------------------------------------------|
| v0.1.x  | :white_check_mark: | current — vendored wdiff 1.2.2 + diffutils 3.10 |
| older   | :x:                | please upgrade to v0.1.2 or newer            |

Each release is a vendored snapshot of upstream `wdiff 1.2.2` and
`diffutils 3.10`. We re-vendor on every upstream security release
and bump the patch number. The build process is reproducible
within a single CI run (same toolchain, same source); bit-for-bit
cross-host reproducibility is a v0.2.0 follow-up.

## Reporting a vulnerability

Email **lijunhao@x-cmd.com** (GPG: see `cosign.pub` on the latest
release) with:

1. A clear description of the issue
2. A reproducer (input + observed output)
3. The affected version tag(s)
4. Whether you've disclosed it elsewhere

**We will acknowledge within 72 hours** and provide a fix or
mitigation plan within 14 days for HIGH/CRITICAL findings. We
follow the [libra / disclose.io](https://disclose.io/) coordinated
disclosure model — please give us 90 days before public disclosure.

For issues that turn out to be **upstream** (in wdiff or diffutils
themselves), we will:

1. File an upstream issue (or escalate an existing one)
2. Apply a local patch in `upstream/` with a clear
   `// AUDIT-FIX-N` comment
3. Document the patch in `AUDIT-2026-07-15.md` "Action plan"
4. Cut a v0.x.y release with the fix

## What counts as a vulnerability

A vulnerability is a defect in **our distribution layer** — the
build scripts, the CI, the `DIFF_PROGRAM` absolute-pathing, the
static linking, the in-binary `wdiff` + `diff` pairing. Upstream
defects are reported separately (we'll help triage but the
canonical fix is upstream).

| in scope | out of scope |
|---|---|
| Build script producing a non-self-contained binary | Upstream wdiff 1.2.2 popen PATH lookup (audit #1) — mitigated in our build |
| Cosign signature broken | wdiff 1.2.2 upstream code |
| CI uploading a non-reproducible binary | Upstream diffutils 3.10 bugs |
| Audit document disagrees with shipped binary | diffutils `-lbcrypt -lws2_32` Windows link order (Windows-only) |

## Threat model we DO defend against

- Attacker uploads a malicious PR that swaps the dist binary
  → blocked by GitHub branch protection + manual review of
  the build script
- Attacker tampers with a release artifact on GitHub Releases
  → blocked by SHA256SUMS verification + (in v0.2.0) cosign
  keyless signatures
- Attacker compromises the GNU wdiff or diffutils upstream tarball
  → mitigated by pinning to specific upstream versions + (v0.2.0)
  upstream GPG signature verification

## Threat model we do NOT defend against (v0.1.x)

- Attacker compromises `ftp.gnu.org` (mirror MITM between
  vendor-refresh and the next release)
- Attacker compromises the GitHub Actions runner
  (we trust GitHub's runner security; ci.yml is in the repo so
  any tampering is auditable)
- Attacker controls `$PATH` of the calling user
  (this is `popen("diff", ...)` audit #1 — our build
  absolute-paths DIFF_PROGRAM, but the binary trusts the
  user's path if `-a` autopager is enabled)
- Attacker controls `$PAGER` of the calling user
  (wdiff `-a` autopager; opt-in, documented behaviour)
