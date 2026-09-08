include(ExternalProject)

# libiconv 1.17 — URL_HASH pins the tarball so Gradle/CMake cache invalidates correctly
# when the URL changes; PATCH is idempotent via helper and handles both MSYS (/c/)
# and WSL (/mnt/c/) via cygpath/wslpath fallback. CONFIGURE uses a dedicated helper
# to avoid bash -c quoting that previously broke --host propagation (host was
# detected as x86_64 instead of aarch64 on WSL/MSYS interop).
ExternalProject_Add(ep_libiconv
    URL https://ftp.gnu.org/pub/gnu/libiconv/libiconv-1.17.tar.gz
    URL_HASH SHA256=8f74213b56238c85a50a5329f77e06198771e70dd9a739779f4c02f65d971313
    BUILD_IN_SOURCE 1
    LOG_CONFIGURE 1
    LOG_BUILD 1
    LOG_INSTALL 1
    # Ensure patch re-runs when the helper script changes: ExternalProject's
    # patch stamp is per-binary-dir, but the helper is generated into the
    # binary dir at configure time, so a change in CMakeLists.txt regenerates
    # the helper and the next configure will see a new PATCH_COMMAND string
    # (helper path + hash) and re-run patch. UPDATE_COMMAND "" prevents
    # spurious git-update attempts for URL projects.
    UPDATE_COMMAND ""
    PATCH_COMMAND
        ${BASH_CMD} "${PATCH_ICONV_HELPER_MSYS}" "<SOURCE_DIR>"
    CONFIGURE_COMMAND
        ${CMAKE_COMMAND} -E env "CC=${_cc_msys}" "CFLAGS=--target=${ANDROID_TARGET}${ANDROID_PLATFORM_LEVEL}" "CXX=${_cxx_msys}" "CXXFLAGS=--target=${ANDROID_TARGET}${ANDROID_PLATFORM_LEVEL}" "AR=${_ar_msys}" "LD=${_ld_msys}" "RANLIB=${_ranlib_msys}" "STRIP=${_strip_msys}" "gl_cv_func_nl_langinfo_codeset=no" "am_cv_langinfo_codeset=no"
        ${BASH_CMD} "${CONFIGURE_ICONV_HELPER_MSYS}" "<SOURCE_DIR>" "${EP_AUTOTOOLS_PREFIX}" "${ANDROID_TARGET}"
    BUILD_COMMAND
        ${CMAKE_COMMAND} -E env "CC=${_cc_msys}" "CFLAGS=--target=${ANDROID_TARGET}${ANDROID_PLATFORM_LEVEL}" "CXX=${_cxx_msys}" "CXXFLAGS=--target=${ANDROID_TARGET}${ANDROID_PLATFORM_LEVEL}" "AR=${_ar_msys}" "LD=${_ld_msys}" "RANLIB=${_ranlib_msys}" "STRIP=${_strip_msys}"
        ${BASH_CMD} "${AUTOTOOLS_HELPER_MSYS}" "<SOURCE_DIR>" make -j1 V=1
    INSTALL_COMMAND
        ${BASH_CMD} "${INSTALL_ICONV_HELPER_MSYS}" "<SOURCE_DIR>" "${EP_AUTOTOOLS_PREFIX}"
)
