cmake_minimum_required(VERSION 3.22.1)

# CMP0135: DOWNLOAD_EXTRACT_TIMESTAMP - use extraction time, not archive time
if(POLICY CMP0135)
    cmake_policy(SET CMP0135 NEW)
endif()

project("imagedecoder_s")

# ---------------------------------------------------------------------------
# Helper: Convert a Windows absolute path (C:/foo or C:\foo) to MSYS Unix path
# (/c/foo). Handles any drive letter, lower-cases it, and preserves the rest.
# If path is already Unix (/c/... or /...), returns unchanged. If not absolute,
# returns the cmake-normalised path.
# ---------------------------------------------------------------------------
function(to_msys_path win_path out_var)
    # Normalise backslashes to forward slashes without using file(TO_CMAKE_PATH),
    # which behaves differently on Linux vs Windows (on Linux it inserts ';').
    string(REPLACE "\\" "/" _tmp "${win_path}")
    # Already MSYS Unix style? (/c/... or /d/... or /usr/...)
    if(_tmp MATCHES "^/[a-z]/")
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
        set(${out_var} "/${_drive}/${CMAKE_MATCH_2}" PARENT_SCOPE)
    else()
        set(${out_var} "${_tmp}" PARENT_SCOPE)
    endif()
endfunction()

# ---------------------------------------------------------------------------
# Tool detection: Make
# ---------------------------------------------------------------------------
# Prefer MSYS2 make on Windows over MinGW or other makes that mis-handle
# MSYS paths. Search MSYS locations first when WIN32. If Make_EXECUTABLE
# was already passed via -D (e.g., from build.gradle.kts), keep it.
if(WIN32 AND NOT Make_EXECUTABLE)
    # Strictly require MSYS2 make on Windows. Chocolatey/MinGW make cannot
    # handle MSYS Unix paths (/c/...) and breaks autotools (C:/ vs /c/).
    # Check all known MSYS2 locations (msys, mingw64, ucrt64, clang64).
    set(_msys_make_candidates
        "C:/msys64/usr/bin/make.exe"
        "C:/msys64/bin/make.exe"
        "C:/msys64/mingw64/bin/make.exe"
        "C:/msys64/mingw64/bin/mingw32-make.exe"
        "C:/msys64/ucrt64/bin/make.exe"
        "C:/msys64/ucrt64/bin/mingw32-make.exe"
        "C:/msys64/clang64/bin/make.exe"
        "C:/tools/msys64/usr/bin/make.exe"
        "C:/tools/msys64/mingw64/bin/make.exe"
        "D:/msys64/usr/bin/make.exe"
        "C:/msys2/usr/bin/make.exe"
    )
    foreach(_p IN LISTS _msys_make_candidates)
        if(EXISTS "${_p}")
            set(Make_EXECUTABLE "${_p}" CACHE FILEPATH "MSYS2 Make" FORCE)
            message(STATUS "Found MSYS2 make at ${_p}")
            break()
        endif()
    endforeach()
    if(NOT Make_EXECUTABLE)
        # Fallback: search PATH for any make that is from MSYS (contains msys)
        find_program(Make_EXECUTABLE NAMES make gmake mingw32-make)
        if(Make_EXECUTABLE AND Make_EXECUTABLE MATCHES "msys")
            message(STATUS "Found MSYS make via PATH: ${Make_EXECUTABLE}")
        elseif(Make_EXECUTABLE)
            message(STATUS "Found non-MSYS make at '${Make_EXECUTABLE}' - ignoring, need MSYS")
            unset(Make_EXECUTABLE)
            unset(Make_EXECUTABLE CACHE)
            # Try where.exe to locate MSYS make
            execute_process(
                COMMAND where make
                OUTPUT_VARIABLE _where_make
                OUTPUT_STRIP_TRAILING_WHITESPACE
                ERROR_QUIET
            )
            message(STATUS "where make output: ${_where_make}")
            string(REGEX MATCH "([^\r\n]*msys64[^\r\n]*make\\.exe)" _msys_make "${_where_make}")
            if(_msys_make AND EXISTS "${_msys_make}")
                set(Make_EXECUTABLE "${_msys_make}" CACHE FILEPATH "MSYS2 Make" FORCE)
                message(STATUS "Found MSYS make via where: ${Make_EXECUTABLE}")
            endif()
        endif()
    endif()
    if(NOT Make_EXECUTABLE OR NOT EXISTS "${Make_EXECUTABLE}")
        message(FATAL_ERROR
            "MSYS2 make not found. Searched:\n"
            "  ${_msys_make_candidates}\n"
            "  and PATH (found '${Make_EXECUTABLE}').\n"
            "  Install MSYS2 from https://www.msys2.org, then in MSYS2 shell run:\n"
            "    pacman -S make base-devel autoconf automake libtool pkg-config\n"
            "  Verify: In PowerShell run 'Get-ChildItem C:\\msys64\\usr\\bin\\make.exe' and 'where.exe make'\n"
            "  After installing, delete external/imagedecoder-houri/library/.cxx and re-sync Gradle.\n"
            "  Or set -DMake_EXECUTABLE=C:/msys64/usr/bin/make.exe explicitly.")
    endif()
