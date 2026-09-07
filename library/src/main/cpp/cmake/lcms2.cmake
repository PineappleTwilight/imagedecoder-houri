include(ExternalProject)

ExternalProject_Add(ep_lcms2
    GIT_REPOSITORY https://github.com/mm2/Little-CMS
    GIT_TAG lcms2.19.1
    BUILD_IN_SOURCE true
    CONFIGURE_COMMAND "${AUTOTOOLS_BASH_PREFIX}" <SOURCE_DIR>/autogen.sh ${EP_AUTOTOOLS_ARGS}
    BUILD_COMMAND ${Make_EXECUTABLE} -j${NPROC} all
    INSTALL_COMMAND ${Make_EXECUTABLE} -j${NPROC} install
)
