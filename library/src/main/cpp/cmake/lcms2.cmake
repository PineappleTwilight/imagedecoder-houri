include(ExternalProject)

ExternalProject_Add(ep_lcms2
    GIT_REPOSITORY https://github.com/mm2/Little-CMS
    GIT_TAG lcms2.19.1
    GIT_SHALLOW TRUE
    BUILD_IN_SOURCE true
    CONFIGURE_COMMAND
        "${BASH_EXECUTABLE}" -c
        "src='<SOURCE_DIR>' && command -v cygpath >/dev/null 2>&1 && src=$(cygpath -u $src) || true && cd $src && ./autogen.sh ${EP_AUTOTOOLS_ARGS_STR}"
    BUILD_COMMAND ${Make_EXECUTABLE} -j${NPROC} all
    INSTALL_COMMAND ${Make_EXECUTABLE} -j${NPROC} install
)