endif()
if(NOT Make_EXECUTABLE)
    find_program(Make_EXECUTABLE make)
endif()
# Final guard: if we somehow still picked chocolatey, error
if(Make_EXECUTABLE MATCHES "chocolatey|ProgramData")
    message(FATAL_ERROR
        "MSYS2 make is required on Windows but found '${Make_EXECUTABLE}'.\n"
        "  This is a non-MSYS make (chocolatey) that cannot handle MSYS Unix paths (/c/...).\n"
        "  Fix: In MSYS2 shell (e.g., MSYS2 MinGW 64-bit), run:\n"
        "    pacman -S make base-devel autoconf automake libtool pkg-config\n"
        "  Then ensure C:/msys64/usr/bin is before C:/ProgramData/chocolatey/bin in your PATH,\n"
        "  or set -DMake_EXECUTABLE=C:/msys64/usr/bin/make.exe\n"
        "  After installing, delete external/imagedecoder-houri/library/.cxx and re-sync Gradle.")
endif()
if(NOT Make_EXECUTABLE)
    message(FATAL_ERROR
        "Make is required.\n"
        "  Windows MSYS64: pacman -S make  (or base-devel)\n"
        "  Ensure C:/msys64/usr/bin is on PATH or set -DMake_EXECUTABLE=...")
endif()
message(STATUS "Using Make: ${Make_EXECUTABLE}")

# ---------------------------------------------------------------------------
# Tool detection: Meson
# ---------------------------------------------------------------------------
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

# ---------------------------------------------------------------------------
# Tool detection: Bash (critical for autotools on Windows)
# In MSYS2, /usr/bin/bash.exe and /bin/bash.exe are the same file but we
# probe both. We also honour $MSYS2_ROOT / $MSYSTEM env hints.
# WSL's C:\\Windows\\System32\\bash.exe uses /mnt/c/... paths and MUST be
# avoided – it breaks autotools path handling.
# ---------------------------------------------------------------------------
if(WIN32)
    # Honour explicit env var if user set MSYS2 location
    if(DEFINED ENV{MSYS2_ROOT} AND EXISTS "$ENV{MSYS2_ROOT}/usr/bin/bash.exe")
        set(_msys_hint_bash "$ENV{MSYS2_ROOT}/usr/bin/bash.exe")
    elseif(DEFINED ENV{MSYS_ROOT} AND EXISTS "$ENV{MSYS_ROOT}/usr/bin/bash.exe")
        set(_msys_hint_bash "$ENV{MSYS_ROOT}/usr/bin/bash.exe")
    endif()
    if(_msys_hint_bash)
        set(BASH_EXECUTABLE "${_msys_hint_bash}" CACHE FILEPATH "MSYS2 Bash" FORCE)
        message(STATUS "Using BASH from env hint: ${BASH_EXECUTABLE}")
    elseif(EXISTS "C:/msys64/usr/bin/bash.exe")
        set(BASH_EXECUTABLE "C:/msys64/usr/bin/bash.exe" CACHE FILEPATH "MSYS2 Bash" FORCE)
    elseif(EXISTS "C:/tools/msys64/usr/bin/bash.exe")
        set(BASH_EXECUTABLE "C:/tools/msys64/usr/bin/bash.exe" CACHE FILEPATH "MSYS2 Bash" FORCE)
    elseif(EXISTS "D:/msys64/usr/bin/bash.exe")
        set(BASH_EXECUTABLE "D:/msys64/usr/bin/bash.exe" CACHE FILEPATH "MSYS2 Bash" FORCE)
    elseif(EXISTS "C:/msys64/bin/bash.exe")
        set(BASH_EXECUTABLE "C:/msys64/bin/bash.exe" CACHE FILEPATH "MSYS2 Bash" FORCE)
    elseif(EXISTS "C:/Program Files/Git/usr/bin/bash.exe")
        set(BASH_EXECUTABLE "C:/Program Files/Git/usr/bin/bash.exe" CACHE FILEPATH "Git Bash" FORCE)
    elseif(EXISTS "C:/Program Files/Git/bin/bash.exe")
        set(BASH_EXECUTABLE "C:/Program Files/Git/bin/bash.exe" CACHE FILEPATH "Git Bash" FORCE)
    elseif(BASH_EXECUTABLE MATCHES "System32|WindowsApps" OR NOT BASH_EXECUTABLE)
        find_program(_better_bash bash
            HINTS
                "C:/msys64/usr/bin"
                "C:/msys64/bin"
                "C:/tools/msys64/usr/bin"
                "C:/tools/msys64/bin"
                "D:/msys64/usr/bin"
                "C:/Program Files/Git/usr/bin"
                "C:/Program Files/Git/bin"
            NO_DEFAULT_PATH
        )
        if(_better_bash)
            set(BASH_EXECUTABLE "${_better_bash}" CACHE FILEPATH "Bash" FORCE)
        elseif(NOT BASH_EXECUTABLE)
            find_program(BASH_EXECUTABLE bash)
        endif()
    endif()
    if(BASH_EXECUTABLE MATCHES "System32")
        message(WARNING "BASH_EXECUTABLE points at WSL bash (${BASH_EXECUTABLE}) – "
            "this will break autotools (needs MSYS2 /c/... not /mnt/c/...). "
            "Install MSYS2 from https://www.msys2.org and ensure C:/msys64/usr/bin/bash.exe exists.")
    endif()
