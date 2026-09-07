include(ExternalProject)

ExternalProject_Add(ep_libffi
    GIT_REPOSITORY https://github.com/libffi/libffi
    GIT_TAG v3.6.0
    GIT_SHALLOW TRUE
    BUILD_IN_SOURCE true
    CONFIGURE_COMMAND
        "${BASH_EXECUTABLE}" -c
        "set -e; if command -v cygpath >/dev/null 2>&1; then src=$(cygpath -u \"<SOURCE_DIR>\"); else src=\"<SOURCE_DIR>\"; fi; cd \"$src\" && ./autogen.sh && ./configure ${EP_AUTOTOOLS_ARGS_STR} --disable-builddir --disable-multi-os-directory --enable-pax_emutramp"
    BUILD_COMMAND ${Make_EXECUTABLE} -j${NPROC} all
    INSTALL_COMMAND ${Make_EXECUTABLE} install
)
