#!/usr/bin/env bash
# test_to_msys_path.sh — validates CMake to_msys_path() via bash reimplementation
# Mirrors logic in library/src/main/cpp/CMakeLists.txt: function(to_msys_path)
# Must stay in sync with test_cmake_to_msys.cmake which runs the real CMake function.
set -e
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
# shellcheck disable=SC1091
source "$SCRIPT_DIR/_assert.sh"

suite_begin "test_to_msys_path"

# Reimplementation of CMake to_msys_path for WSL host (IS_HOST_WINDOWS=TRUE branch)
# This is the bash equivalent of the CMake function when IS_HOST_WINDOWS is true.
to_msys_path() {
  local win_path="$1"
  local _tmp
  # Normalize backslashes
  _tmp="${win_path//\\//}"
  # Already /mnt/c/...
  if [[ "$_tmp" =~ ^/mnt/[a-z]/ ]]; then
    echo "$_tmp"; return
  fi
  # Legacy /c/... -> upgrade to /mnt/c/ on WIN32
  if [[ "$_tmp" =~ ^/[a-z]/ ]]; then
    # IS_HOST_WINDOWS=true path
    echo "$_tmp" | sed -E 's|^/([a-z])/|/mnt/\1/|'
    return
  fi
  # pure Unix absolute like /usr/local
  if [[ "$_tmp" =~ ^/[^/] ]]; then
    echo "$_tmp"; return
  fi
  # Windows drive letter C:/...
  if [[ "$_tmp" =~ ^([A-Za-z]):/(.*) ]]; then
    local drive="${BASH_REMATCH[1],,}"
    local rest="${BASH_REMATCH[2]}"
    echo "/mnt/${drive}/${rest}"
    return
  fi
  echo "$_tmp"
}

# Also need real wslpath for comparison where available
has_wslpath=false
if command -v wslpath >/dev/null 2>&1; then has_wslpath=true; fi

echo "=== test_to_msys_path ==="

assert_eq "C:/Users/Branden -> /mnt/c/Users/Branden" \
  "/mnt/c/Users/Branden" "$(to_msys_path "C:/Users/Branden")"

assert_eq "C:\\Users\\Branden (backslash) -> /mnt/c/Users/Branden" \
  "/mnt/c/Users/Branden" "$(to_msys_path "C:\\Users\\Branden")"

assert_eq "D:/project -> /mnt/d/project" \
  "/mnt/d/project" "$(to_msys_path "D:/project")"

assert_eq "lowercase c:/foo -> /mnt/c/foo" \
  "/mnt/c/foo" "$(to_msys_path "c:/foo")"

assert_eq "already /mnt/c/Users stays" \
  "/mnt/c/Users/Branden" "$(to_msys_path "/mnt/c/Users/Branden")"

assert_eq "legacy /c/Users -> /mnt/c/Users (WIN32 upgrade)" \
  "/mnt/c/Users/Branden" "$(to_msys_path "/c/Users/Branden")"

assert_eq "/usr/local stays" \
  "/usr/local" "$(to_msys_path "/usr/local")"

assert_eq "/mnt/d/foo stays" \
  "/mnt/d/foo" "$(to_msys_path "/mnt/d/foo")"

assert_eq "C:/ -> /mnt/c/" \
  "/mnt/c/" "$(to_msys_path "C:/")"

assert_eq "empty stays empty" \
  "" "$(to_msys_path "")"

assert_eq "relative foo/bar stays" \
  "foo/bar" "$(to_msys_path "foo/bar")"

assert_eq "C:/Program Files/Meson with space" \
  "/mnt/c/Program Files/Meson" "$(to_msys_path "C:/Program Files/Meson")"

assert_eq "C:/A/B/C nested" \
  "/mnt/c/A/B/C" "$(to_msys_path "C:/A/B/C")"

assert_eq "C:/Users/.../fk/include (cross file include)" \
  "/mnt/c/Users/Branden/komikku-pineapple/external/imagedecoder-houri/library/.cxx/Debug/682e2tm6/arm64-v8a/fk/include" \
  "$(to_msys_path "C:/Users/Branden/komikku-pineapple/external/imagedecoder-houri/library/.cxx/Debug/682e2tm6/arm64-v8a/fk/include")"

assert_eq "drive letter lowercased: E:/Foo -> /mnt/e/Foo" \
  "/mnt/e/Foo" "$(to_msys_path "E:/Foo")"

# Compare with wslpath where available (ground truth on WSL)
if $has_wslpath; then
  for p in "C:/Users/Branden" "C:/Program Files/test"; do
    expected="$(wslpath -u "$p" 2>/dev/null || echo "wslpath-fail")"
    if [[ "$expected" == "wslpath-fail" ]]; then
      skip "wslpath parity: $p" "wslpath failed (drive not mounted?)"
      continue
    fi
    actual="$(to_msys_path "$p")"
    assert_eq "wslpath parity: $p" "$expected" "$actual"
  done
  # D: drive may not be mounted in WSL (wslpath fails), test manual fallback instead
  actual="$(to_msys_path "D:/foo")"
  assert_eq "D:/foo manual fallback -> /mnt/d/foo (even if wslpath fails)" "/mnt/d/foo" "$actual"
else
  echo "  SKIP: wslpath not available, skipping parity checks"
fi

# Also test that non-Windows branch leaves /c/ alone (simulate by calling with IS_HOST_WINDOWS=false)
# For this we need a second function that mimics non-Windows (leaves /c/ as /c/)
to_msys_path_linux() {
  local win_path="$1"
  local _tmp="${win_path//\\//}"
  if [[ "$_tmp" =~ ^/mnt/[a-z]/ ]]; then echo "$_tmp"; return; fi
  if [[ "$_tmp" =~ ^/[a-z]/ ]]; then echo "$_tmp"; return; fi
  if [[ "$_tmp" =~ ^/[^/] ]]; then echo "$_tmp"; return; fi
  if [[ "$_tmp" =~ ^([A-Za-z]):/(.*) ]]; then
    local drive="${BASH_REMATCH[1],,}"
    local rest="${BASH_REMATCH[2]}"
    # On Linux non-WSL, would be /c/...; on WSL /mnt/c/...; we test both
    if [[ -f /proc/version ]] && grep -qi "microsoft\|WSL" /proc/version 2>/dev/null; then
      echo "/mnt/${drive}/${rest}"
    else
      echo "/${drive}/${rest}"
    fi
    return
  fi
  echo "$_tmp"
}
assert_eq "linux /c/Users stays /c/Users (non-Windows)" \
  "/c/Users/test" "$(to_msys_path_linux "/c/Users/test")"

suite_summary "test_to_msys_path"