endif()
if(NOT BASH_EXECUTABLE)
    find_program(BASH_EXECUTABLE bash)
endif()
if(NOT BASH_EXECUTABLE)
    set(BASH_EXECUTABLE "bash")
endif()
set(AUTOTOOLS_BASH_PREFIX "${BASH_EXECUTABLE}")
message(STATUS "Using BASH for autotools: ${BASH_EXECUTABLE}")

# ---------------------------------------------------------------------------
# Windows MSYS2 sanity checks: autoreconf / autoconf / automake / libtool
# These are required for libffi (autogen.sh) and lcms2 (autogen.sh).
# We test via bash so the check respects the MSYS PATH view, not Windows PATH.
# ---------------------------------------------------------------------------
if(WIN32)
    # Build PATH that bash will see: prepend MSYS bin dirs if they exist.
    set(_msys_path_extra "")
    foreach(_d IN ITEMS "C:/msys64/usr/bin" "C:/msys64/bin" "C:/tools/msys64/usr/bin" "D:/msys64/usr/bin")
        if(EXISTS "${_d}")
            if(_msys_path_extra)
                set(_msys_path_extra "${_d}:${_msys_path_extra}")
            else()
                set(_msys_path_extra "${_d}")
            endif()
        endif()
    endforeach()
    # Probe autoreconf inside MSYS bash
    execute_process(
        COMMAND "${BASH_EXECUTABLE}" -c "command -v autoreconf >/dev/null 2>&1 && echo FOUND || echo MISSING"
        OUTPUT_VARIABLE _autoreconf_probe
        OUTPUT_STRIP_TRAILING_WHITESPACE
        ERROR_QUIET
    )
    if(_autoreconf_probe STREQUAL "MISSING")
        message(WARNING
            "autoreconf not found inside MSYS bash (${BASH_EXECUTABLE}).\n"
            "  lcms2 and libffi use autogen.sh which requires autoconf/automake/libtool.\n"
            "  Fix (MSYS2 MinGW shell): pacman -S base-devel autoconf automake libtool pkg-config\n"
            "  Alternative (MSYS2 UCRT shell): pacman -S autoconf automake libtool\n"
            "  After installing, delete the .cxx cache and re-sync Gradle.\n"
        )
    else()
        message(STATUS "MSYS autoreconf: found")
    endif()
    # Probe pkg-config similarly (needed by meson/cross file and libvips)
    execute_process(
        COMMAND "${BASH_EXECUTABLE}" -c "command -v pkg-config >/dev/null 2>&1 && echo FOUND || echo MISSING"
        OUTPUT_VARIABLE _pkg_probe
        OUTPUT_STRIP_TRAILING_WHITESPACE
        ERROR_QUIET
    )
    if(_pkg_probe STREQUAL "MISSING")
        message(WARNING "pkg-config not found inside MSYS bash – meson builds (glib/libvips) may fail. Install: pacman -S pkg-config")
    endif()
