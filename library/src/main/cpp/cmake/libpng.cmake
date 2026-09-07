include(ExternalProject)

ExternalProject_Add(ep_libpng
    URL https://github.com/glennrp/libpng/archive/d1d0abeffede1cc898ddc3d0e600839cf026d749.tar.gz
    URL_HASH SHA256=ea59a944375f93e8565b4642d6dac2f194c1306e2407409b4d0951ce610c822a
    DEPENDS ep_zlib
    CMAKE_ARGS
        ${EP_CMAKE_ARGS}
        -DZLIB_ROOT:STRING=${THIRD_PARTY_LIB_PATH}
        -DPNG_SHARED=OFF
        -DPNG_TESTS=OFF
        -DPNG_TOOLS=OFF
        "-DCMAKE_BUILD_TYPE=Release"
)
