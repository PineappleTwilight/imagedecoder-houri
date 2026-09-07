include(ExternalProject)

# lcms2 uses autogen.sh (autoreconf). See libffi.cmake for MSYS2 notes.
ExternalProject_Add(ep_lcms2
    GIT_REPOSITORY https://github.com/mm2/Little-CMS
    GIT_TAG lcms2.19.1
    GIT_SHALLOW TRUE
    BUILD_IN_SOURCE true
    CONFIGURE_COMMAND
        "${BASH_EXECUTABLE}" -c
        "set -e; if command -v cygpath >/dev/null 2>&1; then src=$(cygpath -u \"<SOURCE_DIR>\"); else src=\"<SOURCE_DIR>\"; fi; cd \"$src\" && ./autogen.sh ${EP_AUTOTOOLS_ARGS}"
    BUILD_COMMAND ${Make_EXECUTABLE} -j${NPROC} all
    INSTALL_COMMAND ${Make_EXECUTABLE} -j${NPROC} install
)