endif()

# Prefer Android SDK's ninja (no Program Files space) over Meson's ninja.
# On Windows, "C:/Program Files/Meson/ninja.exe" contains a space which
# breaks ExternalProject's CMAKE_ARGS when passed as -DCMAKE_MAKE_PROGRAM.
# We detect a space and either find an alternative without space or skip
# setting CMAKE_MAKE_PROGRAM and let CMake find ninja via PATH.
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
if(Ninja_EXECUTABLE)
    if(Ninja_EXECUTABLE MATCHES " ")
        message(WARNING "Ninja at '${Ninja_EXECUTABLE}' contains space - may break try_compile. "
            "Attempting to find alternative without space or will skip CMAKE_MAKE_PROGRAM.")
        # Try to find ninja via PATH without the Program Files one
        find_program(_alt_ninja ninja NO_CMAKE_PATH)
        if(_alt_ninja AND NOT _alt_ninja MATCHES " ")
            set(Ninja_EXECUTABLE "${_alt_ninja}")
            message(STATUS "Using alternative Ninja without space: ${Ninja_EXECUTABLE}")
        else()
            # Try Android SDK's ninja explicitly
            if(EXISTS "$ENV{ANDROID_HOME}/cmake/3.22.1/bin/ninja.exe")
                set(Ninja_EXECUTABLE "$ENV{ANDROID_HOME}/cmake/3.22.1/bin/ninja.exe")
                message(STATUS "Falling back to Android SDK Ninja: ${Ninja_EXECUTABLE}")
            elseif(EXISTS "C:/Users/Branden/AppData/Local/Android/Sdk/cmake/3.22.1/bin/ninja.exe")
                set(Ninja_EXECUTABLE "C:/Users/Branden/AppData/Local/Android/Sdk/cmake/3.22.1/bin/ninja.exe")
            else()
                message(STATUS "Skipping CMAKE_MAKE_PROGRAM due to space - CMake will auto-detect ninja")
                set(Ninja_EXECUTABLE "")
            endif()
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
# meson's --prefix must be a Unix absolute path (/c/...), not a Windows
# absolute (C:/...). The autotools --prefix must also be Unix (/c/...) when
# invoked via MSYS bash, otherwise `CC=C:/...` is parsed as variable C.
# We keep both forms: EP_MESON_PREFIX (Unix for meson) and
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

# Cross file: for cross builds (host=android) include/lib paths must be Unix
# even on Windows. EP_MESON_PREFIX is already converted via to_msys_path,
# so we can use it unconditionally.
set(_cross_inc "${EP_MESON_PREFIX}/include")
set(_cross_lib "${EP_MESON_PREFIX}/lib")
set(_cross_pkg "${_pkg_msys}")

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
pkg_config_path = ['${_cross_pkg}']

[properties]
cmake_toolchain_file = '${CMAKE_TOOLCHAIN_FILE}'
pkg_config_libdir = '${_cross_pkg}'

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
if(Ninja_EXECUTABLE)
    list(APPEND EP_CMAKE_ARGS "-DCMAKE_MAKE_PROGRAM=${Ninja_EXECUTABLE}")
endif()

