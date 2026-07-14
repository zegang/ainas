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

# ── Perfetto tracing (Chrome Trace Event format, zero deps) ─────
option(AINAS_ENABLE_TRACING "Enable Perfetto-compatible tracing" OFF)
if(AINAS_ENABLE_TRACING)
    add_definitions(-DAINAS_ENABLE_TRACING=1)
    message(STATUS "Perfetto tracing: ENABLED")
endif()

# ── {fmt} (portable std::format replacement for iOS < 16.3) ─────
include(FetchContent)
FetchContent_Declare(fmt
    GIT_REPOSITORY https://github.com/fmtlib/fmt.git
    GIT_TAG 11.1.4)
FetchContent_MakeAvailable(fmt)

# ── Header-only HTTP client & JSON (for AiController proxy) ──────
FetchContent_Declare(httplib
    GIT_REPOSITORY https://github.com/yhirose/cpp-httplib.git
    GIT_TAG v0.18.2)
FetchContent_MakeAvailable(httplib)
FetchContent_Declare(nlohmann_json
    GIT_REPOSITORY https://github.com/nlohmann/json.git
    GIT_TAG v3.11.3)
FetchContent_MakeAvailable(nlohmann_json)

# ── cllama AI inference binary (separate build tree) ──────────────
include(ExternalProject)
set(CLLAMA_EXTRA_ARGS)
if(DEFINED CMAKE_CXX_FLAGS AND NOT CMAKE_CXX_FLAGS STREQUAL "")
    list(APPEND CLLAMA_EXTRA_ARGS -DCMAKE_CXX_FLAGS=${CMAKE_CXX_FLAGS})
endif()
if(DEFINED ENV{CMAKE_PREFIX_PATH} AND NOT "$ENV{CMAKE_PREFIX_PATH}" STREQUAL "")
    list(APPEND CLLAMA_EXTRA_ARGS -DCMAKE_PREFIX_PATH=$ENV{CMAKE_PREFIX_PATH})
endif()
if(DEFINED ENV{CLLAMA_CMAKE_TOOLCHAIN_FILE} AND NOT "$ENV{CLLAMA_CMAKE_TOOLCHAIN_FILE}" STREQUAL "")
    list(APPEND CLLAMA_EXTRA_ARGS -DCMAKE_TOOLCHAIN_FILE=$ENV{CLLAMA_CMAKE_TOOLCHAIN_FILE})
endif()
if(CLLAMA_IGNORE_CMP0167)
    list(APPEND CLLAMA_EXTRA_ARGS -DCMAKE_POLICY_CMP0167=OLD)
endif()
# Resolve path to the outer vendor/oatpp for reuse across both projects.
get_filename_component(CLLAMA_OATPP_SOURCE_DIR
    ${CMAKE_CURRENT_SOURCE_DIR}/../vendor/oatpp ABSOLUTE)

ExternalProject_Add(cllama
    SOURCE_DIR ${CMAKE_CURRENT_SOURCE_DIR}/../vendor/cllama
    BINARY_DIR ${CMAKE_BINARY_DIR}/cllama
    CMAKE_ARGS
        -DCMAKE_BUILD_TYPE=${CMAKE_BUILD_TYPE}
        -DCMAKE_CXX_COMPILER=${CMAKE_CXX_COMPILER}
        -DCMAKE_C_COMPILER=${CMAKE_C_COMPILER}
        -DCLLAMA_OATPP_SOURCE_DIR=${CLLAMA_OATPP_SOURCE_DIR}
        ${CLLAMA_EXTRA_ARGS}
    INSTALL_COMMAND ""
    BUILD_BYPRODUCTS ${CMAKE_BINARY_DIR}/cllama/bin/cllama
    UPDATE_DISCONNECTED TRUE
)

add_subdirectory(src)
