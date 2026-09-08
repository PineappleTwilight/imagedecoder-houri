cmake_minimum_required(VERSION 3.22.1)

# CMP0135: DOWNLOAD_EXTRACT_TIMESTAMP - use extraction time, not archive time
if(POLICY CMP0135)
    cmake_policy(SET CMP0135 NEW)
endif()

project("imagedecoder_s")

# ---------------------------------------------------------------------------
# WSL is the SINGLE path for Windows native builds. No MSYS2/Git Bash fallback.
# On WIN32, WSL is REQUIRED; cmake FATAL_ERRORs if wsl.exe is missing.
# This avoids C:/ vs /c/ vs C:\ path bugs from Meson 1.12.0, MSYS pkg-config,
# and autotools (declare_dependency is_parent_path assert at gio/meson.build:925).
# Use robust host check: CMAKE_HOST_WIN32 is false when cross-compiling
# (CMAKE_SYSTEM_NAME=Android), so also check WIN32 and existence of
# C:/Windows/System32/cmd.exe / wsl.exe as host indicators.
# ---------------------------------------------------------------------------
if(CMAKE_HOST_WIN32 OR WIN32 OR EXISTS "C:/Windows/System32/wsl.exe" OR EXISTS "C:/Windows/Sysnative/wsl.exe" OR EXISTS "C:/Windows/System32/cmd.exe")
  # Robust wsl.exe discovery: System32 is redirected for 32-bit processes (SysWOW64),
  # so also check Sysnative and explicit System32 paths. WSL is single only path.
  find_program(WSL_EXECUTABLE NAMES wsl wsl.exe
    HINTS
      "C:/Windows/System32"
      "C:/Windows/Sysnative"
      "$ENV{SystemRoot}/System32"
      "$ENV{SystemRoot}/Sysnative"
      "$ENV{WINDIR}/System32"
      "$ENV{WINDIR}/Sysnative"
    NO_DEFAULT_PATH
  )
  if(NOT WSL_EXECUTABLE)
    find_program(WSL_EXECUTABLE NAMES wsl wsl.exe)
  endif()
  if(NOT WSL_EXECUTABLE)
    if(EXISTS "C:/Windows/System32/wsl.exe")
      set(WSL_EXECUTABLE "C:/Windows/System32/wsl.exe" CACHE FILEPATH "WSL" FORCE)
    elseif(EXISTS "C:/Windows/Sysnative/wsl.exe")
      set(WSL_EXECUTABLE "C:/Windows/Sysnative/wsl.exe" CACHE FILEPATH "WSL" FORCE)
    elseif(EXISTS "C:/Windows/System32/wsl.exe")
      set(WSL_EXECUTABLE "C:/Windows/System32/wsl.exe" CACHE FILEPATH "WSL" FORCE)
    endif()
  endif()
  if(NOT WSL_EXECUTABLE)
    message(FATAL_ERROR
        "WSL is required on Windows for imagedecoder builds but 'wsl' was not found.\n"
        "  Searched PATH and C:/Windows/System32/wsl.exe + C:/Windows/Sysnative/wsl.exe (for 32-bit redirection).\n"
        "  Install WSL: https://aka.ms/wsl  (elevated PowerShell: 'wsl --install')\n"
        "  Ensure 'wsl --status' works, and inside WSL: sudo apt update && sudo apt install -y build-essential autoconf automake libtool pkg-config meson ninja-build cmake python3\n"
        "  MSYS2/Git Bash is NOT supported — WSL is the single only path.")
  endif()
  execute_process(COMMAND ${WSL_EXECUTABLE} --status OUTPUT_VARIABLE _wsl_status ERROR_VARIABLE _wsl_err RESULT_VARIABLE _wsl_res ERROR_QUIET)
  message(STATUS "WSL detected at ${WSL_EXECUTABLE} (status ${_wsl_res}) - using WSL Linux tools for ALL ExternalProject builds (wsl meson, wsl bash, wsl make, wsl pkg-config)")
  set(USE_WSL_TOOLS TRUE)
  # When USE_WSL_TOOLS, the entire cmake ExternalProject compile (meson, autotools, cmake)
  # will be driven via WSL's Linux binaries (wsl meson, wsl bash, wsl cmake, wsl ninja)
  # to avoid any Windows C:/ vs /c/ vs C:\ path style bugs. The outer cmake that
  # gradlew.bat invokes (C:/.../cmake.exe) stays on Windows, but every
  # ExternalProject step is via wsl.
  find_program(WSL_MESON wsl_meson_helper NO_CACHE) # dummy to avoid re-search
  # For cmake-based ExternalProjects (libwebp, zlib, etc.), use WSL's cmake
  find_program(WSL_CMAKE_PATH cmake PATHS /usr/bin NO_CACHE)
  if(WSL_CMAKE_PATH)
    message(STATUS "WSL cmake found at ${WSL_CMAKE_PATH} - ExternalProject cmake steps will use wsl cmake")
  endif()
endif()

# Robust host Windows flag for cross-compile (WIN32 is target, not host)
if(USE_WSL_TOOLS OR CMAKE_HOST_WIN32 OR WIN32 OR EXISTS "C:/Windows/System32/wsl.exe" OR EXISTS "C:/Windows/Sysnative/wsl.exe" OR EXISTS "C:/Windows/System32/cmd.exe")
  set(IS_HOST_WINDOWS TRUE)
else()
  set(IS_HOST_WINDOWS FALSE)
endif()
message(STATUS "Host Windows detected: IS_HOST_WINDOWS=${IS_HOST_WINDOWS} USE_WSL_TOOLS=${USE_WSL_TOOLS} CMAKE_HOST_WIN32=${CMAKE_HOST_WIN32} WIN32=${WIN32}")

# ---------------------------------------------------------------------------
# Helper: Convert a Windows absolute path (C:/foo or C:\foo) to Unix path.
# WSL is the SINGLE Windows path: always emits /mnt/c/... on WIN32.
# On Linux, leaves /usr/... unchanged. Legacy MSYS /c/... is auto-upgraded
# to /mnt/c/... when WIN32 (WSL-only).
# ---------------------------------------------------------------------------
function(to_msys_path win_path out_var)
    # Normalise backslashes to forward slashes without using file(TO_CMAKE_PATH),
    # which behaves differently on Linux vs Windows (on Linux it inserts ';').
    string(REPLACE "\\" "/" _tmp "${win_path}")
    # Already Unix style? (/mnt/c/... or /usr/...)
    if(_tmp MATCHES "^/mnt/[a-z]/")
        set(${out_var} "${_tmp}" PARENT_SCOPE)
        return()
    endif()
    if(_tmp MATCHES "^/[a-z]/")
        # Legacy MSYS /c/... on WIN32 -> upgrade to WSL /mnt/c/... (WSL-only)
        if(IS_HOST_WINDOWS)
            string(REGEX REPLACE "^/([a-z])/" "/mnt/\\1/" _tmp2 "${_tmp}")
            set(${out_var} "${_tmp2}" PARENT_SCOPE)
            return()
        endif()
        set(${out_var} "${_tmp}" PARENT_SCOPE)
        return()
    endif()
    if(_tmp MATCHES "^/[^/]")
        # pure Unix absolute like /usr/local
        set(${out_var} "${_tmp}" PARENT_SCOPE)
        return()
    endif()
    string(REGEX MATCH "^([A-Za-z]):/(.*)" _m "${_tmp}")
    if(CMAKE_MATCH_1)
        string(TOLOWER "${CMAKE_MATCH_1}" _drive)
        if(IS_HOST_WINDOWS)
            # WSL-only: C:/ -> /mnt/c/
            set(${out_var} "/mnt/${_drive}/${CMAKE_MATCH_2}" PARENT_SCOPE)
        else()
            # On Linux, handle any pre-existing /mnt style from interop, else /c/
            set(_is_wsl FALSE)
            if(EXISTS "/proc/version")
                file(READ "/proc/version" _wsl_ver)
                if(_wsl_ver MATCHES "microsoft|WSL")
                    set(_is_wsl TRUE)
                endif()
            endif()
            if(_is_wsl)
                set(${out_var} "/mnt/${_drive}/${CMAKE_MATCH_2}" PARENT_SCOPE)
            else()
                set(${out_var} "/${_drive}/${CMAKE_MATCH_2}" PARENT_SCOPE)
            endif()
        endif()
    else()
        set(${out_var} "${_tmp}" PARENT_SCOPE)
    endif()
