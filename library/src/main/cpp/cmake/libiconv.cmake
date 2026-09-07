include(ExternalProject)

# Use bash -c with cygpath so C:/... (Windows) is seen as /c/... inside MSYS bash.
# On Linux, cygpath doesn't exist and the path is already Unix, so fallback is used.
# EP_AUTOTOOLS_ARGS_STR is space-separated (not ; separated) for inside the string.
ExternalProject_Add(ep_libiconv
    URL https://ftp.gnu.org/pub/gnu/libiconv/libiconv-1.17.tar.gz
    CONFIGURE_COMMAND
        "${BASH_EXECUTABLE}" -c
        "set -e; if command -v cygpath >/dev/null 2>&1; then src=$(cygpath -u \"<SOURCE_DIR>\"); bld=$(cygpath -u \"<BINARY_DIR>\"); else src=\"<SOURCE_DIR>\"; bld=\"<BINARY_DIR>\"; fi; mkdir -p \"$bld\" && cd \"$bld\" && \"$src/configure\" ${EP_AUTOTOOLS_ARGS_STR} --enable-extra-encodings"
    BUILD_COMMAND ${Make_EXECUTABLE} -j${NPROC}
    INSTALL_COMMAND ${Make_EXECUTABLE} -j${NPROC} install
)
