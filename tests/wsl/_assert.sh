#!/usr/bin/env bash
# _assert.sh — shared assertion helpers for WSL test suites
# Source this from each test_*.sh

PASS=0
FAIL=0
SKIP=0
SUITE_NAME=""

suite_begin() {
  SUITE_NAME="$1"
  PASS=0; FAIL=0; SKIP=0
  echo "=== $SUITE_NAME ==="
}

assert_eq() {
  local desc="$1" expected="$2" actual="$3"
  if [[ "$expected" == "$actual" ]]; then
    echo "  PASS: $desc"
    PASS=$((PASS+1))
  else
    echo "  FAIL: $desc"
    echo "    expected: '$expected'"
    echo "    actual  : '$actual'"
    FAIL=$((FAIL+1))
  fi
}

assert_contains() {
  local desc="$1" needle="$2" haystack="$3"
  if [[ "$haystack" == *"$needle"* ]]; then
    echo "  PASS: $desc"
    PASS=$((PASS+1))
  else
    echo "  FAIL: $desc"
    echo "    expected to contain: '$needle'"
    echo "    haystack: '$haystack'"
    FAIL=$((FAIL+1))
  fi
}

assert_not_contains() {
  local desc="$1" needle="$2" haystack="$3"
  if [[ "$haystack" != *"$needle"* ]]; then
    echo "  PASS: $desc"
    PASS=$((PASS+1))
  else
    echo "  FAIL: $desc"
    echo "    expected NOT to contain: '$needle'"
    echo "    haystack: '$haystack'"
    FAIL=$((FAIL+1))
  fi
}

assert_file_exists() {
  local desc="$1" path="$2"
  if [[ -f "$path" ]]; then
    echo "  PASS: $desc"
    PASS=$((PASS+1))
  else
    echo "  FAIL: $desc — missing file: $path"
    FAIL=$((FAIL+1))
  fi
}

assert_file_not_exists() {
  local desc="$1" path="$2"
  if [[ ! -e "$path" ]]; then
    echo "  PASS: $desc"
    PASS=$((PASS+1))
  else
    echo "  FAIL: $desc — should not exist but found: $path"
    FAIL=$((FAIL+1))
  fi
}

skip() {
  local desc="$1" reason="$2"
  echo "  SKIP: $desc — $reason"
  SKIP=$((SKIP+1))
}

suite_summary() {
  local name="${1:-$SUITE_NAME}"
  echo ""
  echo "$name: $PASS passed, $FAIL failed, $SKIP skipped"
  # export for run_all.sh aggregation via temp file
  if [[ -n "${WSL_TEST_TMP:-}" ]]; then
    echo "$name:$PASS:$FAIL:$SKIP" >> "$WSL_TEST_TMP"
  fi
  if [[ $FAIL -ne 0 ]]; then
    return 1
  fi
  return 0
}
