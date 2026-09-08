include(ExternalProject)

if(IS_HOST_WINDOWS)
  set(_vips_meson_cmd ${BASH_CMD} "${MESON_HELPER_MSYS}")
else()
  set(_vips_meson_cmd ${Meson_EXECUTABLE} $<$<BOOL:${MESON_VIA_WSL}>:${MESON_WSL_CMD}>)
endif()
ExternalProject_Add(ep_libvips
    GIT_REPOSITORY https://github.com/libvips/libvips
    GIT_TAG v8.18.5
    GIT_SHALLOW TRUE
    PATCH_COMMAND git apply ${CMAKE_CURRENT_SOURCE_DIR}/patches/libvips-remove-subdirs.patch || true
    DEPENDS ep_libexpat ep_glib ep_highway ep_lcms2 ep_libpng ep_libjpeg-turbo ep_libopenjp2 ep_libwebp ep_libheif ep_libjxl
    CONFIGURE_COMMAND
        ${CMAKE_COMMAND} -E env "MSYS_NO_PATHCONV=1" "NINJA=${Ninja_EXECUTABLE}"
        ${_vips_meson_cmd} setup
        --reconfigure
        ${EP_MESON_ARGS}
        -Ddeprecated=false
        -Dexamples=false
        -Dcplusplus=true
        -Dmodules=disabled
        -Dintrospection=disabled
        -Dfuzzing_engine=none
        -Djpeg-xl-module=disabled
        <BINARY_DIR> <SOURCE_DIR>
    BUILD_COMMAND ${_vips_meson_cmd} compile -j ${NPROC} -C <BINARY_DIR>
    INSTALL_COMMAND ${_vips_meson_cmd} install -C <BINARY_DIR>
    BUILD_ALWAYS 1
)
