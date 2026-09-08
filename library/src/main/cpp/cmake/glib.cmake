include(ExternalProject)

ExternalProject_Add(ep_glib
    URL https://download.gnome.org/sources/glib/2.89/glib-2.89.0.tar.xz
    URL_HASH SHA256=205bf5dab175de68f11e33be7bb36d4ad4c5a5097d8c0c88a8682b257b6293dc
    DEPENDS ep_zlib ep_libffi ep_libiconv
    CONFIGURE_COMMAND
        ${CMAKE_COMMAND} -E env "MSYS_NO_PATHCONV=1" "NINJA=${Ninja_EXECUTABLE}" "PKG_CONFIG_PATH=${_cross_pkg}:${_cross_pkg_wsl}" "PKG_CONFIG_LIBDIR=${_cross_pkg}:${_cross_pkg_wsl}"
        ${Meson_EXECUTABLE} setup
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
        <BINARY_DIR> <SOURCE_DIR>
    BUILD_COMMAND ${Meson_EXECUTABLE} compile -j ${NPROC} -C <BINARY_DIR>
    INSTALL_COMMAND ${Meson_EXECUTABLE} install -C <BINARY_DIR>
)
