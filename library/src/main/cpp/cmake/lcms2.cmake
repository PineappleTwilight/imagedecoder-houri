include(ExternalProject)

ExternalProject_Add(ep_lcms2
    URL https://github.com/mm2/Little-CMS/releases/download/lcms2.19/lcms2-2.19.tar.gz
    URL_HASH SHA256=49e7e134e4299733dd0eda434fa468997a28ab3d33fa397c642b03644f552216
    BUILD_IN_SOURCE true
    CONFIGURE_COMMAND
        ${CMAKE_COMMAND} -E env "CC=${_cc_msys}" "CFLAGS=--target=${ANDROID_TARGET}${ANDROID_PLATFORM_LEVEL}" "CXX=${_cxx_msys}" "CXXFLAGS=--target=${ANDROID_TARGET}${ANDROID_PLATFORM_LEVEL}" "AR=${_ar_msys}" "LD=${_ld_msys}" "RANLIB=${_ranlib_msys}" "STRIP=${_strip_msys}"
        ${BASH_CMD} "${AUTOTOOLS_HELPER_MSYS}" "<SOURCE_DIR>" ./configure "--host=${ANDROID_TARGET}" "--prefix=${EP_AUTOTOOLS_PREFIX}" --disable-shared --enable-static --with-pic
    BUILD_COMMAND
        ${CMAKE_COMMAND} -E env "CC=${_cc_msys}" "CFLAGS=--target=${ANDROID_TARGET}${ANDROID_PLATFORM_LEVEL}" "CXX=${_cxx_msys}" "CXXFLAGS=--target=${ANDROID_TARGET}${ANDROID_PLATFORM_LEVEL}" "AR=${_ar_msys}" "LD=${_ld_msys}" "RANLIB=${_ranlib_msys}" "STRIP=${_strip_msys}"
        ${BASH_CMD} "${AUTOTOOLS_HELPER_MSYS}" "<SOURCE_DIR>" make -j${NPROC} all
    INSTALL_COMMAND
        ${CMAKE_COMMAND} -E env "CC=${_cc_msys}" "CFLAGS=--target=${ANDROID_TARGET}${ANDROID_PLATFORM_LEVEL}" "CXX=${_cxx_msys}" "CXXFLAGS=--target=${ANDROID_TARGET}${ANDROID_PLATFORM_LEVEL}" "AR=${_ar_msys}" "LD=${_ld_msys}" "RANLIB=${_ranlib_msys}" "STRIP=${_strip_msys}"
        ${BASH_CMD} "${AUTOTOOLS_HELPER_MSYS}" "<SOURCE_DIR>" make -j${NPROC} install
)
