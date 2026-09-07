include(ExternalProject)

ExternalProject_Add(ep_libffi
    URL https://github.com/libffi/libffi/releases/download/v3.6.0/libffi-3.6.0.tar.gz
    URL_HASH SHA256=31ff1fe32deaebfbb388727f32677bb254bf2a41382c51464c0b1837c9ee9828
    BUILD_IN_SOURCE true
    CONFIGURE_COMMAND
        "${BASH_EXECUTABLE}" "${AUTOTOOLS_HELPER_MSYS}" "<SOURCE_DIR>" ./configure ${EP_AUTOTOOLS_ARGS} --disable-builddir --disable-multi-os-directory --enable-pax_emutramp
    BUILD_COMMAND ${Make_EXECUTABLE} -j${NPROC} all
    INSTALL_COMMAND ${Make_EXECUTABLE} install
)
