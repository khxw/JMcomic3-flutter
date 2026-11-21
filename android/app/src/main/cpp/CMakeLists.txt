cmake_minimum_required(VERSION 3.22.1)
project(jmcomic3_super_resolution LANGUAGES CXX)

if(NOT ANDROID_ABI STREQUAL "arm64-v8a" AND
   NOT ANDROID_ABI STREQUAL "armeabi-v7a")
    # The release targets ARM only. Desktop emulators still build the Flutter
    # app with Rust, while the optional upscaler reports itself as unavailable.
    return()
endif()

set(CMAKE_CXX_STANDARD 17)
set(CMAKE_CXX_STANDARD_REQUIRED ON)

set(NCNN_ROOT "${CMAKE_CURRENT_SOURCE_DIR}/ncnn")
set(NCNN_LIBRARY
    "${CMAKE_CURRENT_SOURCE_DIR}/../jniLibs/${ANDROID_ABI}/libncnn.so")

add_library(ncnn SHARED IMPORTED)
set_target_properties(ncnn PROPERTIES
    IMPORTED_LOCATION "${NCNN_LIBRARY}"
    INTERFACE_INCLUDE_DIRECTORIES "${NCNN_ROOT}/include")

add_library(jmcomic3_super_resolution SHARED super_resolution_jni.cpp)
target_include_directories(jmcomic3_super_resolution PRIVATE
    "${NCNN_ROOT}/include")
target_link_libraries(jmcomic3_super_resolution
    ncnn
    jnigraphics
    log)
