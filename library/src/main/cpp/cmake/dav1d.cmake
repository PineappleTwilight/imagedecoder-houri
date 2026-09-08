include(ExternalProject)

# Meson cross-building to android (host=android is Unix). --prefix must be
# Unix absolute (/mnt/c/...) even on Windows, otherwise meson 1.12 errors
# "prefix value 'C:/...' must be an absolute path" for the host.
# Use CMAKE_COMMAND -E env to set MSYS_NO_PATHCONV=1 so the Unix prefix
# is not converted to C:/... before meson sees it. On Linux this env is
# harmless, so we apply it unconditionally to avoid WIN32 detection issues
# when CMAKE_SYSTEM_NAME=Android.
# On IS_HOST_WINDOWS, use meson_helper.sh via wsl bash to convert C:/ paths to /mnt/c/ via wslpath
if(IS_HOST_WINDOWS)
  set(_dav1d_meson_cmd ${BASH_CMD} "${MESON_HELPER_MSYS}")
else()
  set(_dav1d_meson_cmd ${Meson_EXECUTABLE} $<$<BOOL:${MESON_VIA_WSL}>:${MESON_WSL_CMD}>)
endif()
ExternalProject_Add(ep_dav1d
    GIT_REPOSITORY https://code.videolan.org/videolan/dav1d
    GIT_TAG 1.5.4
    GIT_SHALLOW TRUE
    CONFIGURE_COMMAND ${CMAKE_COMMAND} -E env "MSYS_NO_PATHCONV=1" "NINJA=${Ninja_EXECUTABLE}" ${_dav1d_meson_cmd} setup ${EP_MESON_ARGS} <BINARY_DIR> <SOURCE_DIR>
    BUILD_COMMAND ${_dav1d_meson_cmd} compile -j ${NPROC} -C <BINARY_DIR>
    INSTALL_COMMAND ${_dav1d_meson_cmd} install -C <BINARY_DIR>
)
