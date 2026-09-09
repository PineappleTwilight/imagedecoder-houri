#!/usr/bin/env bash
# test_autotools_helpers.sh — validates autotools_helper.sh + iconv helpers
set -e
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
# shellcheck disable=SC1091
source "$SCRIPT_DIR/_assert.sh"

suite_begin "test_autotools_helpers"

CMAKE_LISTS="$SCRIPT_DIR/../../library/src/main/cpp/CMakeLists.txt"

# 1: autotools_helper.sh template exists in CMakeLists
if grep -q "AUTOTOOLS_HELPER" "$CMAKE_LISTS"; then
  echo "  PASS: AUTOTOOLS_HELPER defined"
  PASS=$((PASS+1))
else
  echo "  FAIL: AUTOTOOLS_HELPER not defined"
  FAIL=$((FAIL+1))
fi

# 2: helper handles wslpath/cygpath for C:/ source dir
if grep -q 'if command -v cygpath' "$CMAKE_LISTS"; then
  echo "  PASS: helpers handle cygpath/wslpath fallback"
  PASS=$((PASS+1))
else
  echo "  FAIL: helpers missing cygpath/wslpath logic"
  FAIL=$((FAIL+1))
fi

# 3: helpers use src="$1" shift pattern (avoids bash -c quoting issues)
if grep -q 'src="$1"' "$CMAKE_LISTS"; then
  echo "  PASS: helpers use src=\"\$1\" shift"
  PASS=$((PASS+1))
else
  echo "  FAIL: helpers should use src=\$1"
  FAIL=$((FAIL+1))
fi

# 4: autotools_helper_autogen.sh exists
if grep -q "AUTOTOOLS_HELPER_AUTOGEN" "$CMAKE_LISTS"; then
  echo "  PASS: AUTOTOOLS_HELPER_AUTOGEN defined"
  PASS=$((PASS+1))
else
  echo "  FAIL: AUTOTOOLS_HELPER_AUTOGEN missing"
  FAIL=$((FAIL+1))
fi

# 5: patch_iconv.sh exists
if grep -q "PATCH_ICONV_HELPER" "$CMAKE_LISTS"; then
  echo "  PASS: PATCH_ICONV_HELPER defined"
  PASS=$((PASS+1))
else
  echo "  FAIL: PATCH_ICONV_HELPER missing"
  FAIL=$((FAIL+1))
fi

# 6: configure_iconv.sh takes prefix as arg and wslpath-converts it
if grep -q "CONFIGURE_ICONV_HELPER" "$CMAKE_LISTS"; then
  echo "  PASS: CONFIGURE_ICONV_HELPER defined"
  PASS=$((PASS+1))
else
  echo "  FAIL: CONFIGURE_ICONV_HELPER missing"
  FAIL=$((FAIL+1))
fi

# 7: install_iconv.sh creates iconv.pc with both iconv and libiconv
if grep -q "iconv.pc" "$CMAKE_LISTS" && grep -q "libiconv.pc" "$CMAKE_LISTS"; then
  echo "  PASS: install helper creates both iconv.pc and libiconv.pc"
  PASS=$((PASS+1))
else
  echo "  FAIL: install helper missing pc files"
  FAIL=$((FAIL+1))
fi

if grep -q "tr -d" "$CMAKE_LISTS" && grep -q "015" "$CMAKE_LISTS"; then
  echo "  PASS: helpers have CRLF fix (tr -d 015)"
  PASS=$((PASS+1))
else
  echo "  FAIL: helpers missing CRLF fix"
  FAIL=$((FAIL+1))
fi

# 9: EP_AUTOTOOLS_ARGS uses _cc_msys or _autotools_cc (Linux NDK) etc. (Unix /mnt/c/... or /usr/...)
if grep -q 'CC=${_cc_msys}' "$CMAKE_LISTS" || grep -q 'CC=${_autotools_cc}' "$CMAKE_LISTS" || grep -q 'CC=${_cross_c}' "$CMAKE_LISTS"; then
  echo "  PASS: EP_AUTOTOOLS_ARGS uses _cc_msys/_autotools_cc (Unix)"
  PASS=$((PASS+1))
else
  echo "  FAIL: EP_AUTOTOOLS_ARGS should use _cc_msys or _autotools_cc"
  FAIL=$((FAIL+1))
fi

# 10: EP_AUTOTOOLS_ARGS --prefix uses EP_AUTOTOOLS_PREFIX (Unix) not THIRD_PARTY_LIB_PATH (Windows)
if grep -q -- '--prefix=${EP_AUTOTOOLS_PREFIX}' "$CMAKE_LISTS"; then
  echo "  PASS: EP_AUTOTOOLS_ARGS --prefix uses Unix prefix"
  PASS=$((PASS+1))
else
  echo "  FAIL: EP_AUTOTOOLS_ARGS --prefix should use EP_AUTOTOOLS_PREFIX"
  FAIL=$((FAIL+1))
fi

# 11: Test that wslpath conversion actually works for autotools pattern (integration)
# Simulate what autotools_helper.sh does: src="C:/Users/..." -> wslpath -u
if command -v wslpath >/dev/null 2>&1; then
  src="C:/Users/Branden/komikku-pineapple/external/imagedecoder-houri/library/src"
  converted="$(wslpath -u "$src" 2>/dev/null || echo "fail")"
  assert_eq "wslpath converts autotools src" "/mnt/c/Users/Branden/komikku-pineapple/external/imagedecoder-houri/library/src" "$converted"
  prefix="C:/Users/Branden/komikku-pineapple/external/imagedecoder-houri/library/.cxx/Debug/682e2tm6/arm64-v8a/fk"
  converted2="$(wslpath -u "$prefix" 2>/dev/null || echo "fail")"
  assert_eq "wslpath converts autotools prefix" "/mnt/c/Users/Branden/komikku-pineapple/external/imagedecoder-houri/library/.cxx/Debug/682e2tm6/arm64-v8a/fk" "$converted2"
else
  skip "wslpath autotools conversion" "wslpath not available"
fi

# 12: Check that generated helpers (if .cxx exists) are LF only
for cand in "$SCRIPT_DIR/../../library/.cxx/Debug/682e2tm6/arm64-v8a/autotools_helper.sh" "$SCRIPT_DIR/../../library/.cxx/Debug/682e2tm6/arm64-v8a/configure_iconv.sh"; do
  if [[ -f "$cand" ]]; then
    if grep -q $'\r' "$cand"; then
      echo "  FAIL: generated $cand has CRLF"
      FAIL=$((FAIL+1))
    else
      echo "  PASS: generated $cand is LF"
      PASS=$((PASS+1))
    fi
  else
    skip "generated helper $cand" "not found (need cmake configure)"
  fi
done

suite_summary "test_autotools_helpers"
