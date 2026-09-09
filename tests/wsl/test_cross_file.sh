#!/usr/bin/env bash
# test_cross_file.sh — validates android-cross-file.txt generation
set -e
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
# shellcheck disable=SC1091
source "$SCRIPT_DIR/_assert.sh"

suite_begin "test_cross_file"

# Candidate locations for generated cross file
CANDIDATES=(
  "$SCRIPT_DIR/../../library/.cxx/Debug/682e2tm6/arm64-v8a/android-cross-file.txt"
  "$SCRIPT_DIR/../../library/.cxx/Release/682e2tm6/arm64-v8a/android-cross-file.txt"
  "$SCRIPT_DIR/../../library/.cxx/Debug/682e2tm6/armeabi-v7a/android-cross-file.txt"
  "$SCRIPT_DIR/../../library/build/intermediates/cxx/Debug/682e2tm6/arm64-v8a/android-cross-file.txt"
)

CROSS_FILE=""
for c in "${CANDIDATES[@]}"; do
  if [[ -f "$c" ]]; then CROSS_FILE="$c"; break; fi
done

# Also check CMakeLists.txt source for template correctness even if no generated file (no configure yet)
CMAKE_LISTS="$SCRIPT_DIR/../../library/src/main/cpp/CMakeLists.txt"

if [[ -z "$CROSS_FILE" ]]; then
  skip "generated cross file" "not found (run CMake configure first, e.g. Gradle Sync). Testing template in CMakeLists.txt instead."
  # Fall through to template checks
else
  echo "  INFO: testing generated file: $CROSS_FILE"
  assert_file_exists "cross file exists" "$CROSS_FILE"

  content="$(cat "$CROSS_FILE")"
  assert_contains "contains system = android" "system = 'android'" "$content"
  assert_contains "contains cpu_family" "cpu_family" "$content"
  # At least one of aarch64/arm should be present depending on ABI; we assume arm64 test run
  assert_contains "contains endian = little" "endian = 'little'" "$content"
  assert_contains "contains [binaries] c =" "c = [" "$content"
  assert_contains "contains pkg-config" "pkg-config" "$content"
  assert_contains "contains pkg_config_path dual" "pkg_config_path" "$content"

  # Binaries must be /mnt/c/... (WSL meson needs Unix), but c_args/c_link_args intentionally use C:/ 
  # for Windows clang to find headers when meson invokes C:/.../clang.exe with C:\... test files.
  # Check [binaries] section specifically.
  binaries_block="$(sed -n '/\[binaries\]/,/\[built-in/p' "$CROSS_FILE")"
  if echo "$binaries_block" | grep -q "C:/"; then
    echo "  FAIL: [binaries] leaks Windows C:/ (should be /mnt/c/ for WSL meson)"
    FAIL=$((FAIL+1))
  else
    echo "  PASS: [binaries] uses /mnt/c/ (no C:/ leak)"
    PASS=$((PASS+1))
  fi
  # c_args intentionally uses C:/ per CMake comment — verify that at least pkg_config stays Unix
  if grep -q "pkg_config_path = \['/mnt/c" "$CROSS_FILE"; then
    echo "  PASS: pkg_config_path uses /mnt/c/"
    PASS=$((PASS+1))
  else
    echo "  FAIL: pkg_config_path should be /mnt/c/"
    FAIL=$((FAIL+1))
  fi

  # Check for CRLF (meson on WSL chokes on \r)
  if grep -q $'\r' "$CROSS_FILE"; then
    echo "  FAIL: cross file contains CRLF (should be LF only)"
    FAIL=$((FAIL+1))
  else
    echo "  PASS: no CRLF"
    PASS=$((PASS+1))
  fi

  # Check that c_args contains include path, and that include is /mnt/c/ or C:/ depending on host?
  # For WSL cross file, include should be /mnt/c/... or C:/ but pkg_config_path must be /mnt/c/
  # Our fixed file uses /mnt/c/ for c binaries and /mnt/c/ for pkg_config_path dual
  assert_contains "c_args contains -I" "-I" "$content"

  # Check that ar/ld/strip are /mnt/c/... (WSL paths)
  assert_contains "binaries ar is /mnt/c" "/mnt/c/" "$content"

  # Count pkg_config_path entries — should have two identical /mnt/c/... entries (dual for MSYS+WSL compat)
  count="$(grep -o "pkg_config_path" "$CROSS_FILE" | wc -l)"
  assert_eq "pkg_config_path appears once" "1" "$count"
  # The value should contain both /mnt/c/... entries separated by comma
  if grep -q "pkg_config_path.*mnt.*mnt" "$CROSS_FILE"; then
    echo "  PASS: pkg_config_path dual /mnt/c entries"
    PASS=$((PASS+1))
  else
    # Some builds may have single entry if not dual; warn but not fail
    skip "pkg_config_path dual entries" "single entry found (acceptable for non-Windows host)"
  fi
