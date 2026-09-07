include(ExternalProject)

# Use bash -c with cygpath so C:/... (Windows) is seen as /c/... inside MSYS bash.
# On Linux, cygpath doesn't exist and the path is already Unix, so fallback is used.
# EP_AUTOTOOLS_ARGS_STR is space-separated (not ; separated) for inside the string.
ExternalProject_Add(ep_libiconv
    URL https://ftp.gnu.org/pub/gnu/libiconv/libiconv-1.17.tar.gz
    BUILD_IN_SOURCE 1
    LOG_CONFIGURE 1
    LOG_BUILD 1
    LOG_INSTALL 1
    CONFIGURE_COMMAND
        "${BASH_EXECUTABLE}" -c
        "set -ex; echo "libiconv: BASH=/bin/bash, src=<SOURCE_DIR>"; if command -v cygpath >/dev/null 2>&1; then src=$(cygpath -u \"<SOURCE_DIR>\"); else src=\"<SOURCE_DIR>\"; fi; cd \"$src\" && ./configure ${EP_AUTOTOOLS_ARGS_STR} --enable-extra-encodings"
    BUILD_COMMAND ${Make_EXECUTABLE} -j1 V=1
    INSTALL_COMMAND ${Make_EXECUTABLE} -j1 install V=1
)
