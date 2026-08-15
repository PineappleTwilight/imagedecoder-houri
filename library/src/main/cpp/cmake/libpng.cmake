include(ExternalProject)

ExternalProject_Add(ep_libpng
    GIT_REPOSITORY https://github.com/pnggroup/libpng
    GIT_TAG d1d0abeffede1cc898ddc3d0e600839cf026d749
    DEPENDS ep_zlib
    CMAKE_ARGS
        ${EP_CMAKE_ARGS}
        -DZLIB_ROOT:STRING=${CMAKE_BINARY_DIR}/fakeroot
        -DPNG_SHARED=OFF
        -DPNG_TESTS=OFF
        -DPNG_TOOLS=OFF
        "-DCMAKE_BUILD_TYPE=Release"
)