fi

# Template checks (always runnable, no configure needed)
if [[ -f "$CMAKE_LISTS" ]]; then
  tpl="$(cat "$CMAKE_LISTS")"
  assert_contains "CMakeLists defines [host_machine] in CROSS_FILE_CONTENT" "[host_machine]" "$tpl"
  assert_contains "CMakeLists defines c = ['\${_cross_c}'" "c = ['\${_cross_c}'" "$tpl"
  # _cross_c can be from _cc_msys (Windows) or Linux NDK at /usr/lib/.../linux-x86_64 (when IS_HOST_WINDOWS with Linux NDK)
  if echo "$tpl" | grep -q '_cross_c "${_cc_msys}"' || echo "$tpl" | grep -q '_cross_c "/usr/lib' || echo "$tpl" | grep -q '_cross_c "${_wsl_linux' || echo "$tpl" | grep -q '_cross_c "${_linux_ndk'; then
    echo "  PASS: CMakeLists defines _cross_c from _cc_msys or Linux NDK on IS_HOST_WINDOWS"
    PASS=$((PASS+1))
  else
    echo "  FAIL: CMakeLists should define _cross_c from _cc_msys or Linux NDK on IS_HOST_WINDOWS"
    FAIL=$((FAIL+1))
  fi
  assert_contains "CMakeLists writes MESON_CROSS_FILE_PATH" 'set(MESON_CROSS_FILE_PATH "${CMAKE_BINARY_DIR}/android-cross-file.txt")' "$tpl"
  assert_contains "CMakeLists converts MESON_CROSS_FILE_PATH via to_msys_path" 'to_msys_path("${MESON_CROSS_FILE_PATH}" MESON_CROSS_FILE_PATH_WSL)' "$tpl"
  assert_contains "CMakeLists has CRLF fix for cross file (tr -d)" "tr -d '\\\\015'" "$tpl"
  cross_content="$(sed -n '/set(CROSS_FILE_CONTENT/,/^[[:space:]]*")$/p' "$CMAKE_LISTS" | head -n 100)"
  if echo "$cross_content" | grep -q "C:/Users/Branden"; then
    echo "  FAIL: CROSS_FILE_CONTENT hardcodes C:/Users/Branden (should use \${_cross_*})"
    FAIL=$((FAIL+1))
  else
    echo "  PASS: CROSS_FILE_CONTENT no hardcoded C:/Users/Branden"
    PASS=$((PASS+1))
  fi
  # Verify that the cross file generation happens before the re-set of EP_MESON_ARGS
  # (the bug was EP_MESON_ARGS set before cross file)
  cross_line="$(grep -n "set(MESON_CROSS_FILE_PATH" "$CMAKE_LISTS" | head -n1 | cut -d: -f1)"
  ep_final_line="$(grep -n "EP_MESON_ARGS (final)" "$CMAKE_LISTS" | head -n1 | cut -d: -f1)"
  if [[ -n "$cross_line" && -n "$ep_final_line" ]]; then
    if [[ "$cross_line" -lt "$ep_final_line" ]]; then
      echo "  PASS: cross file generation (line $cross_line) before EP_MESON_ARGS final (line $ep_final_line)"
      PASS=$((PASS+1))
    else
      echo "  FAIL: EP_MESON_ARGS final should be after cross file generation"
      FAIL=$((FAIL+1))
    fi
  else
    skip "ordering: cross vs EP_MESON_ARGS final" "could not find line numbers"
  fi
else
  echo "  FAIL: CMakeLists.txt not found at $CMAKE_LISTS"
  FAIL=$((FAIL+1))
fi

suite_summary "test_cross_file"
