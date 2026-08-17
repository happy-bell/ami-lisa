cmake_minimum_required(VERSION 3.22)
project(ami_usb_audio LANGUAGES C CXX)

set(CMAKE_CXX_STANDARD 17)
set(CMAKE_CXX_STANDARD_REQUIRED ON)

# ---- libusb (static) ----
set(LIBUSB_BUILD_SHARED_LIBS OFF CACHE BOOL "" FORCE)
set(LIBUSB_BUILD_TESTING OFF CACHE BOOL "" FORCE)
set(LIBUSB_BUILD_EXAMPLES OFF CACHE BOOL "" FORCE)
set(LIBUSB_INSTALL_TARGETS OFF CACHE BOOL "" FORCE)
add_subdirectory(third_party/libusb-cmake EXCLUDE_FROM_ALL)

# ---- libuac (compile sources directly; upstream CMake drags in tests/samples) ----
set(LIBUAC_DIR ${CMAKE_CURRENT_SOURCE_DIR}/third_party/libuac)
set(UAC_GEN_DIR ${CMAKE_CURRENT_BINARY_DIR}/uac_gen)
file(MAKE_DIRECTORY ${UAC_GEN_DIR})
# THROW_ON_ERROR: libuac reports fatal errors as C++ exceptions we catch in JNI
file(WRITE ${UAC_GEN_DIR}/config.h "#define THROW_ON_ERROR\n")

add_library(uac STATIC
    ${LIBUAC_DIR}/src/uac_context.cpp
    ${LIBUAC_DIR}/src/uac_device.cpp
    ${LIBUAC_DIR}/src/uac_parser.cpp
    ${LIBUAC_DIR}/src/uac_streaming.cpp
    ${LIBUAC_DIR}/src/uac_exceptions.cpp
)
target_include_directories(uac
    PUBLIC ${LIBUAC_DIR}/include
    PRIVATE ${LIBUAC_DIR}/src ${UAC_GEN_DIR}
)
target_link_libraries(uac PUBLIC libusb::usb-1.0)
target_compile_options(uac PRIVATE -fexceptions -fno-rtti)

# ---- JNI bridge ----
add_library(ami_usb_audio SHARED usb_audio_jni.cpp)
target_compile_options(ami_usb_audio PRIVATE -fexceptions)
target_link_libraries(ami_usb_audio PRIVATE uac log android)
