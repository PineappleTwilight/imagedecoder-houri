include(ExternalProject)

# Use bash -c wrapper with cygpath fallback so the same command works on
# both MSYS2 (where <SOURCE_DIR> is C:/... and needs /c/... for bash) and
# on Linux (where cygpath doesn't exist and the path is already Unix).
ExternalProject_Add(ep_libiconv
    URL https://ftp.gnu.org/pub/gnu/libiconv/libiconv-1.17.tar.gz
    CONFIGURE_COMMAND
        "${BASH_EXECUTABLE}" -c
        "set -e; if command -v cygpath >/dev/null 2>&1; then src=$(cygpath -u \"<SOURCE_DIR>\"); bld=$(cygpath -u \"<BINARY_DIR>\"); else src=\"<SOURCE_DIR>\"; bld=\"<BINARY_DIR>\"; fi; mkdir -p \"$bld\" && cd \"$bld\" && \"$src/configure\" ${EP_AUTOTOOLS_ARGS} --enable-extra-encodings"
    BUILD_COMMAND ${Make_EXECUTABLE} -j${NPROC}
    INSTALL_COMMAND ${Make_EXECUTABLE} -j${NPROC} install
    BUILD_IN_SOURCE 0
)