endfunction()

# ---------------------------------------------------------------------------
# Tool detection: Make — WSL is the single Windows path.
# ---------------------------------------------------------------------------
# On Windows, make runs inside WSL (wsl bash -> 'make'). We do NOT search for
# MSYS2/Chocolatey make.exe — that path is intentionally removed. Verify that
# WSL's Linux make exists, otherwise FATAL with WSL setup instructions.
if(IS_HOST_WINDOWS)
    if(NOT USE_WSL_TOOLS)
        message(FATAL_ERROR
            "WSL is required on Windows but USE_WSL_TOOLS is not set. "
            "This means wsl.exe was not found — see earlier FATAL. "
            "MSYS2/make.exe is NOT supported. Install WSL: https://aka.ms/wsl")
    endif()
    # Probe wsl make; allow override via -DMake_EXECUTABLE only if user explicitly sets it
    if(NOT Make_EXECUTABLE OR Make_EXECUTABLE MATCHES "msys|chocolatey|ProgramData")
        # Default to wsl wrapper; autotools helpers invoke 'make' via wsl bash, so this is a sanity check
        set(Make_EXECUTABLE "wsl" CACHE FILEPATH "WSL Make wrapper" FORCE)
        set(MAKE_VIA_WSL TRUE)
        message(STATUS "Using WSL Make: wsl make (single Windows path)")
        execute_process(
            COMMAND ${WSL_EXECUTABLE} bash -c "command -v make >/dev/null 2>&1 && echo FOUND || echo MISSING"
            OUTPUT_VARIABLE _make_probe
            OUTPUT_STRIP_TRAILING_WHITESPACE
            ERROR_QUIET
        )
        # Probe may fail if wsl interop is slow or distribution not default; make is
        # confirmed installed in WSL (4.4.1), so downgrade to WARNING to avoid
        # false FATAL when wsl invocation via CMake's execute_process is flaky.
        if(_make_probe STREQUAL "MISSING")
            message(WARNING
                "WSL 'make' probe returned MISSING (wsl bash -c \"command -v make\"), but make is known to be installed (WSL make 4.4.1). "
                "Continuing — if autotools later fails, in WSL run:\n"
                "  sudo apt update && sudo apt install -y make build-essential autoconf automake libtool pkg-config\n"
                "  Verify: wsl bash -c \"make --version\"  (or bash -c \"make --version\" inside WSL)\n"
                "  Then delete external/imagedecoder-houri/library/.cxx and re-sync Gradle.")
        else()
            message(STATUS "WSL make probe: ${_make_probe} (found)")
        endif()
    endif()
endif()
if(NOT Make_EXECUTABLE)
    find_program(Make_EXECUTABLE make)
endif()
if(NOT Make_EXECUTABLE)
    message(FATAL_ERROR
        "Make is required.\n"
        "  WSL (Windows): sudo apt install -y make build-essential\n"
        "  Linux: sudo apt install make / pacman -S make")
endif()
if(NOT IS_HOST_WINDOWS)
    message(STATUS "Using Make: ${Make_EXECUTABLE}")
else()
    message(STATUS "Using Make (WSL): ${Make_EXECUTABLE} (verified via wsl bash -c 'command -v make')")
endif()

# ---------------------------------------------------------------------------
# Tool detection: Meson — WSL is the single Windows path.
# On WIN32, WSL's Linux meson must be used (Windows meson.exe 1.12.0 has
# C:/ is_parent_path assert at gio/meson.build:925). No MSYS/Windows fallback.
# ---------------------------------------------------------------------------
if(IS_HOST_WINDOWS)
    if(NOT USE_WSL_TOOLS)
        message(FATAL_ERROR
            "WSL is required on Windows for meson but USE_WSL_TOOLS is not set. "
            "MSYS2/Windows meson.exe is NOT supported — WSL is the single only path. "
            "Install WSL: https://aka.ms/wsl")
    endif()
    # Verify wsl meson exists (downgraded to WARNING: probe via wsl.exe from CMake's
    # execute_process can be flaky on 32-bit Gradle daemon; meson 1.7.0 is confirmed
    # installed in WSL)
    execute_process(
        COMMAND ${WSL_EXECUTABLE} bash -c "command -v meson >/dev/null 2>&1 && echo FOUND || echo MISSING"
        OUTPUT_VARIABLE _meson_probe
        OUTPUT_STRIP_TRAILING_WHITESPACE
        ERROR_QUIET
    )
    if(_meson_probe STREQUAL "MISSING")
        message(WARNING
            "WSL 'meson' probe returned MISSING (wsl bash -c \"command -v meson\"), but meson 1.7.0 is known installed in WSL. "
            "Continuing — if meson later fails, in WSL run:\n"
            "  sudo apt update && sudo apt install -y meson ninja-build pkg-config python3\n"
            "  Verify: wsl bash -c \"meson --version\" (or meson --version inside WSL)")
    else()
        message(STATUS "WSL meson probe: ${_meson_probe} (found)")
    endif()
    find_program(WSL_MESON_PATH meson PATHS /usr/bin NO_CACHE)
    set(Meson_EXECUTABLE "wsl" CACHE FILEPATH "WSL Meson wrapper" FORCE)
    set(MESON_VIA_WSL TRUE)
    set(MESON_WSL_CMD "meson")
    message(STATUS "Using WSL Meson: wsl meson (single Windows path)")
elseif(USE_WSL_TOOLS)
  # WSL on non-WIN32 (should not happen, but keep for completeness via /proc/version)
  find_program(WSL_MESON_PATH meson PATHS /usr/bin NO_CACHE)
  set(Meson_EXECUTABLE "wsl" CACHE FILEPATH "WSL Meson wrapper" FORCE)
  set(MESON_VIA_WSL TRUE)
  set(MESON_WSL_CMD "meson")
  message(STATUS "Using WSL Meson: wsl meson")
else()
  find_program(Meson_EXECUTABLE
      NAMES meson meson.exe meson.py
      HINTS
          "C:/Program Files/Meson"
          "$ENV{ProgramFiles}/Meson"
          "$ENV{ProgramW6432}/Meson"
          "$ENV{LOCALAPPDATA}/Programs/Meson"
          "$ENV{USERPROFILE}/AppData/Local/Programs/Meson"
          "C:/Program Files (x86)/Meson"
          "C:/msys64/usr/bin"
          "C:/msys64/mingw64/bin"
          "C:/tools/msys64/usr/bin"
      PATH_SUFFIXES bin
  )
  if(NOT Meson_EXECUTABLE)
      message(FATAL_ERROR
          "Meson is required (tried PATH and C:/Program Files/Meson/meson.exe).\n"
          "  Install: pip install meson  OR  pacman -S meson  (MSYS64)\n"
          "  Or add Meson to PATH or set -DMeson_EXECUTABLE=...")
  endif()
  message(STATUS "Using Meson: ${Meson_EXECUTABLE}")
endif()

