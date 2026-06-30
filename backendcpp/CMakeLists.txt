cmake_minimum_required(VERSION 3.20)
project(ainas-backend-cpp VERSION 0.1.0 LANGUAGES CXX C)

set(CMAKE_CXX_STANDARD 20)
set(CMAKE_CXX_STANDARD_REQUIRED ON)
set(CMAKE_CXX_EXTENSIONS OFF)

find_package(Threads REQUIRED)

get_filename_component(OATPP_DIR ${CMAKE_CURRENT_SOURCE_DIR}/../vendor/oatpp ABSOLUTE)
add_subdirectory(${OATPP_DIR} ${CMAKE_BINARY_DIR}/oatpp)

add_subdirectory(src)
