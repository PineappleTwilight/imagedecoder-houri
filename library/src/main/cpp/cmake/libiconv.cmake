include(ExternalProject)

# Use bash -c with cygpath so C:/... (Windows) is seen as /c/... inside MSYS bash.
# On Linux, cygpath doesn't exist and the path is already Unix, so fallback is used.
# EP_AUTOTOOLS_ARGS_STR is space-separated (not ; separated) for inside the string.
# NOTE: No semicolons or double-quotes inside the bash -c string — both break the
# generated ExternalProject stamp file (semicolon splits the CMake list, double-quote
# breaks the outer set(command "...") quoting). Use single quotes + unquoted $src
# and &&/|| instead of ; and if/fi.
ExternalProject_Add(ep_libiconv
    URL https://ftp.gnu.org/pub/gnu/libiconv/libiconv-1.17.tar.gz
    BUILD_IN_SOURCE 1
    LOG_CONFIGURE 1
    LOG_BUILD 1
    LOG_INSTALL 1
    CONFIGURE_COMMAND
        "${BASH_EXECUTABLE}" -c
        "src='<SOURCE_DIR>' && command -v cygpath >/dev/null 2>&1 && src=$(cygpath -u $src) || true && cd $src && ./configure ${EP_AUTOTOOLS_ARGS_STR} --enable-extra-encodings"
    BUILD_COMMAND ${Make_EXECUTABLE} -j1 V=1
    INSTALL_COMMAND ${Make_EXECUTABLE} -j1 install V=1
)
