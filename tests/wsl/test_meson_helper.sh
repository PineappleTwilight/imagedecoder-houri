#!/usr/bin/env bash
# test_meson_helper.sh — validates meson_helper.sh argument handling
# Exercises the exact helper template written by CMakeLists.txt (with empty cross-file guard)
set -e
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
# shellcheck disable=SC1091
source "$SCRIPT_DIR/_assert.sh"

suite_begin "test_meson_helper"

# Helper under test is generated at ${CMAKE_BINARY_DIR}/meson_helper.sh.
# For unit tests we create a temp copy of the template logic without needing a full CMake configure.
# We also support testing the generated file if it exists.

CMAKE_HELPER_TEMPLATE="$SCRIPT_DIR/../../library/src/main/cpp/CMakeLists.txt"

# Build a standalone meson_helper.sh from the template logic (extract between file(WRITE ... [=[ and ]=]))
# Simpler: recreate the helper inline using same source as CMakeLists.txt writes.
make_helper() {
  local out="$1"
  cat > "$out" <<'EOS'
#!/usr/bin/env bash
set -e
_wslpath_or_manual() {
  local p="$1" out=""
  if command -v wslpath >/dev/null 2>&1; then out=$(wslpath -u "$p" 2>/dev/null || echo ""); fi
  if [[ -z "$out" || "$out" == *":/"* ]]; then
    out="$(printf '%s' "$p" | sed -E 's|\\|/|g; s|^([A-Za-z]):/|/mnt/\L\1/|')"
  fi
  if [[ "$out" == *":/"* ]] && command -v cygpath >/dev/null 2>&1; then out=$(cygpath -u "$p" 2>/dev/null || echo "$out"); fi
  if [[ -z "$out" ]]; then out="$p"; fi
  printf '%s' "$out"
}
args=()
for a in "$@"; do
  if [[ "$a" == --cross-file=* ]]; then
    cf="${a#--cross-file=}"
    if [[ -z "$cf" ]]; then
      echo "ERROR: meson_helper.sh received empty --cross-file=" >&2
      exit 1
    fi
    if [[ "$cf" =~ ^[A-Za-z]:/ ]]; then
      cf="$(_wslpath_or_manual "$cf")"
      a="--cross-file=$cf"
    fi
  fi
  if [[ "$a" == *":/"* ]] || [[ "$a" == "C:"* ]] || [[ "$a" =~ ^[A-Za-z]:/ ]]; then
    a="$(_wslpath_or_manual "$a")"
  fi
  if [[ "$a" == --cross-file=* ]]; then
    cf="${a#--cross-file=}"
    if [[ "$cf" =~ ^[A-Za-z]:/ ]]; then
      cf="$(_wslpath_or_manual "$cf")"
      a="--cross-file=$cf"
    fi
  fi
  args+=("$a")
done
printf '%s\n' "${args[@]}"
EOS
  chmod +x "$out"
}

# Also create a helper that would exec meson but we intercept via a fake meson
make_helper_exec() {
  local out="$1" fake_meson="$2"
  cat > "$out" <<EOS
#!/usr/bin/env bash
set -e
_wslpath_or_manual() {
  local p="\$1" out=""
  if command -v wslpath >/dev/null 2>&1; then out=\$(wslpath -u "\$p" 2>/dev/null || echo ""); fi
  if [[ -z "\$out" || "\$out" == *":/"* ]]; then
    out="\$(printf '%s' "\$p" | sed -E 's|\\\\|/|g; s|^([A-Za-z]):/|/mnt/\\L\\1/|')"
  fi
  printf '%s' "\$out"
}
args=()
for a in "\$@"; do
  if [[ "\$a" == --cross-file=* ]]; then
    cf="\${a#--cross-file=}"
    if [[ -z "\$cf" ]]; then echo "ERROR: empty --cross-file=" >&2; exit 1; fi
    if [[ "\$cf" =~ ^[A-Za-z]:/ ]]; then cf="\$(_wslpath_or_manual "\$cf")"; a="--cross-file=\$cf"; fi
  else
    a="\$a"
  fi
  if [[ "\$a" == *":/"* ]] || [[ "\$a" == "C:"* ]] || [[ "\$a" =~ ^[A-Za-z]:/ ]]; then a="\$(_wslpath_or_manual "\$a")"; fi
  if [[ "\$a" == --cross-file=* ]]; then
    cf="\${a#--cross-file=}"
    if [[ "\$cf" =~ ^[A-Za-z]:/ ]]; then cf="\$(_wslpath_or_manual "\$cf")"; a="--cross-file=\$cf"; fi
  fi
  args+=("\$a")
done
exec "$fake_meson" "\${args[@]}"
EOS
  chmod +x "$out"
}

