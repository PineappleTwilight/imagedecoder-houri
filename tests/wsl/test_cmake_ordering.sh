#!/usr/bin/env bash
# test_cmake_ordering.sh — guards the EP_MESON_ARGS ordering bug
# The bug: EP_MESON_ARGS set at top (line ~511) before MESON_CROSS_FILE_PATH_WSL defined at ~680,
# so it expanded to --cross-file= (empty) and meson failed.
set -e
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
# shellcheck disable=SC1091
source "$SCRIPT_DIR/_assert.sh"

suite_begin "test_cmake_ordering"

CMAKE_LISTS="$SCRIPT_DIR/../../library/src/main/cpp/CMakeLists.txt"

if [[ ! -f "$CMAKE_LISTS" ]]; then
  echo "  FAIL: CMakeLists.txt not found"
  FAIL=$((FAIL+1))
  suite_summary "test_cmake_ordering"
  exit 1
fi

# 1: Early EP_MESON_ARGS exists (top, near ProcessorCount)
early_line="$(grep -n "set(EP_MESON_ARGS" "$CMAKE_LISTS" | head -n1 | cut -d: -f1)"
if [[ -n "$early_line" ]]; then
  echo "  PASS: early EP_MESON_ARGS found at line $early_line"
  PASS=$((PASS+1))
else
  echo "  FAIL: early EP_MESON_ARGS not found"
  FAIL=$((FAIL+1))
fi

# 2: Re-set EP_MESON_ARGS after cross file (fix)
final_line="$(grep -n "EP_MESON_ARGS (final)" "$CMAKE_LISTS" | head -n1 | cut -d: -f1)"
if [[ -n "$final_line" ]]; then
  echo "  PASS: final EP_MESON_ARGS marker at line $final_line"
  PASS=$((PASS+1))
else
  echo "  FAIL: final EP_MESON_ARGS marker missing (fix not applied)"
  FAIL=$((FAIL+1))
fi

# 3: Cross file generation line
cross_line="$(grep -n "set(MESON_CROSS_FILE_PATH" "$CMAKE_LISTS" | head -n1 | cut -d: -f1)"
if [[ -n "$cross_line" ]]; then
  echo "  PASS: MESON_CROSS_FILE_PATH set at line $cross_line"
  PASS=$((PASS+1))
else
  echo "  FAIL: MESON_CROSS_FILE_PATH not found"
  FAIL=$((FAIL+1))
fi

# 4: Ordering: early < cross < final
if [[ -n "$early_line" && -n "$cross_line" && -n "$final_line" ]]; then
  if [[ "$early_line" -lt "$cross_line" && "$cross_line" -lt "$final_line" ]]; then
    echo "  PASS: ordering early($early_line) < cross($cross_line) < final($final_line)"
    PASS=$((PASS+1))
  else
    echo "  FAIL: wrong ordering early=$early_line cross=$cross_line final=$final_line (need early < cross < final)"
    FAIL=$((FAIL+1))
  fi
fi

# 5: Final EP_MESON_ARGS uses _WSL on IS_HOST_WINDOWS branch
if grep -A3 "Re-set EP_MESON_ARGS" "$CMAKE_LISTS" | grep -q "MESON_CROSS_FILE_PATH_WSL"; then
  echo "  PASS: final EP_MESON_ARGS uses _WSL path for IS_HOST_WINDOWS"
  PASS=$((PASS+1))
else
  echo "  FAIL: final EP_MESON_ARGS should reference _WSL"
  FAIL=$((FAIL+1))
fi

# 6: All ExternalProject_Add that use EP_MESON_ARGS come after final
# Find first ExternalProject that uses EP_MESON_ARGS (dav1d) and ensure it's after final
first_ep_line="$(grep -n "ExternalProject_Add(ep_dav1d" "$CMAKE_LISTS" 2>/dev/null | cut -d: -f1 | head -n1)"
# dav1d is in include file, not main. Check includes after final
include_line="$(grep -n 'include("cmake/dav1d.cmake")' "$CMAKE_LISTS" | cut -d: -f1 | head -n1)"
if [[ -n "$include_line" && -n "$final_line" ]]; then
  if [[ "$final_line" -lt "$include_line" ]]; then
    echo "  PASS: EP_MESON_ARGS final ($final_line) before dav1d include ($include_line)"
    PASS=$((PASS+1))
  else
    echo "  FAIL: dav1d include ($include_line) should be after final EP_MESON_ARGS ($final_line)"
    FAIL=$((FAIL+1))
  fi
else
  skip "EP_MESON_ARGS before includes" "could not find include line"
fi

# 7: Stale build.ninja check — if .cxx exists, ensure no empty --cross-file=
BUILD_NINJA=""
for cand in "$SCRIPT_DIR/../../library/.cxx/Debug/682e2tm6/arm64-v8a/build.ninja" "$SCRIPT_DIR/../../library/.cxx/Release/682e2tm6/arm64-v8a/build.ninja"; do
  if [[ -f "$cand" ]]; then BUILD_NINJA="$cand"; break; fi
done
if [[ -n "$BUILD_NINJA" ]]; then
  if grep -q -- "--cross-file= --" "$BUILD_NINJA"; then
    echo "  FAIL: build.ninja contains empty --cross-file= (stale cache, need rm -rf .cxx)"
    FAIL=$((FAIL+1))
  else
    echo "  PASS: build.ninja has no empty --cross-file="
    PASS=$((PASS+1))
  fi
  if grep -q -- "--cross-file=/mnt/c" "$BUILD_NINJA"; then
    echo "  PASS: build.ninja contains /mnt/c cross-file"
    PASS=$((PASS+1))
  else
    echo "  FAIL: build.ninja missing /mnt/c cross-file (should be /mnt/c/... for WSL)"
    FAIL=$((FAIL+1))
  fi
else
  skip "build.ninja checks" "no build.ninja yet (run Gradle Sync first)"
fi

count="$(grep -c "set(EP_MESON_ARGS" "$CMAKE_LISTS")"
if [[ "$count" -eq 4 ]]; then
  echo "  PASS: exactly 4 EP_MESON_ARGS definitions (2 branches x 2 sites: early + final re-set)"
  PASS=$((PASS+1))
else
  echo "  FAIL: expected 4 EP_MESON_ARGS definitions, found $count"
  FAIL=$((FAIL+1))
fi

# 9: meson_helper.sh template guard exists (already tested elsewhere, but ordering suite also checks)
if grep -q "empty --cross-file" "$CMAKE_LISTS"; then
  echo "  PASS: meson_helper template has empty guard"
  PASS=$((PASS+1))
else
  echo "  FAIL: meson_helper template missing empty guard"
  FAIL=$((FAIL+1))
fi

suite_summary "test_cmake_ordering"
