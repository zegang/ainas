# ── Platform abstraction source file ────────────────────────────────
if(CMAKE_SYSTEM_NAME STREQUAL "Linux")
    if(ANDROID)
        set(PLATFORM_SOURCE platform/Platform_android.cpp)
        message(STATUS "Platform: Android")
    else()
        set(PLATFORM_SOURCE platform/Platform_linux.cpp)
        message(STATUS "Platform: Linux")
    endif()
elseif(CMAKE_SYSTEM_NAME STREQUAL "Darwin")
    if(IOS OR CMAKE_SYSTEM_NAME STREQUAL "iOS")
        set(PLATFORM_SOURCE platform/Platform_ios.cpp)
        message(STATUS "Platform: iOS")
    else()
        set(PLATFORM_SOURCE platform/Platform_macos.cpp)
        message(STATUS "Platform: macOS")
    endif()
elseif(CMAKE_SYSTEM_NAME STREQUAL "Windows")
    set(PLATFORM_SOURCE platform/Platform_windows.cpp)
    message(STATUS "Platform: Windows")
elseif(CMAKE_SYSTEM_NAME STREQUAL "Android")
    set(PLATFORM_SOURCE platform/Platform_android.cpp)
    message(STATUS "Platform: Android")
elseif(CMAKE_SYSTEM_NAME STREQUAL "iOS")
    set(PLATFORM_SOURCE platform/Platform_ios.cpp)
    message(STATUS "Platform: iOS")
else()
    set(PLATFORM_SOURCE platform/Platform_linux.cpp)
    message(STATUS "Platform: ${CMAKE_SYSTEM_NAME} (fallback to Linux)")
endif()

# ── Platform-specific mDNS source file ─────────────────────────────
if(CMAKE_SYSTEM_NAME STREQUAL "Linux")
    find_package(PkgConfig QUIET)
    if(PkgConfig_FOUND)
        pkg_check_modules(AVAHI_CLIENT avahi-client)
    endif()
    if(AVAHI_CLIENT_FOUND)
        set(MDNS_SOURCE mdns/MdnsService_avahi.cpp)
        set(MDNS_AVAILABLE TRUE)
        message(STATUS "mDNS: Using native Avahi (Linux)")
    else()
        find_path(DNS_SD_INCLUDE_DIRS dns_sd.h)
        find_library(DNS_SD_LIBRARIES dns_sd)
        if(DNS_SD_INCLUDE_DIRS AND DNS_SD_LIBRARIES)
            set(MDNS_SOURCE mdns/MdnsService_bonjour.cpp)
            set(MDNS_AVAILABLE TRUE)
            message(STATUS "mDNS: Using Bonjour (Linux via libdns_sd)")
        else()
            set(MDNS_SOURCE mdns/MdnsService_stub.cpp)
            set(MDNS_AVAILABLE FALSE)
            message(WARNING "mDNS not available — install libavahi-client-dev or libavahi-compat-libdnssd-dev")
        endif()
    endif()
elseif(CMAKE_SYSTEM_NAME STREQUAL "Darwin")
    set(MDNS_SOURCE mdns/MdnsService_bonjour.cpp)
    set(MDNS_AVAILABLE TRUE)
    message(STATUS "mDNS: Using Bonjour (macOS)")
elseif(CMAKE_SYSTEM_NAME STREQUAL "Windows")
    set(MDNS_SOURCE mdns/MdnsService_bonjour.cpp)
    set(MDNS_AVAILABLE TRUE)
    message(STATUS "mDNS: Using Bonjour (Windows)")
else()
    set(MDNS_SOURCE mdns/MdnsService_stub.cpp)
    set(MDNS_AVAILABLE FALSE)
    message(STATUS "mDNS: Not available on ${CMAKE_SYSTEM_NAME}")
endif()

# ── System libraries ───────────────────────────────────────────────
find_package(PkgConfig QUIET)
if(PkgConfig_FOUND)
    pkg_check_modules(SQLITE3 sqlite3)
    pkg_check_modules(POPPLER poppler-cpp)
    pkg_check_modules(QPDF libqpdf)
endif()

# Warn if Poppler is missing (pdf-to-images won't work)
if(NOT POPPLER_FOUND)
    find_path(POPPLER_INCLUDE_DIRS poppler/cpp/poppler-document.h)
    find_library(POPPLER_LIBRARIES poppler-cpp)
    if(POPPLER_INCLUDE_DIRS AND POPPLER_LIBRARIES)
        set(POPPLER_FOUND TRUE)
    endif()
endif()
if(NOT POPPLER_FOUND)
    message(WARNING "libpoppler-cpp not found — install libpoppler-cpp-dev (Debian/Ubuntu) or poppler (brew/macports)")
endif()

# Warn if QPDF is missing (merge-to-pdf won't work)
if(NOT QPDF_FOUND)
    find_path(QPDF_INCLUDE_DIRS qpdf/QPDF.hh)
    find_library(QPDF_LIBRARIES qpdf)
    if(QPDF_INCLUDE_DIRS AND QPDF_LIBRARIES)
        set(QPDF_FOUND TRUE)
    endif()
endif()
if(NOT QPDF_FOUND)
    message(WARNING "libqpdf not found — install libqpdf-dev (Debian/Ubuntu) or qpdf (brew/macports)")
