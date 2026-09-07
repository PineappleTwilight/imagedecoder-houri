include(ExternalProject)

# Meson cross-building to android (host=android is Unix). --prefix must be
# Unix absolute (/c/...) even on Windows, otherwise meson 1.12 errors
# "prefix value 'C:/...' must be an absolute path" for the host.
# Use CMAKE_COMMAND -E env to set MSYS_NO_PATHCONV=1 so the Unix prefix
# is not converted to C:/... before meson sees it. On Linux this env is
# harmless, so we apply it unconditionally to avoid WIN32 detection issues
# when CMAKE_SYSTEM_NAME=Android.
ExternalProject_Add(ep_dav1d
    GIT_REPOSITORY https://code.videolan.org/videolan/dav1d
    GIT_TAG 1.5.4
    GIT_SHALLOW TRUE
    CONFIGURE_COMMAND ${CMAKE_COMMAND} -E env "MSYS_NO_PATHCONV=1" "NINJA=${Ninja_EXECUTABLE}" ${Meson_EXECUTABLE} setup ${EP_MESON_ARGS} <BINARY_DIR> <SOURCE_DIR>
    BUILD_COMMAND ${Meson_EXECUTABLE} compile -j ${NPROC} -C <BINARY_DIR>
    INSTALL_COMMAND ${Meson_EXECUTABLE} install -C <BINARY_DIR>
)