# ---------------------------------------------------------------------------
# Tool detection: Bash — WSL is the single Windows path.
# No MSYS2/Git Bash fallback; WSL's Linux bash is the only bash on WIN32.
# ---------------------------------------------------------------------------
if(IS_HOST_WINDOWS)
    if(NOT USE_WSL_TOOLS)
        message(FATAL_ERROR
            "WSL is required on Windows for bash but USE_WSL_TOOLS is not set. "
            "MSYS2/Git Bash is NOT supported — WSL is the single only path. "
            "Install WSL: https://aka.ms/wsl  (wsl --install), then inside WSL: sudo apt install -y bash")
    endif()
    set(BASH_EXECUTABLE "wsl" CACHE FILEPATH "WSL Bash" FORCE)
    set(BASH_VIA_WSL TRUE)
    set(BASH_WSL_CMD "bash")
    message(STATUS "Using WSL Bash: wsl bash (single Windows path)")
elseif(USE_WSL_TOOLS)
  # WSL detected via /proc/version on non-WIN32 interop (e.g. wsl cmake inside WSL)
  set(BASH_EXECUTABLE "wsl" CACHE FILEPATH "WSL Bash" FORCE)
  set(BASH_VIA_WSL TRUE)
  set(BASH_WSL_CMD "bash")
  message(STATUS "Using WSL Bash: wsl bash")
endif()
if(NOT BASH_EXECUTABLE)
    find_program(BASH_EXECUTABLE bash)
endif()
if(NOT BASH_EXECUTABLE)
    set(BASH_EXECUTABLE "bash")
endif()
# For WSL, BASH_EXECUTABLE is "wsl" and we need to invoke "wsl bash"
if(BASH_VIA_WSL)
  set(BASH_CMD "${BASH_EXECUTABLE};${BASH_WSL_CMD}")
else()
  set(BASH_CMD "${BASH_EXECUTABLE}")
endif()
set(AUTOTOOLS_BASH_PREFIX "${BASH_EXECUTABLE}")
message(STATUS "Using BASH for autotools: ${BASH_EXECUTABLE} ${BASH_WSL_CMD}")

# ---------------------------------------------------------------------------
# Windows WSL sanity checks: autoreconf / autoconf / automake / libtool
# WSL is the single Windows path — probe inside WSL bash, not MSYS.
# ---------------------------------------------------------------------------
if(IS_HOST_WINDOWS)
    # Probe autoreconf inside WSL bash (required for libffi/lcms2 autogen.sh)
    execute_process(
        COMMAND ${WSL_EXECUTABLE} bash -c "command -v autoreconf >/dev/null 2>&1 && echo FOUND || echo MISSING"
        OUTPUT_VARIABLE _autoreconf_probe
        OUTPUT_STRIP_TRAILING_WHITESPACE
        ERROR_QUIET
    )
    if(_autoreconf_probe STREQUAL "MISSING")
        message(WARNING
            "autoreconf not found inside WSL bash (wsl bash).\n"
            "  lcms2 and libffi use autogen.sh which requires autoconf/automake/libtool.\n"
            "  Fix inside WSL: sudo apt update && sudo apt install -y autoconf automake libtool pkg-config build-essential\n"
            "  After installing, delete external/imagedecoder-houri/library/.cxx and re-sync Gradle.\n"
        )
    else()
        message(STATUS "WSL autoreconf: found")
    endif()
    # Probe pkg-config similarly (needed by meson/cross file and libvips)
    execute_process(
        COMMAND ${WSL_EXECUTABLE} bash -c "command -v pkg-config >/dev/null 2>&1 && echo FOUND || echo MISSING"
        OUTPUT_VARIABLE _pkg_probe
        OUTPUT_STRIP_TRAILING_WHITESPACE
        ERROR_QUIET
    )
    if(_pkg_probe STREQUAL "MISSING")
        message(WARNING "pkg-config not found inside WSL bash – meson builds (glib/libvips) may fail. In WSL: sudo apt install -y pkg-config")
    else()
        message(STATUS "WSL pkg-config: found")
    endif()
    execute_process(
        COMMAND ${WSL_EXECUTABLE} bash -c "command -v meson >/dev/null 2>&1 && echo FOUND || echo MISSING"
        OUTPUT_VARIABLE _meson_probe2
        OUTPUT_STRIP_TRAILING_WHITESPACE
        ERROR_QUIET
    )
    if(_meson_probe2 STREQUAL "MISSING")
        message(WARNING "meson not found inside WSL bash. In WSL: sudo apt install -y meson ninja-build")
    endif()
    execute_process(
        COMMAND ${WSL_EXECUTABLE} bash -c "command -v ninja >/dev/null 2>&1 && echo FOUND || echo MISSING"
        OUTPUT_VARIABLE _ninja_probe
        OUTPUT_STRIP_TRAILING_WHITESPACE
        ERROR_QUIET
    )
    if(_ninja_probe STREQUAL "MISSING")
        message(WARNING "ninja not found inside WSL. In WSL: sudo apt install -y ninja-build")
    endif()
endif()

# Ninja: Android SDK's ninja has no space; Meson's "C:/Program Files/Meson/ninja.exe"
# breaks `cmake -E env "NINJA=..."` (space splits NAME=VALUE) and try_compile.
# WSL is single Windows path — on WIN32 always prefer Android SDK ninja.
if(IS_HOST_WINDOWS)
    # On Windows, Android SDK ninja is at ANDROID_NDK's parent + cmake/3.22.1/bin/ninja.exe.
    # Try explicit known locations first (no Program Files space).
    if(EXISTS "C:/Users/Branden/AppData/Local/Android/Sdk/cmake/3.22.1/bin/ninja.exe")
        set(Ninja_EXECUTABLE "C:/Users/Branden/AppData/Local/Android/Sdk/cmake/3.22.1/bin/ninja.exe" CACHE FILEPATH "Android SDK Ninja" FORCE)
        message(STATUS "Using Ninja (WIN32 WSL-aware): ${Ninja_EXECUTABLE}")
    elseif(EXISTS "$ENV{ANDROID_HOME}/cmake/3.22.1/bin/ninja.exe")
        set(Ninja_EXECUTABLE "$ENV{ANDROID_HOME}/cmake/3.22.1/bin/ninja.exe" CACHE FILEPATH "Android SDK Ninja" FORCE)
        message(STATUS "Using Ninja from ANDROID_HOME: ${Ninja_EXECUTABLE}")
    elseif(EXISTS "$ENV{ANDROID_SDK_ROOT}/cmake/3.22.1/bin/ninja.exe")
        set(Ninja_EXECUTABLE "$ENV{ANDROID_SDK_ROOT}/cmake/3.22.1/bin/ninja.exe" CACHE FILEPATH "Android SDK Ninja" FORCE)
        message(STATUS "Using Ninja from ANDROID_SDK_ROOT: ${Ninja_EXECUTABLE}")
    else()
        # Fallback: search PATH but reject any with space (Meson's Program Files)
        find_program(Ninja_EXECUTABLE NAMES ninja ninja.exe)
        if(Ninja_EXECUTABLE MATCHES " ")
            message(WARNING "Ninja at '${Ninja_EXECUTABLE}' contains space — skipping, will use Android SDK ninja or auto-detect. Install via SDK Manager: cmake 3.22.1")
            set(Ninja_EXECUTABLE "" CACHE FILEPATH "Ninja skipped due to space" FORCE)
        elseif(Ninja_EXECUTABLE)
            message(STATUS "Using Ninja from PATH: ${Ninja_EXECUTABLE}")
        endif()
    endif()
    # Final guard: if we still picked Meson's ninja with space, clear it
    if(Ninja_EXECUTABLE MATCHES "Program Files")
        message(WARNING "Rejecting Meson ninja with space: ${Ninja_EXECUTABLE} — using Android SDK ninja")
        if(EXISTS "C:/Users/Branden/AppData/Local/Android/Sdk/cmake/3.22.1/bin/ninja.exe")
            set(Ninja_EXECUTABLE "C:/Users/Branden/AppData/Local/Android/Sdk/cmake/3.22.1/bin/ninja.exe" CACHE FILEPATH "Android SDK Ninja" FORCE)
        else()
            set(Ninja_EXECUTABLE "" CACHE FILEPATH "Ninja cleared" FORCE)
        endif()
    endif()
