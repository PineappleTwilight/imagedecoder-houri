cmake_minimum_required(VERSION 3.22.1)

project("imagedecoder_s")

find_program(Make_EXECUTABLE make)
if(NOT Make_EXECUTABLE)
    message(FATAL_ERROR "Make is required")
endif()

find_program(Meson_EXECUTABLE
    NAMES meson meson.exe
    HINTS
        "C:/Program Files/Meson"
        "$ENV{ProgramFiles}/Meson"
        "$ENV{ProgramW6432}/Meson"
        "$ENV{LOCALAPPDATA}/Programs/Meson"
        "$ENV{USERPROFILE}/AppData/Local/Programs/Meson"
        "C:/Program Files (x86)/Meson"
    PATH_SUFFIXES bin
)
if(NOT Meson_EXECUTABLE)
    message(FATAL_ERROR "Meson is required (tried PATH and C:/Program Files/Meson/meson.exe; add Meson to PATH or set -DMeson_EXECUTABLE=...)")
endif()
# Autotools `configure` scripts need bash; prefer Git for Windows bash on Windows
# over WSL's C:\Windows\System32\bash.exe (which expects /mnt/c/... paths).
if(WIN32)
    find_program(BASH_EXECUTABLE bash
        HINTS
            "C:/Program Files/Git/usr/bin"
            "C:/Program Files/Git/bin"
            "C:/msys64/usr/bin"
            "C:/msys64/bin"
            "C:/tools/msys64/usr/bin"
        NO_DEFAULT_PATH
    )
    if(NOT BASH_EXECUTABLE)
        find_program(BASH_EXECUTABLE bash)
    endif()
else()
    find_program(BASH_EXECUTABLE bash)
endif()
if(NOT BASH_EXECUTABLE)
    set(BASH_EXECUTABLE "bash")
endif()
set(AUTOTOOLS_BASH_PREFIX "${BASH_EXECUTABLE}")
find_program(Ninja_EXECUTABLE NAMES ninja ninja.exe
    HINTS
        "$ENV{ANDROID_HOME}/cmake/3.22.1/bin"
        "$ENV{ANDROID_SDK_ROOT}/cmake/3.22.1/bin"
        "C:/Program Files/Meson"
        "$ENV{ProgramFiles}/Meson"
        "C:/Program Files/Ninja"
)
# Keep forward slashes for -DCMAKE_MAKE_PROGRAM to avoid space splitting on Windows
if(Ninja_EXECUTABLE)
    file(TO_CMAKE_PATH "${Ninja_EXECUTABLE}" Ninja_EXECUTABLE)
endif()

set(THIRD_PARTY_LIB_PATH ${CMAKE_BINARY_DIR}/fakeroot)
if(WIN32)
    file(TO_NATIVE_PATH "${THIRD_PARTY_LIB_PATH}" _meson_prefix_native)
    set(EP_MESON_PREFIX "${_meson_prefix_native}")
else()
    set(EP_MESON_PREFIX "${THIRD_PARTY_LIB_PATH}")
endif()
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
    message(FATAL_ERROR "Unsupported architecture: ${ANDROID_ABI}")
endif()

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
c_args = ['-I${THIRD_PARTY_LIB_PATH}/include', '-Wno-error=format-nonliteral']
cpp_args = ['-I${THIRD_PARTY_LIB_PATH}/include', '-Wno-error=format-nonliteral', '-DHAVE_POSIX_MEMALIGN']
c_link_args = ['-L${THIRD_PARTY_LIB_PATH}/lib']
cpp_link_args = ['-L${THIRD_PARTY_LIB_PATH}/lib']
pkg_config_path = ['${THIRD_PARTY_LIB_PATH}/lib/pkgconfig']

[properties]
cmake_toolchain_file = '${CMAKE_TOOLCHAIN_FILE}'
pkg_config_libdir = '${THIRD_PARTY_LIB_PATH}/lib/pkgconfig'

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

# Detect CPU count for parallel builds
include(ProcessorCount)
ProcessorCount(NPROC)
if(NPROC EQUAL 0)
    set(NPROC 4)
endif()

# Common args to all Mason ExternalProjects
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
    "-DCMAKE_INSTALL_PREFIX=${CMAKE_BINARY_DIR}/fakeroot"
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

set(EP_AUTOTOOLS_ARGS
    "--host=${ANDROID_TARGET}${ANDROID_PLATFORM_LEVEL}"
    "CC=${CMAKE_C_COMPILER} --target=${ANDROID_TARGET}${ANDROID_PLATFORM_LEVEL}"
    "CXX=${CMAKE_CXX_COMPILER} --target=${ANDROID_TARGET}${ANDROID_PLATFORM_LEVEL}"
    "AR=${CMAKE_AR}"
    "AS=${CMAKE_ASM_COMPILER}"
    "LD=${CMAKE_LINKER}"
    "RANLIB=${CMAKE_RANLIB}"
    "STRIP=${CMAKE_STRIP}"
    "--prefix=${THIRD_PARTY_LIB_PATH}"
    "--disable-shared"
    "--enable-static"
    "--with-pic"
)

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