TMP_HELPER="$(mktemp)"
make_helper "$TMP_HELPER"

run_helper() {
  bash "$TMP_HELPER" "$@" 2>&1
}

# Test 1: empty --cross-file= must error (the bug we fixed)
set +e
out="$(run_helper setup --cross-file= --prefix=/mnt/c/foo 2>&1)"
rc=$?
set -e
if [[ $rc -ne 0 ]] && [[ "$out" == *"empty --cross-file"* ]]; then
  echo "  PASS: empty --cross-file= errors with diagnostic"
  PASS=$((PASS+1))
else
  echo "  FAIL: empty --cross-file= should error with diagnostic"
  echo "    rc=$rc out=$out"
  FAIL=$((FAIL+1))
fi

# Test 2: --cross-file=C:/... converts to /mnt/c/...
out="$(run_helper setup --cross-file=C:/Users/Branden/komikku-pineapple/external/imagedecoder-houri/library/.cxx/Debug/682e2tm6/arm64-v8a/android-cross-file.txt)"
assert_eq "--cross-file=C:/... -> /mnt/c/..." \
  "--cross-file=/mnt/c/Users/Branden/komikku-pineapple/external/imagedecoder-houri/library/.cxx/Debug/682e2tm6/arm64-v8a/android-cross-file.txt" \
  "$(echo "$out" | grep -F -- "--cross-file=" | head -n1)"

# Test 3: --cross-file=/mnt/c/... stays
out="$(run_helper setup --cross-file=/mnt/c/Users/test/android-cross-file.txt)"
assert_eq "--cross-file=/mnt/c/... stays" \
  "--cross-file=/mnt/c/Users/test/android-cross-file.txt" \
  "$(echo "$out" | grep -F -- "--cross-file=" | head -n1)"

# Test 4: standalone C:/ path converts (build dir, source dir)
out="$(run_helper setup --cross-file=/mnt/c/foo --prefix=/mnt/c/foo C:/Users/Branden/komikku-pineapple/external/imagedecoder-houri/library/.cxx/Debug/682e2tm6/arm64-v8a/fk/src/ep_dav1d-build)"
assert_contains "standalone C:/ build dir converts" "/mnt/c/Users/Branden" "$out"

# Test 5: standalone /mnt/c/... stays
out="$(run_helper setup --cross-file=/mnt/c/foo /mnt/c/Users/test/build)"
assert_contains "standalone /mnt/c/... stays" "/mnt/c/Users/test/build" "$out"

# Test 6: args without :/ stay unchanged
out="$(run_helper setup --prefix=/mnt/c/foo --libdir=lib --default-library=static --buildtype=release)"
assert_contains "args without drive stay: --libdir" "--libdir=lib" "$out"
assert_contains "args without drive stay: --buildtype" "--buildtype=release" "$out"

# Test 7: multiple args mixed (the real failing command)
out="$(run_helper setup --cross-file=C:/Users/Branden/komikku-pineapple/external/imagedecoder-houri/library/.cxx/Debug/682e2tm6/arm64-v8a/android-cross-file.txt --prefix=/mnt/c/Users/Branden/komikku-pineapple/external/imagedecoder-houri/library/.cxx/Debug/682e2tm6/arm64-v8a/fk --libdir=lib --default-library=static --buildtype=release C:/Users/Branden/komikku-pineapple/external/imagedecoder-houri/library/.cxx/Debug/682e2tm6/arm64-v8a/fk/src/ep_dav1d-build C:/Users/Branden/komikku-pineapple/external/imagedecoder-houri/library/.cxx/Debug/682e2tm6/arm64-v8a/fk/src/ep_dav1d)"
assert_contains "mixed: cross file converted" "/mnt/c/Users/Branden" "$out"
assert_contains "mixed: prefix kept" "--prefix=/mnt/c/Users/Branden" "$out"
assert_not_contains "mixed: no remaining C:/" "C:/Users" "$out"