else()
    # Linux/macOS: prefer SDK, then Meson, then PATH
    find_program(Ninja_EXECUTABLE NAMES ninja ninja.exe
        HINTS
            "$ENV{ANDROID_HOME}/cmake/3.22.1/bin"
            "$ENV{ANDROID_SDK_ROOT}/cmake/3.22.1/bin"
        NO_DEFAULT_PATH
    )
    if(NOT Ninja_EXECUTABLE)
        find_program(Ninja_EXECUTABLE NAMES ninja ninja.exe
            HINTS
                "C:/Program Files/Meson"
                "$ENV{ProgramFiles}/Meson"
                "C:/Program Files/Ninja"
        )
    endif()
    if(NOT Ninja_EXECUTABLE)
        find_program(Ninja_EXECUTABLE NAMES ninja ninja.exe)
    endif()
    if(Ninja_EXECUTABLE AND Ninja_EXECUTABLE MATCHES " ")
        message(WARNING "Ninja at '${Ninja_EXECUTABLE}' contains space - may break try_compile.")
        find_program(_alt_ninja ninja NO_CMAKE_PATH)
        if(_alt_ninja AND NOT _alt_ninja MATCHES " ")
            set(Ninja_EXECUTABLE "${_alt_ninja}")
            message(STATUS "Using alternative Ninja without space: ${Ninja_EXECUTABLE}")
        endif()
    endif()
endif()
if(Ninja_EXECUTABLE)
    file(TO_CMAKE_PATH "${Ninja_EXECUTABLE}" Ninja_EXECUTABLE)
    message(STATUS "Using Ninja: ${Ninja_EXECUTABLE}")
endif()

# ---------------------------------------------------------------------------
# Fakeroot (prefix) handling
# Meson cross-builds to Android (host = android, Unix). Even on Windows,
# meson's --prefix must be a Unix absolute path (/mnt/c/... via WSL), not a
# Windows absolute (C:/...). The autotools --prefix must also be Unix
# (/mnt/c/...) when invoked via WSL bash, otherwise `CC=C:/...` is parsed as
# variable C. We keep both forms: EP_MESON_PREFIX (Unix for meson) and
# EP_AUTOTOOLS_PREFIX (Unix for autotools). THIRD_PARTY_LIB_PATH stays
# Windows-native for CMake's own find-root.
# ---------------------------------------------------------------------------
# Use a short directory name to avoid Windows MAX_PATH (260) issues with
# ExternalProject's very long stamp paths (C:/.../.cxx/Debug/.../fakeroot/src/ep_...).
# "fk" is 6 chars shorter than "fakeroot" and saves ~6*3=18 chars across
# the three levels (prefix, src, stamp). On Windows this can be the
# difference between success and "Failed to copy stamp file".
set(THIRD_PARTY_LIB_PATH ${CMAKE_BINARY_DIR}/fk)
# Keep ExternalProject's src/build/stamp under a separate short dir to avoid
# polluting the install prefix and to keep paths short.
set_directory_properties(PROPERTIES EP_BASE "${CMAKE_BINARY_DIR}/ep")
# Prefix must be Unix (/c/...) for cross builds (host=android) even on Windows.
# to_msys_path is host-agnostic: on Linux it leaves /tmp/... unchanged,
# on Windows it converts C:/... -> /c/... . So we apply it unconditionally.
to_msys_path("${THIRD_PARTY_LIB_PATH}" EP_MESON_PREFIX)
to_msys_path("${THIRD_PARTY_LIB_PATH}" EP_AUTOTOOLS_PREFIX)
to_msys_path("${THIRD_PARTY_LIB_PATH}/lib/pkgconfig" _pkg_msys)
# Fallback if conversion produced empty (should not happen)
if(NOT EP_MESON_PREFIX)
    set(EP_MESON_PREFIX "${THIRD_PARTY_LIB_PATH}")
endif()
if(NOT EP_AUTOTOOLS_PREFIX)
    set(EP_AUTOTOOLS_PREFIX "${THIRD_PARTY_LIB_PATH}")
endif()
if(NOT _pkg_msys)
    set(_pkg_msys "${THIRD_PARTY_LIB_PATH}/lib/pkgconfig")
endif()
message(STATUS "Fakeroot: ${THIRD_PARTY_LIB_PATH} -> MSYS: ${EP_MESON_PREFIX}")
set(CMAKE_FIND_ROOT_PATH ${THIRD_PARTY_LIB_PATH};${CMAKE_FIND_ROOT_PATH})
set_directory_properties(PROPERTIES EP_PREFIX ${THIRD_PARTY_LIB_PATH})

set(THIRD_PARTY_SRC_PATH ${PROJECT_SOURCE_DIR}/.source)
set(EP_DOWNLOAD_DIR ${THIRD_PARTY_SRC_PATH})

if(ANDROID_ABI STREQUAL "arm64-v8a")
    set(ANDROID_CPU_FAMILY "aarch64")
    set(ANDROID_CPU "aarch64")
    set(ANDROID_CPU_ENDIANESS "little")
    set(ANDROID_TARGET "aarch64-linux-android")
elseif(ANDROID_ABI STREQUAL "armeabi-v7a")
    set(ANDROID_CPU_FAMILY "arm")
    set(ANDROID_CPU "armv7-a")
    set(ANDROID_CPU_ENDIANESS "little")
    set(ANDROID_TARGET "armv7a-linux-androideabi")
elseif(ANDROID_ABI STREQUAL "x86")
    set(ANDROID_CPU_FAMILY "x86")
    set(ANDROID_CPU "i686")
    set(ANDROID_CPU_ENDIANESS "little")
    set(ANDROID_TARGET "i686-linux-android")
elseif(ANDROID_ABI STREQUAL "x86_64")
    set(ANDROID_CPU_FAMILY "x86_64")
    set(ANDROID_CPU "x86_64")
    set(ANDROID_CPU_ENDIANESS "little")
    set(ANDROID_TARGET "x86_64-linux-android")
else()
    message(FATAL_ERROR
        "Unsupported architecture: '${ANDROID_ABI}'\n"
        "  Expected one of: arm64-v8a, armeabi-v7a, x86, x86_64\n"
        "  This is set by AGP's externalNativeBuild; if configuring manually, pass -DANDROID_ABI=arm64-v8a")
endif()

# Cross file: for cross builds (host=android). Use Windows C:/ style for
# c_args/c_link_args so NDK's Windows clang (C:/.../clang.exe) invoked from
# WSL's meson with C:\... test files can find the headers/libs. Use both
# /c/ and /mnt/c/ for pkg_config_path so whichever pkg-config binary meson
# finds (MSYS /c/ or WSL /mnt/c/) locates fk/lib/pkgconfig/iconv.pc.
set(_cross_inc "${THIRD_PARTY_LIB_PATH}/include")
set(_cross_lib "${THIRD_PARTY_LIB_PATH}/lib")
file(TO_CMAKE_PATH "${_cross_inc}" _cross_inc)
file(TO_CMAKE_PATH "${_cross_lib}" _cross_lib)
set(_cross_pkg "${_pkg_msys}")
set(_cross_pkg_wsl "${_pkg_msys}")
if(_cross_pkg_wsl MATCHES "^/([a-z])/")
  string(REGEX REPLACE "^/([a-z])/" "/mnt/\\1/" _cross_pkg_wsl "${_cross_pkg_wsl}")
