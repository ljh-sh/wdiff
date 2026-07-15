#!/usr/bin/env pwsh
# Stage the built wdiff + diff into a self-contained dist archive. Windows.
#   TARGET    e.g. x86_64-windows
#   BUILD_DIR (default $PSScriptRoot/..\build)
#   DIST      (default $PSScriptRoot/..\dist)
#
# Stage layout inside dist\wdiff-$TARGET\:
#   bin\wdiff.exe     (the CLI binary)
#   bin\diff.exe      (the bundled diff binary)
#   man\man1\wdiff.1  (the wdiff man page, source roff)
#   man\man1\diff.1   (the diff man page, source roff)
#   README.md         (link to ljh-sh/wdiff)
#
# Output: dist\wdiff-$TARGET.zip (SHA256 inline in release.yml).
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$ROOT = (Resolve-Path "$PSScriptRoot/..").Path
$BUILD_DIR = if ($env:BUILD_DIR) { $env:BUILD_DIR } else { "$ROOT\build" }
$DIST = if ($env:DIST) { $env:DIST } else { "$ROOT\dist" }
$TARGET = if ($env:TARGET) { $env:TARGET } else { throw "set TARGET, e.g. x86_64-windows" }

$WDIFF_BIN = "$BUILD_DIR\wdiff\src\wdiff.exe"
$DIFF_BIN  = "$BUILD_DIR\diffutils\src\diff.exe"
if (-not (Test-Path $WDIFF_BIN)) { throw "error: $WDIFF_BIN not built" }
if (-not (Test-Path $DIFF_BIN))  { throw "error: $DIFF_BIN not built" }

$WDIFF_MAN_SRC = "$ROOT\upstream\wdiff\man\wdiff.1"
$DIFF_MAN_SRC  = "$ROOT\upstream\diffutils\man\diff.1"

$STAGE = "$DIST\wdiff-$TARGET"
if (Test-Path $STAGE) { Remove-Item -Recurse -Force $STAGE }
New-Item -ItemType Directory -Force -Path "$STAGE\bin" | Out-Null
New-Item -ItemType Directory -Force -Path "$STAGE\man\man1" | Out-Null

Copy-Item $WDIFF_BIN "$STAGE\bin\wdiff.exe"
Copy-Item $DIFF_BIN  "$STAGE\bin\diff.exe"

if (Test-Path $WDIFF_MAN_SRC) { Copy-Item $WDIFF_MAN_SRC "$STAGE\man\man1\wdiff.1" }
if (Test-Path $DIFF_MAN_SRC)  { Copy-Item $DIFF_MAN_SRC  "$STAGE\man\man1\diff.1" }

# Tiny README so the archive is self-explanatory.
$readme = @"
# wdiff — single-binary release (Windows)

Self-contained archive from https://github.com/ljh-sh/wdiff (release tag).
The wrapper LICENSE (MIT) and NOTICE (GPL-3.0 attribution) live there.

`wdiff` is a front-end to GNU `diff`, so `diff.exe` is bundled in the
same `bin\` directory. wdiff is compiled with `DIFF_PROGRAM`
absolute-pathed to `$bindir\diff.exe`, so the runtime lookup of `diff`
is fully predictable — no PATH traversal (mitigates the `popen()`
finding in `AUDIT-2026-07-15.md`).

Install (optional, manual):

    # In an elevated PowerShell:
    Copy-Item bin\wdiff.exe, bin\diff.exe C:\Windows\System32\

Then:

    PS> wdiff --version
    wdiff (GNU wdiff) 1.2.2
    PS> diff --version
    diff (GNU diffutils) 3.10
"@
Set-Content -Path "$STAGE\README.md" -Value $readme

# Zip archive — basename-keyed so downstream users can verify from any cwd.
$ARCHIVE = "$DIST\wdiff-$TARGET.zip"
if (Test-Path $ARCHIVE) { Remove-Item -Force $ARCHIVE }
Compress-Archive -Path "$STAGE" -DestinationPath $ARCHIVE

Write-Host "==> $ARCHIVE"
