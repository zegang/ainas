cmake_minimum_required(VERSION 3.20)

find_package(OpenSSL REQUIRED)

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
    ${CMAKE_CURRENT_SOURCE_DIR}/../../src/lic/crypto.cpp
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

target_link_libraries(lic_gen PRIVATE
    OpenSSL::SSL
    OpenSSL::Crypto
)
