#!/usr/bin/env bash
# test_wsl_detection.sh — validates WSL + tool presence as CMakeLists.txt expects
set -e
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
# shellcheck disable=SC1091
source "$SCRIPT_DIR/_assert.sh"

suite_begin "test_wsl_detection"

is_windows=false
if [[ -f "C:/Windows/System32/wsl.exe" ]] || [[ -f "/mnt/c/Windows/System32/wsl.exe" ]] || grep -qi "microsoft" /proc/version 2>/dev/null; then
  is_windows=true
fi

# 1: WSL executable discoverable (via Windows path or via PATH)
found_wsl=false
for cand in "C:/Windows/System32/wsl.exe" "C:/Windows/Sysnative/wsl.exe" "/mnt/c/Windows/System32/wsl.exe" "/usr/bin/wsl" "$(command -v wsl 2>/dev/null || echo none)"; do
  if [[ -f "$cand" ]] || [[ -x "$cand" ]]; then
    found_wsl=true
    echo "  INFO: wsl candidate: $cand"
    break
  fi
done
if command -v wsl >/dev/null 2>&1; then
  found_wsl=true
fi
if $found_wsl; then
  echo "  PASS: wsl executable found"
  PASS=$((PASS+1))
else
  # On Linux without WSL, this is a skip not a fail (host is Linux, not Windows)
  if grep -qi "microsoft" /proc/version 2>/dev/null || [[ -d "/mnt/c/Windows/System32" ]]; then
    echo "  FAIL: wsl not found but host looks like WSL/Windows (expected wsl.exe)"
    FAIL=$((FAIL+1))
  else
    skip "wsl executable" "host is Linux without WSL (not Windows) — WSL check N/A"
  fi
fi

# 2: wsl --status (or wsl echo) works if WSL is present
if command -v wsl >/dev/null 2>&1; then
  set +e
  out="$(wsl --status 2>&1 | head -n5 || wsl echo ok 2>&1 | head -n5)"
  rc=$?
  set -e
  if [[ $rc -eq 0 ]] || echo "$out" | grep -qi "WSL\|Default\|ok"; then
    echo "  PASS: wsl --status / echo ok (rc=$rc)"
    PASS=$((PASS+1))
  else
    echo "  FAIL: wsl --status failed rc=$rc out=$out"
    FAIL=$((FAIL+1))
  fi
else
  skip "wsl --status" "wsl not in PATH on this host"
fi

# Helper to test via wsl bash -c vs directly
run_wsl_bash() {
  if command -v wsl >/dev/null 2>&1; then
    wsl bash -c "$1" 2>&1
  else
    bash -c "$1" 2>&1
  fi
}

# 3: wsl bash exists
if run_wsl_bash "echo ok" | grep -q ok; then
  echo "  PASS: wsl bash works"
  PASS=$((PASS+1))
else
  echo "  FAIL: wsl bash not working"
  FAIL=$((FAIL+1))
fi

# 4: meson in WSL
if run_wsl_bash "command -v meson >/dev/null 2>&1 && echo FOUND || echo MISSING" | grep -q FOUND; then
  ver="$(run_wsl_bash "meson --version 2>&1" | head -n1)"
  echo "  PASS: wsl meson found ($ver)"
  PASS=$((PASS+1))
else
  echo "  FAIL: wsl meson not found — run: wsl bash -c 'sudo apt update && sudo apt install -y meson ninja-build'"
  FAIL=$((FAIL+1))
fi

# 5: ninja in WSL
if run_wsl_bash "command -v ninja >/dev/null 2>&1 && echo FOUND || echo MISSING" | grep -q FOUND; then
  ver="$(run_wsl_bash "ninja --version 2>&1" | head -n1)"
  echo "  PASS: wsl ninja found ($ver)"
  PASS=$((PASS+1))
else
  echo "  FAIL: wsl ninja missing — sudo apt install -y ninja-build"
  FAIL=$((FAIL+1))
fi

# 6: make in WSL
if run_wsl_bash "command -v make >/dev/null 2>&1 && echo FOUND || echo MISSING" | grep -q FOUND; then
  ver="$(run_wsl_bash "make --version 2>&1" | head -n1)"
  echo "  PASS: wsl make found ($ver)"
  PASS=$((PASS+1))
else
  echo "  FAIL: wsl make missing — sudo apt install -y make build-essential"
  FAIL=$((FAIL+1))
