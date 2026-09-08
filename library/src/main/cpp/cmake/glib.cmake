include(ExternalProject)

if(IS_HOST_WINDOWS)
  set(_glib_meson_cmd ${BASH_CMD} "${MESON_HELPER_MSYS}")
else()
  set(_glib_meson_cmd ${Meson_EXECUTABLE} $<$<BOOL:${MESON_VIA_WSL}>:${MESON_WSL_CMD}>)
endif()
ExternalProject_Add(ep_glib
    URL https://download.gnome.org/sources/glib/2.89/glib-2.89.0.tar.xz
    URL_HASH SHA256=205bf5dab175de68f11e33be7bb36d4ad4c5a5097d8c0c88a8682b257b6293dc
    DEPENDS ep_zlib ep_libffi ep_libiconv
    CONFIGURE_COMMAND
        ${CMAKE_COMMAND} -E env "MSYS_NO_PATHCONV=1" "NINJA=${Ninja_EXECUTABLE}" "PKG_CONFIG_PATH=${_cross_pkg}:${_cross_pkg_wsl}" "PKG_CONFIG_LIBDIR=${_cross_pkg}:${_cross_pkg_wsl}" "BASH_COMPLETION_COMPLETIONSDIR="
        ${_glib_meson_cmd} setup
        ${EP_MESON_ARGS}
        -Dtests=false
        -Dman-pages=disabled
        -Ddocumentation=false
        -Dinstalled_tests=false
        -Dlibmount=disabled
        -Dselinux=disabled
        -Dxattr=false
        -Ddtrace=disabled
        -Dsystemtap=disabled
        -Dsysprof=disabled
        -Db_lto=false
        <BINARY_DIR> <SOURCE_DIR>
    BUILD_COMMAND ${_glib_meson_cmd} compile -j ${NPROC} -C <BINARY_DIR>
    INSTALL_COMMAND ${_glib_meson_cmd} install -C <BINARY_DIR>
)
