include(ExternalProject)

ExternalProject_Add(ep_libjpeg-turbo
    GIT_REPOSITORY https://github.com/libjpeg-turbo/libjpeg-turbo
    GIT_TAG 3.2.0
    GIT_SHALLOW TRUE
    CMAKE_ARGS
        ${EP_CMAKE_ARGS}
        -DWITH_JPEG8=1
        -DWITH_TURBOJPEG=0
        -DENABLE_SHARED=0
        -DENABLE_STATIC=1
        -DREQUIRE_SIMD=1
)
