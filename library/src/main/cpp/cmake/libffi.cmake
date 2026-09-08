include(ExternalProject)

ExternalProject_Add(ep_libffi
    URL https://github.com/libffi/libffi/releases/download/v3.6.0/libffi-3.6.0.tar.gz
    URL_HASH SHA256=31ff1fe32deaebfbb388727f32677bb254bf2a41382c51464c0b1837c9ee9828
    BUILD_IN_SOURCE true
    CONFIGURE_COMMAND
        ${CMAKE_COMMAND} -E env "CC=${_cc_msys}" "CFLAGS=--target=${ANDROID_TARGET}${ANDROID_PLATFORM_LEVEL}" "CXX=${_cxx_msys}" "CXXFLAGS=--target=${ANDROID_TARGET}${ANDROID_PLATFORM_LEVEL}" "AR=${_ar_msys}" "LD=${_ld_msys}" "RANLIB=${_ranlib_msys}" "STRIP=${_strip_msys}"
        ${BASH_CMD} "${AUTOTOOLS_HELPER_MSYS}" "<SOURCE_DIR>" ./configure "--host=${ANDROID_TARGET}" "--prefix=${EP_AUTOTOOLS_PREFIX}" --disable-shared --enable-static --with-pic --disable-builddir --disable-multi-os-directory --enable-pax_emutramp
    BUILD_COMMAND
        ${CMAKE_COMMAND} -E env "CC=${_cc_msys}" "CFLAGS=--target=${ANDROID_TARGET}${ANDROID_PLATFORM_LEVEL}" "CXX=${_cxx_msys}" "CXXFLAGS=--target=${ANDROID_TARGET}${ANDROID_PLATFORM_LEVEL}" "AR=${_ar_msys}" "LD=${_ld_msys}" "RANLIB=${_ranlib_msys}" "STRIP=${_strip_msys}"
        ${BASH_CMD} "${AUTOTOOLS_HELPER_MSYS}" "<SOURCE_DIR>" make -j${NPROC} all
    INSTALL_COMMAND
        ${CMAKE_COMMAND} -E env "CC=${_cc_msys}" "CFLAGS=--target=${ANDROID_TARGET}${ANDROID_PLATFORM_LEVEL}" "CXX=${_cxx_msys}" "CXXFLAGS=--target=${ANDROID_TARGET}${ANDROID_PLATFORM_LEVEL}" "AR=${_ar_msys}" "LD=${_ld_msys}" "RANLIB=${_ranlib_msys}" "STRIP=${_strip_msys}"
        ${BASH_CMD} "${AUTOTOOLS_HELPER_MSYS}" "<SOURCE_DIR>" make install
)