fi

# 7: pkg-config in WSL
if run_wsl_bash "command -v pkg-config >/dev/null 2>&1 && echo FOUND || echo MISSING" | grep -q FOUND; then
  echo "  PASS: wsl pkg-config found"
  PASS=$((PASS+1))
else
  echo "  FAIL: wsl pkg-config missing — sudo apt install -y pkg-config"
  FAIL=$((FAIL+1))
fi

# 8: autoreconf in WSL (needed for lcms2/libffi autogen.sh)
if run_wsl_bash "command -v autoreconf >/dev/null 2>&1 && echo FOUND || echo MISSING" | grep -q FOUND; then
  echo "  PASS: wsl autoreconf found"
  PASS=$((PASS+1))
else
  echo "  FAIL: wsl autoreconf missing — sudo apt install -y autoconf automake libtool"
  FAIL=$((FAIL+1))
fi

# 9: wslpath in WSL
if run_wsl_bash "command -v wslpath >/dev/null 2>&1 && echo FOUND || echo MISSING" | grep -q FOUND; then
  got="$(run_wsl_bash "wslpath -u 'C:/Users/Branden' 2>&1")"
  assert_eq "wslpath C:/ -> /mnt/c" "/mnt/c/Users/Branden" "$got"
else
  echo "  FAIL: wslpath missing in WSL"
  FAIL=$((FAIL+1))
fi

# 10: cmake in WSL (used for inner cmake deps if needed)
if run_wsl_bash "command -v cmake >/dev/null 2>&1 && echo FOUND || echo MISSING" | grep -q FOUND; then
  ver="$(run_wsl_bash "cmake --version 2>&1" | head -n1)"
  echo "  PASS: wsl cmake found ($ver)"
  PASS=$((PASS+1))
else
  skip "wsl cmake" "not found (outer Windows cmake is used for parent, WSL cmake optional)"
fi

# 11: Ninja without space (the Program Files bug)
# On Windows, Meson's C:/Program Files/Meson/ninja.exe breaks cmake -E env NINJA=... because space splits NAME=VALUE.
# CMakeLists.txt prefers Android SDK ninja at C:/.../Android/Sdk/cmake/3.22.1/bin/ninja.exe
SDK_NINJA="/mnt/c/Users/Branden/AppData/Local/Android/Sdk/cmake/3.22.1/bin/ninja.exe"
if [[ -f "$SDK_NINJA" ]] || [[ -f "C:/Users/Branden/AppData/Local/Android/Sdk/cmake/3.22.1/bin/ninja.exe" ]]; then
  echo "  PASS: Android SDK ninja exists (no space, safe for cmake -E env)"
  PASS=$((PASS+1))
else
  skip "Android SDK ninja" "not found at $SDK_NINJA (install via SDK Manager: cmake 3.22.1)"
fi

if command -v ninja >/dev/null 2>&1; then
  ninja_path="$(command -v ninja)"
  if [[ "$ninja_path" == *"Program Files"* ]]; then
    echo "  FAIL: ninja at '$ninja_path' contains space (would break cmake -E env NINJA=...). Use SDK ninja."
    FAIL=$((FAIL+1))
  else
    echo "  PASS: ninja path has no space: $ninja_path"
    PASS=$((PASS+1))
  fi
else
  skip "ninja path space check" "ninja not in PATH"
fi

# 12: Verify CMakeLists.txt does not rely on MSYS/Git Bash (WSL is single path)
CMAKE_LISTS="$SCRIPT_DIR/../../library/src/main/cpp/CMakeLists.txt"
if grep -q "MSYS2/Git Bash is NOT supported — WSL is the single only path" "$CMAKE_LISTS"; then
  echo "  PASS: CMakeLists documents WSL as single Windows path"
  PASS=$((PASS+1))
else
  echo "  FAIL: CMakeLists missing WSL single-path documentation"
  FAIL=$((FAIL+1))
fi

# 13: Verify CMakeLists.txt FATAL_ERRORs if WSL missing on Windows (no silent fallback)
if grep -q "WSL is required on Windows" "$CMAKE_LISTS"; then
  echo "  PASS: CMakeLists has WSL FATAL_ERROR on Windows"
  PASS=$((PASS+1))
else
  echo "  FAIL: CMakeLists should FATAL if WSL missing on WIN32"
  FAIL=$((FAIL+1))
fi

suite_summary "test_wsl_detection"
