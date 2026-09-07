include(ExternalProject)

ExternalProject_Add(ep_lcms2
    URL https://downloads.sourceforge.net/project/lcms/lcms/2.19/lcms2-2.19.tar.gz
    URL_HASH SHA256=a0d9cc6b6f0f334fa1ced499d42298a4b89dccf6f745a4a5072d1b76929522d1d4
    BUILD_IN_SOURCE true
    CONFIGURE_COMMAND
        "${BASH_EXECUTABLE}" "${AUTOTOOLS_HELPER_MSYS}" "<SOURCE_DIR>" ./configure ${EP_AUTOTOOLS_ARGS}
    BUILD_COMMAND ${Make_EXECUTABLE} -j${NPROC} all
    INSTALL_COMMAND ${Make_EXECUTABLE} -j${NPROC} install
)