endif()
if(NOT SQLITE3_FOUND)
    # If the user passed a .c file as SQLITE3_LIBRARIES (Windows CI fallback),
    # compile it into a static library. Must check BEFORE find_library below,
    # because find_library treats an already-set cache variable as valid and
    # would pass the .c path directly to MSVC -> LNK1136.
    if(DEFINED SQLITE3_LIBRARIES AND SQLITE3_LIBRARIES MATCHES "\\.c$")
        get_filename_component(SQLITE3_C_FILE "${SQLITE3_LIBRARIES}" ABSOLUTE)
        get_filename_component(SQLITE3_DIR "${SQLITE3_C_FILE}" DIRECTORY)
        if(NOT SQLITE3_INCLUDE_DIRS)
            set(SQLITE3_INCLUDE_DIRS "${SQLITE3_DIR}")
        endif()
        add_library(sqlite3_amalg STATIC "${SQLITE3_C_FILE}")
        target_include_directories(sqlite3_amalg PUBLIC "${SQLITE3_INCLUDE_DIRS}")
        set(SQLITE3_FOUND TRUE)
        set(SQLITE3_LIBRARIES sqlite3_amalg)
        message(STATUS "SQLite3: building amalgamation source as static library")
    else()
        find_path(SQLITE3_INCLUDE_DIRS sqlite3.h)
        find_library(SQLITE3_LIBRARIES sqlite3)
        if(SQLITE3_INCLUDE_DIRS AND SQLITE3_LIBRARIES)
            set(SQLITE3_FOUND TRUE)
        endif()
        if(NOT SQLITE3_FOUND)
            message(FATAL_ERROR "sqlite3 development library not found")
        endif()
    endif()
endif()

add_executable(ainas-backend-cpp
    main.cpp
    config/Config.cpp
    util/cflag.cpp
    logging/Logger.cpp
    service/FileService.cpp
    service/ThumbnailService.cpp
    service/PdfService.cpp
    service/AiService.cpp
    controller/AiController.cpp
    controller/ConfigController.cpp
    controller/UserController.cpp
    database/Database.cpp
    database/FileRepository.cpp
    database/ConfigRepository.cpp
    database/UserRepository.cpp
    database/SyncConfigRepository.cpp
    database/SyncFileManifestRepository.cpp
    service/SyncService.cpp
    controller/SyncController.cpp
    ${MDNS_SOURCE}
    ${PLATFORM_SOURCE}
)

target_link_libraries(ainas-backend-cpp PRIVATE
    oatpp
    Threads::Threads
    ${SQLITE3_LIBRARIES}
    httplib::httplib
    nlohmann_json::nlohmann_json
)

if(POPPLER_FOUND)
    target_link_libraries(ainas-backend-cpp PRIVATE ${POPPLER_LIBRARIES})
endif()
if(QPDF_FOUND)
    target_link_libraries(ainas-backend-cpp PRIVATE ${QPDF_LIBRARIES})
endif()

add_dependencies(ainas-backend-cpp cllama)

# Copy cllama binary and runner into bin/ subdirectory alongside the backend binary.
# The backend resolves cllama as "<self-dir>/bin/cllama" by default.
# Uses a helper script so build won't fail when cllama binaries don't exist yet.
set(_CL_COPY_SCRIPT "${CMAKE_CURRENT_SOURCE_DIR}/../cmake/copy_if_exists.cmake")
set(_CL_SUFFIX "$<IF:$<PLATFORM_ID:Windows>,.exe,>")
add_custom_command(TARGET ainas-backend-cpp POST_BUILD
    COMMAND ${CMAKE_COMMAND} -E make_directory "$<TARGET_FILE_DIR:ainas-backend-cpp>/bin"
    COMMAND ${CMAKE_COMMAND} -E env
        "SRC=${CMAKE_BINARY_DIR}/cllama/bin/cllama${_CL_SUFFIX}"
        "DST=$<TARGET_FILE_DIR:ainas-backend-cpp>/bin/"
        ${CMAKE_COMMAND} -P "${_CL_COPY_SCRIPT}"
    COMMAND ${CMAKE_COMMAND} -E env
        "SRC=${CMAKE_BINARY_DIR}/cllama/bin/cllama_runner${_CL_SUFFIX}"
        "DST=$<TARGET_FILE_DIR:ainas-backend-cpp>/bin/"
        ${CMAKE_COMMAND} -P "${_CL_COPY_SCRIPT}"
    COMMENT "Copying cllama and cllama_runner to output bin/"
)

if(AVAHI_CLIENT_FOUND)
    target_link_libraries(ainas-backend-cpp PRIVATE ${AVAHI_CLIENT_LIBRARIES})
    target_include_directories(ainas-backend-cpp PRIVATE ${AVAHI_CLIENT_INCLUDE_DIRS})
endif()
if(DNS_SD_LIBRARIES)
    target_link_libraries(ainas-backend-cpp PRIVATE ${DNS_SD_LIBRARIES})
    target_include_directories(ainas-backend-cpp PRIVATE ${DNS_SD_INCLUDE_DIRS})
endif()

if(CMAKE_SYSTEM_NAME STREQUAL "Windows")
    target_link_libraries(ainas-backend-cpp PRIVATE ws2_32)
endif()

target_include_directories(ainas-backend-cpp PRIVATE
    ${CMAKE_CURRENT_SOURCE_DIR}/../include
    ${CMAKE_CURRENT_SOURCE_DIR}/../vendor/stb
    ${SQLITE3_INCLUDE_DIRS}
)

if(POPPLER_FOUND)
    target_include_directories(ainas-backend-cpp PRIVATE ${POPPLER_INCLUDE_DIRS})
endif()
if(QPDF_FOUND)
    target_include_directories(ainas-backend-cpp PRIVATE ${QPDF_INCLUDE_DIRS})
endif()