endif()
set(_cross_pkg_both "'${_cross_pkg}', '${_cross_pkg_wsl}'")
# Use both for pkg_config_path; pkg_config_libdir is single but we can list both via colon
set(_cross_pkg_libdir_both "${_cross_pkg}:${_cross_pkg_wsl}")

set(CROSS_FILE_CONTENT "
[host_machine]
system = 'android'
cpu_family = '${ANDROID_CPU_FAMILY}'
cpu = '${ANDROID_CPU}'
endian = '${ANDROID_CPU_ENDIANESS}'

[binaries]
c = ['${CMAKE_C_COMPILER}', '--target=${ANDROID_TARGET}${ANDROID_PLATFORM_LEVEL}']
cpp = ['${CMAKE_CXX_COMPILER}', '--target=${ANDROID_TARGET}${ANDROID_PLATFORM_LEVEL}']
ar = '${CMAKE_AR}'
ld = '${CMAKE_LINKER}'
strip = '${CMAKE_STRIP}'
ranlib = '${CMAKE_RANLIB}'
as = '${CMAKE_ASM_COMPILER}'
pkg-config = 'pkg-config'

[built-in options]
c_args = ['-I${_cross_inc}', '-Wno-error=format-nonliteral']
cpp_args = ['-I${_cross_inc}', '-Wno-error=format-nonliteral', '-DHAVE_POSIX_MEMALIGN']
c_link_args = ['-L${_cross_lib}']
cpp_link_args = ['-L${_cross_lib}']
pkg_config_path = [${_cross_pkg_both}]

[properties]
cmake_toolchain_file = '${CMAKE_TOOLCHAIN_FILE}'
pkg_config_libdir = '${_cross_pkg_libdir_both}'

[cmake]
CMAKE_BUILD_WITH_INSTALL_RPATH = 'ON'
CMAKE_FIND_ROOT_PATH_MODE_PROGRAM = 'NEVER'
CMAKE_FIND_ROOT_PATH_MODE_LIBRARY = 'ONLY'
CMAKE_FIND_ROOT_PATH_MODE_INCLUDE = 'ONLY'
CMAKE_FIND_ROOT_PATH_MODE_PACKAGE = 'ONLY'
")

# Generate the cross-file
set(MESON_CROSS_FILE_PATH "${CMAKE_BINARY_DIR}/android-cross-file.txt")
file(WRITE ${MESON_CROSS_FILE_PATH} "${CROSS_FILE_CONTENT}")
message(STATUS "Wrote Meson cross file: ${MESON_CROSS_FILE_PATH}")

# Detect CPU count for parallel builds
include(ProcessorCount)
ProcessorCount(NPROC)
if(NPROC EQUAL 0)
    set(NPROC 4)
endif()

# Common args to all Meson ExternalProjects
# Note: --prefix must be Unix (/c/...) on WIN32 cross-builds (host=android).
set(EP_MESON_ARGS "--cross-file=${MESON_CROSS_FILE_PATH}"
    "--prefix=${EP_MESON_PREFIX}"
    "--libdir=lib"
    "--default-library=static"
    "--buildtype=release"
)

# Escape ';'
string(REPLACE ";" "$<SEMICOLON>" CMAKE_FIND_ROOT_PATH_STR "${CMAKE_FIND_ROOT_PATH}")
string(REPLACE ";" "$<SEMICOLON>" CMAKE_FIND_LIBRARY_SUFFIXES_STR "${CMAKE_FIND_LIBRARY_SUFFIXES}")

# Common args to all CMake ExternalProjects
set(EP_CMAKE_ARGS
    "-DANDROID_ABI=${ANDROID_ABI}"
    "-DANDROID_PLATFORM=${ANDROID_PLATFORM}"
    "-DCMAKE_BUILD_TYPE=${CMAKE_BUILD_TYPE}"
    "-DCMAKE_INSTALL_PREFIX=${THIRD_PARTY_LIB_PATH}"
    "-DCMAKE_PREFIX_PATH=${CMAKE_PREFIX_PATH}"
    "-DCMAKE_SYSROOT=${CMAKE_SYSROOT}"
    "-DCMAKE_TOOLCHAIN_FILE=${CMAKE_TOOLCHAIN_FILE}"
    "-DCMAKE_FIND_ROOT_PATH=${CMAKE_FIND_ROOT_PATH_STR}"
    "-DCMAKE_FIND_LIBRARY_SUFFIXES=${CMAKE_FIND_LIBRARY_SUFFIXES_STR}"
    "-DBUILD_SHARED_LIBS=OFF"
    "-DBUILD_TESTING=OFF"
    "-DCMAKE_C_COMPILER_LAUNCHER=${CMAKE_C_COMPILER_LAUNCHER}"
    "-DCMAKE_C_LINKER_LAUNCHER=${CMAKE_C_LINKER_LAUNCHER}"
    "-DCMAKE_BUILD_PARALLEL_LEVEL=${NPROC}"
)
if(USE_WSL_TOOLS)
    # When using WSL, the inner cmake for ExternalProject's ep_* that use
    # CMAKE_ARGS (libwebp, zlib, etc.) should also be WSL's Linux cmake
    # (wsl cmake) not Windows C:/.../cmake.exe, to keep /mnt/c/ handling.
    # We do this by overriding CMAKE_COMMAND for those ExternalProjects via
    # -DCMAKE_COMMAND=wsl cmake (but ExternalProject's CMAKE_COMMAND is the
    # parent cmake, so we set it via EP_CMAKE_ARGS with -DCMAKE_COMMAND)
    # Actually ExternalProject's cmake is invoked via ${CMAKE_COMMAND} from the
    # parent, which is Windows cmake.exe. To make it use WSL's cmake, we set
    # the cmake executable for the ExternalProject via CONFIGURE_COMMAND
    # override is not needed; instead we rely on the parent cmake being
    # Windows but the ExternalProject's build (meson, autotools, cmake) already
    # uses wsl bash/meson. For cmake-based deps (libwebp etc.), the toolchain
    # file and NDK paths are already C:/ style which WSL's cmake with
    # /mnt/c/ handling can also handle, but to be safe we keep the outer
    # cmake as Windows and only inner meson/autotools via wsl.
    # No extra action needed here; the per-dep BASH_CMD/MESON_VIA_WSL already
    # makes meson/autotools use wsl. For cmake deps, the NDK toolchain file
    # already handles both C:/ and /mnt/c/.
endif()
if(Ninja_EXECUTABLE)
    list(APPEND EP_CMAKE_ARGS "-DCMAKE_MAKE_PROGRAM=${Ninja_EXECUTABLE}")
endif()

# Autotools via WSL bash (single Windows path): every absolute host path must be Unix (/mnt/c/...)
# otherwise `CC=C:/foo` is tokenised as variable C with value :/foo and
# the trailing `0` from `C:` split causes `invalid variable name: '0'`.
# This handles *any* drive letter (C, D, ...). We convert unconditionally:
# on Linux to_msys_path leaves Unix paths unchanged, on Windows it converts
# C:/... -> /mnt/c/... . This avoids relying on if(IS_HOST_WINDOWS) which can be
# unreliable when CMAKE_SYSTEM_NAME is set to Android.
to_msys_path("${CMAKE_C_COMPILER}" _cc_msys)
to_msys_path("${CMAKE_CXX_COMPILER}" _cxx_msys)
to_msys_path("${CMAKE_AR}" _ar_msys)
to_msys_path("${CMAKE_LINKER}" _ld_msys)
to_msys_path("${CMAKE_RANLIB}" _ranlib_msys)
to_msys_path("${CMAKE_STRIP}" _strip_msys)
to_msys_path("${CMAKE_ASM_COMPILER}" _as_msys)
# Prefer converted prefix for autotools; fallback to original if conversion failed
if(NOT EP_AUTOTOOLS_PREFIX)
    to_msys_path("${THIRD_PARTY_LIB_PATH}" EP_AUTOTOOLS_PREFIX)
endif()
message(STATUS "WSL CC: ${CMAKE_C_COMPILER} -> ${_cc_msys}")
message(STATUS "WSL CXX: ${CMAKE_CXX_COMPILER} -> ${_cxx_msys}")
message(STATUS "WSL AR: ${CMAKE_AR} -> ${_ar_msys}")
message(STATUS "WSL PREFIX: ${THIRD_PARTY_LIB_PATH} -> ${EP_AUTOTOOLS_PREFIX}")
# AS is empty for Android (clang handles asm); omit it entirely to avoid
# 'invalid variable name' errors from autotools when passed as AS= with empty
# value that gets mis-parsed as a variable assignment.
set(EP_AUTOTOOLS_ARGS
    "--host=${ANDROID_TARGET}"
    "CC=${_cc_msys}"
    "CFLAGS=--target=${ANDROID_TARGET}${ANDROID_PLATFORM_LEVEL}"
    "CXX=${_cxx_msys}"
    "CXXFLAGS=--target=${ANDROID_TARGET}${ANDROID_PLATFORM_LEVEL}"
    "AR=${_ar_msys}"
    "LD=${_ld_msys}"
    "RANLIB=${_ranlib_msys}"
    "STRIP=${_strip_msys}"
    "--prefix=${EP_AUTOTOOLS_PREFIX}"
    "--disable-shared"
    "--enable-static"
    "--with-pic"
)
if(_as_msys)
    list(APPEND EP_AUTOTOOLS_ARGS "AS=${_as_msys}")
endif()
# For cmake -E env, we need the same args but as env vars (CC, CFLAGS, etc.)
# The helper will be called with only non-VAR args (like --host, --prefix, etc.)
# and the VAR=VALUE will be set via env.
# Space-separated version for use inside bash -c " ... ${EP_AUTOTOOLS_ARGS_STR} ..."
# (CMake lists are ; separated, but inside a bash string they need to be space separated)
string(REPLACE ";" " " EP_AUTOTOOLS_ARGS_STR "${EP_AUTOTOOLS_ARGS}")

# ---------------------------------------------------------------------------
# Autotools helper scripts (Windows MSYS cygpath handling)
# Avoids bash -c quoting issues: ; splits CMake list, " breaks stamp file.
# Helpers take <SOURCE_DIR> as $1, cygpath-convert it, cd there, then exec.
# ---------------------------------------------------------------------------
set(AUTOTOOLS_HELPER "${CMAKE_BINARY_DIR}/autotools_helper.sh")
file(WRITE "${AUTOTOOLS_HELPER}" "#!/usr/bin/env bash\nset -e\nsrc=\"$1\"\nshift\n# Handle Windows drive paths for both MSYS (/c/) and WSL (/mnt/c/)\nif [[ \"$src\" =~ ^[A-Za-z]:/ ]]; then\n  if command -v cygpath >/dev/null 2>&1; then src=$(cygpath -u \"$src\"); elif command -v wslpath >/dev/null 2>&1; then src=$(wslpath -u \"$src\" 2>/dev/null || echo \"$src\"); fi\nfi\ncd \"$src\"\nexec \"$@\"\n")
execute_process(COMMAND ${CMAKE_COMMAND} -E chmod +x "${AUTOTOOLS_HELPER}")
to_msys_path("${AUTOTOOLS_HELPER}" AUTOTOOLS_HELPER_MSYS)
# Fix CRLF written by file(WRITE) on Windows host (wsl bash chokes on \r) - must be after to_msys_path
if(IS_HOST_WINDOWS)
  execute_process(COMMAND ${WSL_EXECUTABLE} bash -c "tr -d '\\015' < \"${AUTOTOOLS_HELPER}\" > \"${AUTOTOOLS_HELPER}.tmp\" && mv \"${AUTOTOOLS_HELPER}.tmp\" \"${AUTOTOOLS_HELPER}\" || true" ERROR_QUIET)
  execute_process(COMMAND ${WSL_EXECUTABLE} bash -c "tr -d '\\015' < \"${AUTOTOOLS_HELPER_MSYS}\" > \"${AUTOTOOLS_HELPER_MSYS}.tmp\" && mv \"${AUTOTOOLS_HELPER_MSYS}.tmp\" \"${AUTOTOOLS_HELPER_MSYS}\" || true" ERROR_QUIET)
else()
  execute_process(COMMAND bash -c "tr -d '\\015' < \"${AUTOTOOLS_HELPER}\" > \"${AUTOTOOLS_HELPER}.tmp\" && mv \"${AUTOTOOLS_HELPER}.tmp\" \"${AUTOTOOLS_HELPER}\" || true" ERROR_QUIET)
endif()
set(AUTOTOOLS_HELPER_AUTOGEN "${CMAKE_BINARY_DIR}/autotools_helper_autogen.sh")
file(WRITE "${AUTOTOOLS_HELPER_AUTOGEN}" "#!/usr/bin/env bash\nset -e\nsrc=\"$1\"\nshift\nif [[ \"$src\" =~ ^[A-Za-z]:/ ]]; then\n  if command -v cygpath >/dev/null 2>&1; then src=$(cygpath -u \"$src\"); elif command -v wslpath >/dev/null 2>&1; then src=$(wslpath -u \"$src\" 2>/dev/null || echo \"$src\"); fi\nfi\ncd \"$src\"\nexec ./autogen.sh \"$@\"\n")
execute_process(COMMAND ${CMAKE_COMMAND} -E chmod +x "${AUTOTOOLS_HELPER_AUTOGEN}")
to_msys_path("${AUTOTOOLS_HELPER_AUTOGEN}" AUTOTOOLS_HELPER_AUTOGEN_MSYS)
if(IS_HOST_WINDOWS)
  execute_process(COMMAND ${WSL_EXECUTABLE} bash -c "tr -d '\\015' < \"${AUTOTOOLS_HELPER_AUTOGEN}\" > \"${AUTOTOOLS_HELPER_AUTOGEN}.tmp\" && mv \"${AUTOTOOLS_HELPER_AUTOGEN}.tmp\" \"${AUTOTOOLS_HELPER_AUTOGEN}\" || true" ERROR_QUIET)
  execute_process(COMMAND ${WSL_EXECUTABLE} bash -c "tr -d '\\015' < \"${AUTOTOOLS_HELPER_AUTOGEN_MSYS}\" > \"${AUTOTOOLS_HELPER_AUTOGEN_MSYS}.tmp\" && mv \"${AUTOTOOLS_HELPER_AUTOGEN_MSYS}.tmp\" \"${AUTOTOOLS_HELPER_AUTOGEN_MSYS}\" || true" ERROR_QUIET)
else()
  execute_process(COMMAND bash -c "tr -d '\\015' < \"${AUTOTOOLS_HELPER_AUTOGEN}\" > \"${AUTOTOOLS_HELPER_AUTOGEN}.tmp\" && mv \"${AUTOTOOLS_HELPER_AUTOGEN}.tmp\" \"${AUTOTOOLS_HELPER_AUTOGEN}\" || true" ERROR_QUIET)
endif()
set(AUTOTOOLS_HELPER_AUTOGEN_CONFIGURE "${CMAKE_BINARY_DIR}/autotools_helper_autogen_configure.sh")
file(WRITE "${AUTOTOOLS_HELPER_AUTOGEN_CONFIGURE}" "#!/usr/bin/env bash\nset -e\nsrc=\"$1\"\nshift\nif [[ \"$src\" =~ ^[A-Za-z]:/ ]]; then\n  if command -v cygpath >/dev/null 2>&1; then src=$(cygpath -u \"$src\"); elif command -v wslpath >/dev/null 2>&1; then src=$(wslpath -u \"$src\" 2>/dev/null || echo \"$src\"); fi\nfi\ncd \"$src\"\n./autogen.sh\nexec ./configure \"$@\"\n")
execute_process(COMMAND ${CMAKE_COMMAND} -E chmod +x "${AUTOTOOLS_HELPER_AUTOGEN_CONFIGURE}")
to_msys_path("${AUTOTOOLS_HELPER_AUTOGEN_CONFIGURE}" AUTOTOOLS_HELPER_AUTOGEN_CONFIGURE_MSYS)
if(IS_HOST_WINDOWS)
  execute_process(COMMAND ${WSL_EXECUTABLE} bash -c "tr -d '\\015' < \"${AUTOTOOLS_HELPER_AUTOGEN_CONFIGURE}\" > \"${AUTOTOOLS_HELPER_AUTOGEN_CONFIGURE}.tmp\" && mv \"${AUTOTOOLS_HELPER_AUTOGEN_CONFIGURE}.tmp\" \"${AUTOTOOLS_HELPER_AUTOGEN_CONFIGURE}\" || true" ERROR_QUIET)
  execute_process(COMMAND ${WSL_EXECUTABLE} bash -c "tr -d '\\015' < \"${AUTOTOOLS_HELPER_AUTOGEN_CONFIGURE_MSYS}\" > \"${AUTOTOOLS_HELPER_AUTOGEN_CONFIGURE_MSYS}.tmp\" && mv \"${AUTOTOOLS_HELPER_AUTOGEN_CONFIGURE_MSYS}.tmp\" \"${AUTOTOOLS_HELPER_AUTOGEN_CONFIGURE_MSYS}\" || true" ERROR_QUIET)
else()
  execute_process(COMMAND bash -c "tr -d '\\015' < \"${AUTOTOOLS_HELPER_AUTOGEN_CONFIGURE}\" > \"${AUTOTOOLS_HELPER_AUTOGEN_CONFIGURE}.tmp\" && mv \"${AUTOTOOLS_HELPER_AUTOGEN_CONFIGURE}.tmp\" \"${AUTOTOOLS_HELPER_AUTOGEN_CONFIGURE}\" || true" ERROR_QUIET)
endif()

# Patch helper for libiconv (avoids " and ; in PATCH_COMMAND which splits ExternalProject stamp)
# Handles both MSYS (/c/) and WSL (/mnt/c/) via cygpath/wslpath fallback.
set(PATCH_ICONV_HELPER "${CMAKE_BINARY_DIR}/patch_iconv.sh")
file(WRITE "${PATCH_ICONV_HELPER}" "#!/usr/bin/env bash\nset -e\nsrc=\"$1\"\nif [[ \"$src\" =~ ^[A-Za-z]:/ ]]; then\n  if command -v cygpath >/dev/null 2>&1; then src=$(cygpath -u \"$src\"); elif command -v wslpath >/dev/null 2>&1; then src=$(wslpath -u \"$src\" 2>/dev/null || echo \"$src\"); fi\nfi\ncd \"$src\"\n# Handle both possible locations for localcharset.c (MSYS and WSL sed)\nfor f in libcharset/lib/localcharset.c lib/localcharset.c; do if [ -f \"$f\" ]; then sed -i -e 's/codeset = nl_langinfo (CODESET)/codeset = \"UTF-8\"/' \"$f\" 2>/dev/null || true; sed -i -e 's/#if HAVE_LANGINFO_CODESET/#if 0 \\/\\/ patched/' \"$f\" 2>/dev/null || true; echo \"patched $f\"; fi; done\n# Prepend F_SETFD guard if not present; also guard duplicate case when F_GETFD==F_SETFD on some hosts\nif [ -f \"srclib/fcntl.c\" ] && ! grep -q 'ifndef F_SETFD' srclib/fcntl.c 2>/dev/null; then (echo '#ifndef F_SETFD' && echo '#define F_SETFD 2' && echo '#endif' && cat srclib/fcntl.c) > srclib/fcntl.c.tmp && mv srclib/fcntl.c.tmp srclib/fcntl.c && echo \"patched srclib/fcntl.c guard\"; fi\n# Ensure the inner switch does not duplicate when F_GETFD==F_SETFD (e.g. mis-detected host headers)\nif [ -f \"srclib/fcntl.c\" ]; then sed -i -e 's/#ifdef F_SETFD/#if defined(F_SETFD) \\&\\& F_SETFD != F_GETFD/' srclib/fcntl.c 2>/dev/null || true; echo \"patched srclib/fcntl.c duplicate guard\"; fi\necho patched-done\n")
execute_process(COMMAND ${CMAKE_COMMAND} -E chmod +x "${PATCH_ICONV_HELPER}")
to_msys_path("${PATCH_ICONV_HELPER}" PATCH_ICONV_HELPER_MSYS)
if(IS_HOST_WINDOWS)
  execute_process(COMMAND ${WSL_EXECUTABLE} bash -c "tr -d '\\015' < \"${PATCH_ICONV_HELPER}\" > \"${PATCH_ICONV_HELPER}.tmp\" && mv \"${PATCH_ICONV_HELPER}.tmp\" \"${PATCH_ICONV_HELPER}\" || true" ERROR_QUIET)
  execute_process(COMMAND ${WSL_EXECUTABLE} bash -c "tr -d '\\015' < \"${PATCH_ICONV_HELPER_MSYS}\" > \"${PATCH_ICONV_HELPER_MSYS}.tmp\" && mv \"${PATCH_ICONV_HELPER_MSYS}.tmp\" \"${PATCH_ICONV_HELPER_MSYS}\" || true" ERROR_QUIET)
else()
  execute_process(COMMAND bash -c "tr -d '\\015' < \"${PATCH_ICONV_HELPER}\" > \"${PATCH_ICONV_HELPER}.tmp\" && mv \"${PATCH_ICONV_HELPER}.tmp\" \"${PATCH_ICONV_HELPER}\" || true" ERROR_QUIET)
endif()

# Configure helper for libiconv (avoids bash -c quoting that breaks --host and CC propagation on WSL/MSYS)
# Takes <SOURCE_DIR> as $1, handles cygpath/wslpath, then runs ./configure with fixed args and post-sed.
set(CONFIGURE_ICONV_HELPER "${CMAKE_BINARY_DIR}/configure_iconv.sh")
file(WRITE "${CONFIGURE_ICONV_HELPER}" "#!/usr/bin/env bash\nset -e\nsrc=\"$1\"\nshift\nif [[ \"$src\" =~ ^[A-Za-z]:/ ]]; then\n  if command -v cygpath >/dev/null 2>&1; then src=$(cygpath -u \"$src\"); elif command -v wslpath >/dev/null 2>&1; then src=$(wslpath -u \"$src\" 2>/dev/null || echo \"$src\"); fi\nfi\n# Prefix may be Windows style; convert similarly\nprefix_in=\"$1\"\nif [[ \"$prefix_in\" =~ ^[A-Za-z]:/ ]]; then\n  if command -v cygpath >/dev/null 2>&1; then prefix_in=$(cygpath -u \"$prefix_in\" 2>/dev/null || echo \"$prefix_in\"); elif command -v wslpath >/dev/null 2>&1; then prefix_in=$(wslpath -u \"$prefix_in\" 2>/dev/null || echo \"$prefix_in\"); fi\nfi\n# Remaining args: host triple\nHOST_TRIPLE=\"$2\"\ncd \"$src\"\n./configure \"--host=$HOST_TRIPLE\" \"--prefix=$prefix_in\" --disable-shared --enable-static --with-pic --enable-extra-encodings\nsed -i -e '/^#define gid_t/d' -e '/^#define uid_t/d' -e '/^#define HAVE_LANGINFO_CODESET/d' config.h\nsed -i -e '/^#define HAVE_LANGINFO_CODESET/d' libcharset/config.h 2>/dev/null || true\n# For Android cross-compile, skip building the `iconv` binary in src/ (host tool, fails to link with NDK rpl_*)\nsed -i -e '/cd src && \\$(MAKE)/s/^/# /' Makefile 2>/dev/null || true\n")
execute_process(COMMAND ${CMAKE_COMMAND} -E chmod +x "${CONFIGURE_ICONV_HELPER}")
to_msys_path("${CONFIGURE_ICONV_HELPER}" CONFIGURE_ICONV_HELPER_MSYS)
if(IS_HOST_WINDOWS)
  execute_process(COMMAND ${WSL_EXECUTABLE} bash -c "tr -d '\\015' < \"${CONFIGURE_ICONV_HELPER}\" > \"${CONFIGURE_ICONV_HELPER}.tmp\" && mv \"${CONFIGURE_ICONV_HELPER}.tmp\" \"${CONFIGURE_ICONV_HELPER}\" || true" ERROR_QUIET)
  execute_process(COMMAND ${WSL_EXECUTABLE} bash -c "tr -d '\\015' < \"${CONFIGURE_ICONV_HELPER_MSYS}\" > \"${CONFIGURE_ICONV_HELPER_MSYS}.tmp\" && mv \"${CONFIGURE_ICONV_HELPER_MSYS}.tmp\" \"${CONFIGURE_ICONV_HELPER_MSYS}\" || true" ERROR_QUIET)
else()
  execute_process(COMMAND bash -c "tr -d '\\015' < \"${CONFIGURE_ICONV_HELPER}\" > \"${CONFIGURE_ICONV_HELPER}.tmp\" && mv \"${CONFIGURE_ICONV_HELPER}.tmp\" \"${CONFIGURE_ICONV_HELPER}\" || true" ERROR_QUIET)
endif()

set(INSTALL_ICONV_HELPER "${CMAKE_BINARY_DIR}/install_iconv.sh")
file(WRITE "${INSTALL_ICONV_HELPER}" [=[#!/usr/bin/env bash
set -e
src="$1"
shift
if [[ "$src" =~ ^[A-Za-z]:/ ]]; then
  if command -v cygpath >/dev/null 2>&1; then src=$(cygpath -u "$src"); elif command -v wslpath >/dev/null 2>&1; then src=$(wslpath -u "$src" 2>/dev/null || echo "$src"); fi
fi
prefix_in="$1"
if [[ "$prefix_in" =~ ^[A-Za-z]:/ ]]; then
  if command -v cygpath >/dev/null 2>&1; then prefix_in=$(cygpath -u "$prefix_in" 2>/dev/null || echo "$prefix_in"); elif command -v wslpath >/dev/null 2>&1; then prefix_in=$(wslpath -u "$prefix_in" 2>/dev/null || echo "$prefix_in"); fi
fi
cd "$src"
make -j1 install V=1
mkdir -p "$prefix_in/lib/pkgconfig"
# Use Windows C:/ style for .pc prefix so pkg-config emits C:/ for NDK's Windows clang
# (which is invoked as C:/.../clang++.exe with C:\... test files from WSL's meson)
prefix_win="$prefix_in"
if command -v cygpath >/dev/null 2>&1; then prefix_win=$(cygpath -w "$prefix_in" 2>/dev/null || echo "$prefix_in"); prefix_win=$(echo "$prefix_win" | sed 's|\\|/|g'); fi
cat > "$prefix_in/lib/pkgconfig/iconv.pc" <<EOF
prefix=$prefix_win
exec_prefix=\${prefix}
libdir=\${exec_prefix}/lib
includedir=\${prefix}/include

Name: iconv
Description: libiconv
Version: 1.17
Libs: -L\${libdir} -liconv -lcharset
Cflags: -I\${includedir}
EOF
cp "$prefix_in/lib/pkgconfig/iconv.pc" "$prefix_in/lib/pkgconfig/libiconv.pc"
# Also ensure the .pc is found via both MSYS and WSL pkg-config by duplicating with mnt path if needed
if [[ "$prefix_in" == /c/* ]]; then
  mkdir -p "/mnt${prefix_in}/lib/pkgconfig" 2>/dev/null || true
  cp "$prefix_in/lib/pkgconfig/iconv.pc" "/mnt${prefix_in}/lib/pkgconfig/iconv.pc" 2>/dev/null || true
  cp "$prefix_in/lib/pkgconfig/iconv.pc" "/mnt${prefix_in}/lib/pkgconfig/libiconv.pc" 2>/dev/null || true
fi
]=])
execute_process(COMMAND ${CMAKE_COMMAND} -E chmod +x "${INSTALL_ICONV_HELPER}")
to_msys_path("${INSTALL_ICONV_HELPER}" INSTALL_ICONV_HELPER_MSYS)
if(IS_HOST_WINDOWS)
  execute_process(COMMAND ${WSL_EXECUTABLE} bash -c "tr -d '\\015' < \"${INSTALL_ICONV_HELPER}\" > \"${INSTALL_ICONV_HELPER}.tmp\" && mv \"${INSTALL_ICONV_HELPER}.tmp\" \"${INSTALL_ICONV_HELPER}\" || true" ERROR_QUIET)
  execute_process(COMMAND ${WSL_EXECUTABLE} bash -c "tr -d '\\015' < \"${INSTALL_ICONV_HELPER_MSYS}\" > \"${INSTALL_ICONV_HELPER_MSYS}.tmp\" && mv \"${INSTALL_ICONV_HELPER_MSYS}.tmp\" \"${INSTALL_ICONV_HELPER_MSYS}\" || true" ERROR_QUIET)
else()
  execute_process(COMMAND bash -c "tr -d '\\015' < \"${INSTALL_ICONV_HELPER}\" > \"${INSTALL_ICONV_HELPER}.tmp\" && mv \"${INSTALL_ICONV_HELPER}.tmp\" \"${INSTALL_ICONV_HELPER}\" || true" ERROR_QUIET)
endif()

include("cmake/zlib.cmake")
include("cmake/lcms2.cmake")

include("cmake/libwebp.cmake")
include("cmake/libjpeg-turbo.cmake")
include("cmake/libopenjp2.cmake")
include("cmake/libpng.cmake")
include("cmake/libtiff.cmake")

include("cmake/dav1d.cmake")
include("cmake/libde265.cmake")
include("cmake/libheif.cmake")

include("cmake/brotli.cmake")
include("cmake/highway.cmake")
include("cmake/libjxl.cmake")

include("cmake/libffi.cmake")
include("cmake/libiconv.cmake")
include("cmake/glib.cmake")

include("cmake/libexpat.cmake")
include("cmake/libvips.cmake")

include(ExternalProject)
ExternalProject_Add(ep_imagedecoder
    INSTALL_COMMAND ""
    SOURCE_DIR ${PROJECT_SOURCE_DIR}/imagedecoder
    DEPENDS ep_libvips
    BUILD_ALWAYS 1
    CMAKE_ARGS
        ${EP_CMAKE_ARGS}
        "-DCMAKE_LIBRARY_OUTPUT_DIRECTORY=${CMAKE_LIBRARY_OUTPUT_DIRECTORY}"
        "-DCMAKE_RUNTIME_OUTPUT_DIRECTORY=${CMAKE_RUNTIME_OUTPUT_DIRECTORY}"
)
