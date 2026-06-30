# ── Platform-specific mDNS source file ─────────────────────────────
if(CMAKE_SYSTEM_NAME STREQUAL "Linux")
    find_package(PkgConfig QUIET)
    if(PkgConfig_FOUND)
        pkg_check_modules(AVAHI avahi-client)
    endif()
    if(AVAHI_FOUND)
        set(MDNS_SOURCE mdns/MdnsService_linux.cpp)
        set(MDNS_AVAILABLE TRUE)
        message(STATUS "mDNS: Using Avahi (Linux)")
    else()
        set(MDNS_SOURCE mdns/MdnsService_stub.cpp)
        set(MDNS_AVAILABLE FALSE)
        message(WARNING "avahi-client not found — mDNS disabled on Linux")
    endif()
elseif(CMAKE_SYSTEM_NAME STREQUAL "Darwin")
    set(MDNS_SOURCE mdns/MdnsService_macos.cpp)
    set(MDNS_AVAILABLE TRUE)
    message(STATUS "mDNS: Using Bonjour (macOS)")
else()
    set(MDNS_SOURCE mdns/MdnsService_stub.cpp)
    set(MDNS_AVAILABLE FALSE)
    message(STATUS "mDNS: Not available on ${CMAKE_SYSTEM_NAME}")
endif()

find_package(PkgConfig QUIET)
if(PkgConfig_FOUND)
    pkg_check_modules(SQLITE3 sqlite3)
endif()
if(NOT SQLITE3_FOUND)
    find_path(SQLITE3_INCLUDE_DIRS sqlite3.h)
    find_library(SQLITE3_LIBRARIES sqlite3)
    if(SQLITE3_INCLUDE_DIRS AND SQLITE3_LIBRARIES)
        set(SQLITE3_FOUND TRUE)
    endif()
endif()
if(NOT SQLITE3_FOUND)
    # If the user passed a .c file as SQLITE3_LIBRARIES (Windows CI fallback),
    # compile it into a static library
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
        message(FATAL_ERROR "sqlite3 development library not found")
    endif()
endif()

add_executable(ainas-backend-cpp
    main.cpp
    config/Config.cpp
    util/cflag.cpp
    logging/Logger.cpp
    service/FileService.cpp
    service/ThumbnailService.cpp
    controller/AiController.cpp
    controller/ConfigController.cpp
    database/Database.cpp
    database/FileRepository.cpp
    database/ConfigRepository.cpp
    ${MDNS_SOURCE}
)

target_link_libraries(ainas-backend-cpp PRIVATE
    oatpp
    Threads::Threads
    ${SQLITE3_LIBRARIES}
)

if(AVAHI_FOUND)
    target_link_libraries(ainas-backend-cpp PRIVATE ${AVAHI_LIBRARIES})
    target_include_directories(ainas-backend-cpp PRIVATE ${AVAHI_INCLUDE_DIRS})
endif()

target_include_directories(ainas-backend-cpp PRIVATE
    ${CMAKE_CURRENT_SOURCE_DIR}/../include
    ${CMAKE_CURRENT_SOURCE_DIR}/../vendor/stb
    ${SQLITE3_INCLUDE_DIRS}
)
