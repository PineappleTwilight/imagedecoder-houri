# AGENTS.md — tests/wsl (build-helper tests)

## OVERVIEW
Standalone bash + `cmake -P` regression guards for the WSL/CMake path logic in `library/src/main/cpp/CMakeLists.txt`. No Gradle or Android SDK needed.

## STRUCTURE
```
tests/wsl/
├── run_all.sh                # entry point: discovers + runs all suites, aggregates results
├── run.ps1                   # Windows wrapper: delegates to WSL bash, mirrors exit codes
├── _assert.sh                # shared assert primitives, sourced by every test_*.sh
├── test_to_msys_path.sh      # bash reimplementation of to_msys_path() (15 cases)
├── test_meson_helper.sh      # meson_helper.sh argument handling (15 cases)
├── test_cross_file.sh        # android-cross-file.txt content (10 cases)
├── test_cmake_ordering.sh    # EP_MESON_ARGS ordering guard (5 cases)
├── test_wsl_detection.sh     # WSL + tool presence on host (12 cases)
├── test_autotools_helpers.sh # autotools_helper.sh path handling (8 cases)
└── test_cmake_to_msys.cmake  # real CMake to_msys_path() via cmake -P
```

## WHERE TO LOOK
| Suite | Guards |
|---|---|
| test_to_msys_path.sh | `C:/` → `/mnt/c/` conversion, `/c/` upgrade, backslashes, spaces |
| test_meson_helper.sh | empty `--cross-file=` slipping through, `C:/` not wslpath-converted |
| test_cross_file.sh | android-cross-file.txt missing, CRLF, `C:/` leaked into `[binaries]` |
| test_cmake_ordering.sh | stale `.cxx` with empty `--cross-file=` in build.ninja, duplicate EP_MESON_ARGS |
| test_wsl_detection.sh | wsl.exe via 32-bit redirection, meson/make/pkg-config present, Ninja-with-space |
| test_autotools_helpers.sh | autotools_helper.sh wslpath of `C:/` source dir, prefix conversion |
| test_cmake_to_msys.cmake | real CMake to_msys_path() parity with the bash version |

Origin bug class: `EP_MESON_ARGS` set before `MESON_CROSS_FILE_PATH_WSL` was defined, so `--cross-file=` expanded empty.

## CONVENTIONS
Authoring a suite:
- `#!/usr/bin/env bash` + `set -e`
- `SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"` idiom
- `source "$SCRIPT_DIR/_assert.sh"`
- `suite_begin "name"` at top, `suite_summary "name"` at bottom
- assert primitives: `assert_eq`, `assert_contains`, `assert_not_contains`, `assert_file_exists`, `assert_file_not_exists`, `skip`
- `suite_summary` appends `name:pass:fail:skip` to `$WSL_TEST_TMP` for run_all.sh aggregation; without it the suite is invisible in totals

Discovery:
- run_all.sh globs `test_*.sh`, skips `_assert.sh`, then runs test_cmake_to_msys.cmake via `cmake -P`
- run.ps1: `-Suite <name>` single suite, `-WhatIf` dry-run, `-Verbose`; appends `.sh`/`.cmake` automatically

## ANTI-PATTERNS
- Adding a suite without `suite_begin`/`suite_summary`: breaks `$WSL_TEST_TMP` aggregation, suite passes silently with 0 cases
- Testing generated `library/.cxx` artifacts without a skip-guard for pre-configure state: `.cxx` may not exist yet, suite fails spuriously
- Editing test_to_msys_path.sh without test_cmake_to_msys.cmake: the two must stay in sync, they exercise the same logic via bash and real CMake

## COMMANDS
```bash
bash tests/wsl/run_all.sh                          # all suites (WSL or Git Bash)
bash tests/wsl/test_meson_helper.sh                # single suite directly
powershell -File tests\wsl\run.ps1                 # Windows wrapper (delegates to WSL)
powershell -File tests\wsl\run.ps1 -Suite test_to_msys_path -WhatIf
```

Exit codes: 0 all pass, 1 failures, 2 environment not ready (cmake/wslpath/wsl.exe missing).