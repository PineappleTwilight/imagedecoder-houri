# WSL Tests for imagedecoder-houri

This directory contains comprehensive WSL functionality tests that sniff out the exact class of bug that caused:

```
ERROR: Cannot find specified cross file:
--cross-file=  (empty) -> meson fails with "Could not find any valid candidate for cross files"
```

Root cause was CMake variable ordering: `EP_MESON_ARGS` was set **before** `MESON_CROSS_FILE_PATH_WSL` was defined via `to_msys_path()`, so `--cross-file=` expanded to empty and was passed through `meson_helper.sh` to `meson setup`.

## Structure

```
tests/
  README.md                 — this file
  wsl/
    run_all.sh              — single entry point (runs all suites)
    test_to_msys_path.sh    — CMake to_msys_path() conversions (15 cases)
    test_meson_helper.sh    — meson_helper.sh argument handling (15 cases)
    test_cross_file.sh      — android-cross-file.txt content (10 cases)
    test_cmake_ordering.sh  — EP_MESON_ARGS ordering guard (5 cases)
    test_wsl_detection.sh   — WSL + tool presence on host (12 cases)
    test_autotools_helpers.sh — autotools_helper.sh path handling (8 cases)
    test_cmake_to_msys.cmake — CMake script-mode test for to_msys_path (run via cmake -P)
```

## Running

From **WSL** (recommended, single path):

```bash
# From repo root (parent)
bash external/imagedecoder-houri/tests/wsl/run_all.sh
# or
wsl bash -c "bash /mnt/c/Users/Branden/komikku-pineapple/external/imagedecoder-houri/tests/wsl/run_all.sh"
```

From **Windows PowerShell** (native, the wrapper calls WSL for you):

```powershell
# All suites — from repo root
powershell -ExecutionPolicy Bypass -File external\imagedecoder-houri\tests\wsl\run.ps1
# or pwsh
pwsh -File external/imagedecoder-houri/tests/wsl/run.ps1

# Repo-root wrapper (same)
powershell -ExecutionPolicy Bypass -File scripts\wsl-tests\run.ps1
pwsh -File scripts/wsl-tests/run.ps1

# Single suite + verbose + dry-run
powershell -File external\imagedecoder-houri\tests\wsl\run.ps1 -Suite test_meson_helper -Verbose
powershell -File external\imagedecoder-houri\tests\wsl\run.ps1 -Suite test_to_msys_path -WhatIf
```

From **Windows Git Bash** (should also pass, but helpers prefer wslpath):

```bash
bash external/imagedecoder-houri/tests/wsl/run_all.sh
```

No Gradle required — all tests are pure `bash` + `cmake -P` (PowerShell wrappers just delegate to `wsl bash`).

## What Each Suite Catches

| Suite | What breaks if it fails |
|-------|------------------------|
| `to_msys_path` | `C:/` → `/mnt/c/` wrong, `/c/` not upgraded, backslash not handled, spaces broken |
| `meson_helper` | Empty `--cross-file=` slips through, `C:/` not converted via `wslpath`, order-dependent conversion missed |
| `cross_file` | `android-cross-file.txt` missing, CRLF present, `C:/` leaked into `[binaries]`, pkg_config_path not dual-listed |
| `cmake_ordering` | Stale `.cxx` cache with empty `--cross-file=` in `build.ninja`, duplicate EP_MESON_ARGS definitions diverge |
| `wsl_detection` | `wsl.exe` not found via 32-bit redirection, `meson`/`make`/`pkg-config` missing in WSL, Ninja with space selected |
| `autotools_helpers` | `autotools_helper.sh` fails to `wslpath` a `C:/` source dir, prefix conversion broken |

## Exit Codes

- `0` — all tests passed
- `1` — one or more failures (suite and case names printed in red)
- `2` — environment not ready (e.g., `cmake` or `wslpath` missing; not a code bug, but a setup hint)

## Maintenance

When adding a new ExternalProject that uses `EP_MESON_ARGS` or `MESON_HELPER`:

1. Add a case to `test_cmake_ordering.sh` that `grep`s `CMakeLists.txt` for the new include and asserts it appears **after** the re-set of `EP_MESON_ARGS` (around line 696).
2. Add a case to `test_meson_helper.sh` for any new flag shape that contains a path.

When changing `to_msys_path()`:

1. Update `test_to_msys_path.sh` and `test_cmake_to_msys.cmake` together — they exercise the same logic via bash and via real CMake.
