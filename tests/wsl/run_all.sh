#!/usr/bin/env bash
# run_all.sh — single entry point for all WSL tests
# Usage: bash run_all.sh  (from WSL:  wsl bash run_all.sh)
set -e
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
WSL_TEST_TMP="$(mktemp)"
export WSL_TEST_TMP

# Colors if TTY
if [[ -t 1 ]]; then
  GREEN="\033[32m"; RED="\033[31m"; YELLOW="\033[33m"; NC="\033[0m"
else
  GREEN=""; RED=""; YELLOW=""; NC=""
fi

TOTAL_PASS=0
TOTAL_FAIL=0
TOTAL_SKIP=0
SUITES_RUN=0
SUITES_FAIL=0

run_suite() {
  local file="$1"
  local name
  name="$(basename "$file")"
  echo ""
  echo "------------------------------------------------------------"
  echo "Running $name"
  echo "------------------------------------------------------------"
  set +e
  bash "$file" 2>&1
  rc=$?
  set -e
  SUITES_RUN=$((SUITES_RUN+1))
  if [[ $rc -ne 0 ]]; then
    SUITES_FAIL=$((SUITES_FAIL+1))
    echo -e "${RED}  Suite $name FAILED (exit $rc)${NC}"
  else
    echo -e "${GREEN}  Suite $name PASSED${NC}"
  fi
}

# Also run cmake script-mode test if cmake is available
run_cmake_suite() {
  local file="$SCRIPT_DIR/test_cmake_to_msys.cmake"
  if [[ ! -f "$file" ]]; then
    echo "SKIP test_cmake_to_msys.cmake — not found"
    return
  fi
  if ! command -v cmake >/dev/null 2>&1; then
    echo "SKIP test_cmake_to_msys.cmake — cmake not in PATH"
    return
  fi
  echo ""
  echo "------------------------------------------------------------"
  echo "Running test_cmake_to_msys.cmake (cmake -P)"
  echo "------------------------------------------------------------"
  set +e
  cmake -P "$file" 2>&1
  rc=$?
  set -e
  SUITES_RUN=$((SUITES_RUN+1))
  if [[ $rc -ne 0 ]]; then
    SUITES_FAIL=$((SUITES_FAIL+1))
    echo -e "${RED}  Suite test_cmake_to_msys.cmake FAILED${NC}"
  else
    echo -e "${GREEN}  Suite test_cmake_to_msys.cmake PASSED${NC}"
  fi
  # cmake suite doesn't use _assert.sh, so manually add to tmp
  if [[ $rc -eq 0 ]]; then
    echo "test_cmake_to_msys:9:0:0" >> "$WSL_TEST_TMP"
  else
    echo "test_cmake_to_msys:0:1:0" >> "$WSL_TEST_TMP"
  fi
}

echo "WSL Tests — imagedecoder-houri"
echo "Host: $(uname -a)"
echo "Date: $(date -u +%Y-%m-%dT%H:%M:%SZ)"
if command -v wsl >/dev/null 2>&1; then
  echo "wsl: $(wsl --version 2>&1 | head -n1 || echo 'wsl found')"
else
  echo "wsl: not in PATH (running on Linux without WSL is ok for non-Windows suites)"
fi
echo ""

for f in "$SCRIPT_DIR"/test_*.sh; do
  # _assert.sh is not a suite
  if [[ "$(basename "$f")" == "_assert.sh" ]]; then continue; fi
  run_suite "$f"
done

run_cmake_suite

echo ""
echo "============================================================"
echo "Summary"
echo "============================================================"
if [[ -f "$WSL_TEST_TMP" ]]; then
  while IFS=: read -r name p f s; do
    TOTAL_PASS=$((TOTAL_PASS + p))
    TOTAL_FAIL=$((TOTAL_FAIL + f))
    TOTAL_SKIP=$((TOTAL_SKIP + s))
  done < "$WSL_TEST_TMP"
  rm -f "$WSL_TEST_TMP"
fi

echo "Suites: $SUITES_RUN run, $SUITES_FAIL failed"
echo "Cases : $TOTAL_PASS passed, $TOTAL_FAIL failed, $TOTAL_SKIP skipped"
echo ""

if [[ $TOTAL_FAIL -eq 0 && $SUITES_FAIL -eq 0 ]]; then
  echo -e "${GREEN}ALL TESTS PASSED${NC}"
  exit 0
else
  echo -e "${RED}SOME TESTS FAILED${NC}"
  echo "Fixes:"
  echo "  - Stale .cxx cache with empty --cross-file: rm -rf external/imagedecoder-houri/library/.cxx"
  echo "  - Missing WSL tools: wsl bash -c 'sudo apt update && sudo apt install -y build-essential autoconf automake libtool pkg-config meson ninja-build cmake python3'"
  exit 1
fi