# Autotools via MSYS bash: every absolute host path must be Unix (/c/...)
# otherwise `CC=C:/foo` is tokenised as variable C with value :/foo and
# the trailing `0` from `C:` split causes `invalid variable name: '0'`.
# This handles *any* drive letter (C, D, ...), not just C. We convert
# unconditionally: on Linux to_msys_path leaves Unix paths unchanged, on
# Windows it converts C:/... -> /c/... . This avoids relying on if(WIN32)
# which can be unreliable when CMAKE_SYSTEM_NAME is set to Android.
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
message(STATUS "MSYS CC: ${CMAKE_C_COMPILER} -> ${_cc_msys}")
message(STATUS "MSYS CXX: ${CMAKE_CXX_COMPILER} -> ${_cxx_msys}")
message(STATUS "MSYS AR: ${CMAKE_AR} -> ${_ar_msys}")
message(STATUS "MSYS PREFIX: ${THIRD_PARTY_LIB_PATH} -> ${EP_AUTOTOOLS_PREFIX}")
# AS is empty for Android (clang handles asm); keep empty to avoid
# passing a Windows path that would be mis-parsed. If you need a real AS,
# use _as_msys.
set(EP_AUTOTOOLS_ARGS
    "--host=${ANDROID_TARGET}"
    "CC=${_cc_msys}"
    "CFLAGS=--target=${ANDROID_TARGET}${ANDROID_PLATFORM_LEVEL}"
    "CXX=${_cxx_msys}"
    "CXXFLAGS=--target=${ANDROID_TARGET}${ANDROID_PLATFORM_LEVEL}"
    "AR=${_ar_msys}"
    "AS="
    "LD=${_ld_msys}"
    "RANLIB=${_ranlib_msys}"
    "STRIP=${_strip_msys}"
    "--prefix=${EP_AUTOTOOLS_PREFIX}"
    "--disable-shared"
    "--enable-static"
    "--with-pic"
)
# Space-separated version for use inside bash -c " ... ${EP_AUTOTOOLS_ARGS_STR} ..."
# (CMake lists are ; separated, but inside a bash string they need to be space separated)
string(REPLACE ";" " " EP_AUTOTOOLS_ARGS_STR "${EP_AUTOTOOLS_ARGS}")

# ---------------------------------------------------------------------------
# Autotools helper scripts (Windows MSYS cygpath handling)
# Avoids bash -c quoting issues: ; splits CMake list, " breaks stamp file.
# Helpers take <SOURCE_DIR> as $1, cygpath-convert it, cd there, then exec.
# ---------------------------------------------------------------------------
set(AUTOTOOLS_HELPER "${CMAKE_BINARY_DIR}/autotools_helper.sh")
file(WRITE "${AUTOTOOLS_HELPER}" "#!/usr/bin/env bash\nset -e\nsrc=\"$1\"\nshift\nif command -v cygpath >/dev/null 2>&1; then\n  src=$(cygpath -u \"$src\")\nfi\ncd \"$src\"\nexec \"$@\"\n")
execute_process(COMMAND ${CMAKE_COMMAND} -E chmod +x "${AUTOTOOLS_HELPER}")
to_msys_path("${AUTOTOOLS_HELPER}" AUTOTOOLS_HELPER_MSYS)
set(AUTOTOOLS_HELPER_AUTOGEN "${CMAKE_BINARY_DIR}/autotools_helper_autogen.sh")
file(WRITE "${AUTOTOOLS_HELPER_AUTOGEN}" "#!/usr/bin/env bash\nset -e\nsrc=\"$1\"\nshift\nif command -v cygpath >/dev/null 2>&1; then\n  src=$(cygpath -u \"$src\")\nfi\ncd \"$src\"\nexec ./autogen.sh \"$@\"\n")
execute_process(COMMAND ${CMAKE_COMMAND} -E chmod +x "${AUTOTOOLS_HELPER_AUTOGEN}")
to_msys_path("${AUTOTOOLS_HELPER_AUTOGEN}" AUTOTOOLS_HELPER_AUTOGEN_MSYS)
set(AUTOTOOLS_HELPER_AUTOGEN_CONFIGURE "${CMAKE_BINARY_DIR}/autotools_helper_autogen_configure.sh")
file(WRITE "${AUTOTOOLS_HELPER_AUTOGEN_CONFIGURE}" "#!/usr/bin/env bash\nset -e\nsrc=\"$1\"\nshift\nif command -v cygpath >/dev/null 2>&1; then\n  src=$(cygpath -u \"$src\")\nfi\ncd \"$src\"\n./autogen.sh\nexec ./configure \"$@\"\n")
execute_process(COMMAND ${CMAKE_COMMAND} -E chmod +x "${AUTOTOOLS_HELPER_AUTOGEN_CONFIGURE}")
to_msys_path("${AUTOTOOLS_HELPER_AUTOGEN_CONFIGURE}" AUTOTOOLS_HELPER_AUTOGEN_CONFIGURE_MSYS)

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
