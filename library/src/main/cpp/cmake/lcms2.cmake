include(ExternalProject)

ExternalProject_Add(ep_lcms2
    URL https://downloads.sourceforge.net/project/lcms/lcms/2.19/lcms2-2.19.tar.gz
    URL_HASH SHA256=49e7e134e4299733dd0eda434fa468997a28ab3d33fa397c642b03644f552216
    BUILD_IN_SOURCE true
    CONFIGURE_COMMAND
        "${BASH_EXECUTABLE}" "${AUTOTOOLS_HELPER_MSYS}" "<SOURCE_DIR>" ./configure ${EP_AUTOTOOLS_ARGS}
    BUILD_COMMAND ${Make_EXECUTABLE} -j${NPROC} all
    INSTALL_COMMAND ${Make_EXECUTABLE} -j${NPROC} install
)
