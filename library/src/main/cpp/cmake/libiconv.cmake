include(ExternalProject)

ExternalProject_Add(ep_libiconv
    URL https://ftp.gnu.org/pub/gnu/libiconv/libiconv-1.17.tar.gz
    BUILD_IN_SOURCE 1
    LOG_CONFIGURE 1
    LOG_BUILD 1
    LOG_INSTALL 1
    CONFIGURE_COMMAND
        "${BASH_EXECUTABLE}" "${AUTOTOOLS_HELPER}" "<SOURCE_DIR>" ./configure ${EP_AUTOTOOLS_ARGS} --enable-extra-encodings
    BUILD_COMMAND ${Make_EXECUTABLE} -j1 V=1
    INSTALL_COMMAND ${Make_EXECUTABLE} -j1 install V=1
)