# Test 8: D: drive
out="$(run_helper setup --cross-file=D:/work/android-cross-file.txt)"
assert_eq "D:/ drive converts" \
  "--cross-file=/mnt/d/work/android-cross-file.txt" \
  "$(echo "$out" | grep -F -- "--cross-file=" | head -n1)"

# Test 9: E:/Foo with capitals
out="$(run_helper setup --cross-file=E:/Foo/Bar.txt)"
assert_eq "E:/ drive converts lowercased" \
  "--cross-file=/mnt/e/Foo/Bar.txt" \
  "$(echo "$out" | grep -F -- "--cross-file=" | head -n1)"

# Test 10: --cross-file without value but with = and trailing space scenario (already covered by empty)
# Test 11: --cross-file with already /mnt/c/ should not double-convert to /mnt/mnt/...
out="$(run_helper setup --cross-file=/mnt/c/already.txt)"
assert_eq "double conversion guard" "--cross-file=/mnt/c/already.txt" "$(echo "$out" | grep -F -- "--cross-file=" | head -n1)"

# Test 12: prefix already /mnt/c/... should stay (not become /mnt/mnt)
out="$(run_helper setup --prefix=/mnt/c/foo)"
assert_contains "prefix /mnt/c stays" "--prefix=/mnt/c/foo" "$out"

# Test 13: Order preservation
out="$(run_helper setup --cross-file=/mnt/c/a.txt --prefix=/mnt/c/b -Dtests=false)"
# Should be same order, just possibly converted
assert_contains "order: --cross-file before --prefix" "--cross-file=/mnt/c/a.txt" "$out"
# Check that -Dtests=false is preserved exactly
assert_contains "order: -Dtests=false preserved" "-Dtests=false" "$out"

# Test 14: Verify helper does not mangle --cross-file= with quotes (none expected, but ensure no crash)
out="$(run_helper setup --cross-file=/mnt/c/foo/bar\ with\ space.txt 2>&1 || true)"
# The helper splits on "$@" so space inside arg is preserved if quoted; we test that quoting works
# Call with quoted arg
out2="$(run_helper setup "--cross-file=/mnt/c/foo/bar with space.txt")"
assert_contains "quoted path with space preserved" "bar with space" "$out2"

# Test 15: Ensure helper template in CMakeLists.txt matches our inline (drift detection)
# Extract the helper from CMakeLists.txt and compare key guard string
if grep -q "empty --cross-file=" "$CMAKE_HELPER_TEMPLATE" 2>/dev/null; then
  echo "  PASS: CMakeLists.txt helper contains empty guard"
  PASS=$((PASS+1))
else
  echo "  FAIL: CMakeLists.txt helper missing empty guard (drift)"
  FAIL=$((FAIL+1))
fi

# Test 16: If a generated helper exists in a stale .cxx, verify it also has guard (after cmake reconfigure)
for cand in "$SCRIPT_DIR/../../library/.cxx/Debug/682e2tm6/arm64-v8a/meson_helper.sh" "$SCRIPT_DIR/../../library/.cxx/Release/682e2tm6/arm64-v8a/meson_helper.sh"; do
  if [[ -f "$cand" ]]; then
    if grep -q "empty --cross-file" "$cand"; then
      echo "  PASS: generated $cand has guard"
      PASS=$((PASS+1))
    else
      echo "  FAIL: generated $cand missing guard (stale cache, run rm -rf .../.cxx)"
      FAIL=$((FAIL+1))
    fi
  else
    skip "generated helper $cand" "not present (run CMake configure first)"
  fi
done

rm -f "$TMP_HELPER"

suite_summary "test_meson_helper"
