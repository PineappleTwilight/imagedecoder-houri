include(ExternalProject)

ExternalProject_Add(ep_libffi
    URL https://github.com/libffi/libffi/releases/download/v3.6.0/libffi-3.6.0.tar.gz
    URL_HASH SHA256=9cc832d54f2860b490fa8a0a0d26d742084bac394d3c4b9e4b90cb92ada0fce25
    BUILD_IN_SOURCE true
    CONFIGURE_COMMAND
        "${BASH_EXECUTABLE}" "${AUTOTOOLS_HELPER_MSYS}" "<SOURCE_DIR>" ./configure ${EP_AUTOTOOLS_ARGS} --disable-builddir --disable-multi-os-directory --enable-pax_emutramp
    BUILD_COMMAND ${Make_EXECUTABLE} -j${NPROC} all
    INSTALL_COMMAND ${Make_EXECUTABLE} install
)
