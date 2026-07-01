cmake_minimum_required(VERSION 3.20)
project(ainas-backend-cpp VERSION 0.1.0 LANGUAGES CXX C)

set(CMAKE_CXX_STANDARD 20)
set(CMAKE_CXX_STANDARD_REQUIRED ON)
set(CMAKE_CXX_EXTENSIONS OFF)

if(CMAKE_SYSTEM_NAME STREQUAL "Windows")
    # Configurable Windows target version.
    # Override with -DTARGET_WINDOWS_VER=0x0601 to target Windows 7.
    # Default 0x0A00 = Windows 10/11.
    set(TARGET_WINDOWS_VER "0x0A00" CACHE STRING
        "Minimum Windows version to target (e.g. 0x0601=Win7, 0x0A00=Win10/11)")
    add_definitions(-DWINVER=${TARGET_WINDOWS_VER})
    add_definitions(-D_WIN32_WINNT=${TARGET_WINDOWS_VER})
    string(SUBSTRING "${TARGET_WINDOWS_VER}" 2 -1 WIN_VER_HEX)
    set(NTDDI_VERSION "0x${WIN_VER_HEX}0000")
    add_definitions(-DNTDDI_VERSION=${NTDDI_VERSION})
endif()

find_package(Threads REQUIRED)

get_filename_component(OATPP_DIR ${CMAKE_CURRENT_SOURCE_DIR}/../vendor/oatpp ABSOLUTE)
add_subdirectory(${OATPP_DIR} ${CMAKE_BINARY_DIR}/oatpp)

add_subdirectory(src)
