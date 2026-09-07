include(ExternalProject)

ExternalProject_Add(ep_libiconv
    URL https://ftp.gnu.org/pub/gnu/libiconv/libiconv-1.17.tar.gz
    BUILD_IN_SOURCE 1
    LOG_CONFIGURE 1
    LOG_BUILD 1
    LOG_INSTALL 1
    CONFIGURE_COMMAND
        ${CMAKE_COMMAND} -E env "CC=${_cc_msys}" "CFLAGS=--target=${ANDROID_TARGET}${ANDROID_PLATFORM_LEVEL}" "CXX=${_cxx_msys}" "CXXFLAGS=--target=${ANDROID_TARGET}${ANDROID_PLATFORM_LEVEL}" "AR=${_ar_msys}" "LD=${_ld_msys}" "RANLIB=${_ranlib_msys}" "STRIP=${_strip_msys}" "gl_cv_func_nl_langinfo_codeset=no" "am_cv_langinfo_codeset=no"
        "${BASH_EXECUTABLE}" "${AUTOTOOLS_HELPER_MSYS}" "<SOURCE_DIR>" bash -c "./configure \"--host=${ANDROID_TARGET}\" \"--prefix=${EP_AUTOTOOLS_PREFIX}\" --disable-shared --enable-static --with-pic --enable-extra-encodings && sed -i -e '/^#define gid_t/d' -e '/^#define uid_t/d' -e '/^#define HAVE_LANGINFO_CODESET/d' config.h && sed -i -e '/^#define HAVE_LANGINFO_CODESET/d' libcharset/config.h 2>/dev/null || true" 
    BUILD_COMMAND
        ${CMAKE_COMMAND} -E env "CC=${_cc_msys}" "CFLAGS=--target=${ANDROID_TARGET}${ANDROID_PLATFORM_LEVEL}" "CXX=${_cxx_msys}" "CXXFLAGS=--target=${ANDROID_TARGET}${ANDROID_PLATFORM_LEVEL}" "AR=${_ar_msys}" "LD=${_ld_msys}" "RANLIB=${_ranlib_msys}" "STRIP=${_strip_msys}"
        "${BASH_EXECUTABLE}" "${AUTOTOOLS_HELPER_MSYS}" "<SOURCE_DIR>" make -j1 V=1
    INSTALL_COMMAND
        ${CMAKE_COMMAND} -E env "CC=${_cc_msys}" "CFLAGS=--target=${ANDROID_TARGET}${ANDROID_PLATFORM_LEVEL}" "CXX=${_cxx_msys}" "CXXFLAGS=--target=${ANDROID_TARGET}${ANDROID_PLATFORM_LEVEL}" "AR=${_ar_msys}" "LD=${_ld_msys}" "RANLIB=${_ranlib_msys}" "STRIP=${_strip_msys}"
        "${BASH_EXECUTABLE}" "${AUTOTOOLS_HELPER_MSYS}" "<SOURCE_DIR>" make -j1 install V=1
)
