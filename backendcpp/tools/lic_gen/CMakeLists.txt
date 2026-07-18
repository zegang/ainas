cmake_minimum_required(VERSION 3.20)

# On iOS cross-builds the host macOS has OpenSSL but the iOS toolchain
# cannot compile its headers — skip it.
if(CMAKE_SYSTEM_NAME STREQUAL "iOS")
    set(LIC_CRYPTO_SRC ../../src/lic/crypto_stub.cpp)
    message(STATUS "lic_gen: iOS cross-build — using crypto stubs")
else()
    find_package(OpenSSL QUIET)
    if(OpenSSL_FOUND)
        set(LIC_CRYPTO_SRC ../../src/lic/crypto.cpp)
        add_definitions(-DAINAS_HAVE_OPENSSL)
    else()
        set(LIC_CRYPTO_SRC ../../src/lic/crypto_stub.cpp)
        message(STATUS "lic_gen: OpenSSL not found — using crypto stubs")
    endif()
endif()

# Generate the public-key header (same logic as src/CMakeLists.txt) so
# the tool can also call importLicense / isLicenseValid if desired.
set(LIC_PUBLIC_KEY_CONTENTS "placeholder")
if(DEFINED LIC_PUBLIC_KEY_PATH AND EXISTS "${LIC_PUBLIC_KEY_PATH}")
    file(READ "${LIC_PUBLIC_KEY_PATH}" LIC_PUBLIC_KEY_CONTENTS_RAW)
    string(REPLACE "\\" "\\\\" LIC_PUBLIC_KEY_CONTENTS "${LIC_PUBLIC_KEY_CONTENTS_RAW}")
    string(REPLACE "\"" "\\\"" LIC_PUBLIC_KEY_CONTENTS "${LIC_PUBLIC_KEY_CONTENTS}")
    message(STATUS "lic_gen: embedding public key from ${LIC_PUBLIC_KEY_PATH}")
else()
    message(STATUS "lic_gen: no LIC_PUBLIC_KEY_PATH — using placeholder")
endif()

set(LIC_PUBLIC_KEY_GEN_DIR "${CMAKE_CURRENT_BINARY_DIR}/generated")
file(MAKE_DIRECTORY "${LIC_PUBLIC_KEY_GEN_DIR}")
file(WRITE "${LIC_PUBLIC_KEY_GEN_DIR}/lic_public_key.h"
"#pragma once\n\n"
"static constexpr const char* kLicPublicKey =\n"
"    \"${LIC_PUBLIC_KEY_CONTENTS}\";\n"
)

# Lic source files from the backend library
set(LIC_SOURCES
    ${CMAKE_CURRENT_SOURCE_DIR}/${LIC_CRYPTO_SRC}
    ${CMAKE_CURRENT_SOURCE_DIR}/../../src/lic/fingerprint.cpp
    ${CMAKE_CURRENT_SOURCE_DIR}/../../src/lic/license.cpp
)

# Stub hardware info (tool doesn't need real hardware detection)
set(LIC_STUB_SOURCE
    ${CMAKE_CURRENT_SOURCE_DIR}/hardware_stub.cpp
)

add_executable(lic_gen
    main.cpp
    ${LIC_STUB_SOURCE}
    ${LIC_SOURCES}
)

target_include_directories(lic_gen PRIVATE
    ${CMAKE_CURRENT_SOURCE_DIR}/../../include
    ${CMAKE_CURRENT_SOURCE_DIR}/../../src
    ${LIC_PUBLIC_KEY_GEN_DIR}
)

if(OpenSSL_FOUND)
    target_link_libraries(lic_gen PRIVATE
        OpenSSL::SSL
        OpenSSL::Crypto
    )
endif()
