# CMakeLists.txt example for a C++ project
cmake_minimum_required(VERSION 3.20 FATAL_ERROR)
project(MyProject VERSION 1.2.3 LANGUAGES CXX)

# Set C++ standard
set(CMAKE_CXX_STANDARD 17)
set(CMAKE_CXX_STANDARD_REQUIRED ON)
set(CMAKE_CXX_EXTENSIONS OFF)

# Build type
if(NOT CMAKE_BUILD_TYPE)
    set(CMAKE_BUILD_TYPE Release CACHE STRING "Build type" FORCE)
endif()

# Options
option(BUILD_TESTS "Build test suite" ON)
option(BUILD_DOCS "Build documentation" OFF)
option(ENABLE_COVERAGE "Enable code coverage" OFF)

# Find dependencies
find_package(Boost 1.75 REQUIRED COMPONENTS filesystem system)
find_package(Threads REQUIRED)
find_package(OpenSSL REQUIRED)
find_package(fmt CONFIG QUIET)

if(NOT fmt_FOUND)
    message(STATUS "fmt not found, fetching from GitHub...")
    include(FetchContent)
    FetchContent_Declare(
        fmt
        GIT_REPOSITORY https://github.com/fmtlib/fmt.git
        GIT_TAG 10.1.1
    )
    FetchContent_MakeAvailable(fmt)
endif()

# Compile definitions
add_compile_definitions(
    $<$<CONFIG:Debug>:DEBUG_MODE>
    $<$<CONFIG:Release>:NDEBUG>
    PROJECT_VERSION="${PROJECT_VERSION}"
)

# Compiler warnings
add_compile_options(
    -Wall -Wextra -Wpedantic
    $<$<CONFIG:Debug>:-g -O0>
    $<$<CONFIG:Release>:-O3>
)

# Source files
file(GLOB_RECURSE SOURCES "src/*.cpp")
file(GLOB_RECURSE HEADERS "include/*.hpp")

# Main library
add_library(mylib STATIC ${SOURCES})

target_include_directories(mylib
    PUBLIC
        $<BUILD_INTERFACE:${CMAKE_CURRENT_SOURCE_DIR}/include>
        $<INSTALL_INTERFACE:include>
    PRIVATE
        ${CMAKE_CURRENT_SOURCE_DIR}/src
)

target_link_libraries(mylib
    PUBLIC
        Boost::filesystem
        Boost::system
        OpenSSL::SSL
    PRIVATE
        Threads::Threads
        fmt::fmt
)

# Main executable
add_executable(myapp src/main.cpp)
target_link_libraries(myapp PRIVATE mylib)

# Tests
if(BUILD_TESTS)
    enable_testing()
    find_package(GTest REQUIRED)

    add_executable(tests
        tests/test_main.cpp
        tests/test_core.cpp
        tests/test_utils.cpp
    )

    target_link_libraries(tests
        PRIVATE mylib GTest::gtest GTest::gtest_main
    )

    add_test(NAME unit_tests COMMAND tests)

    # Coverage
    if(ENABLE_COVERAGE)
        target_compile_options(tests PRIVATE --coverage)
        target_link_options(tests PRIVATE --coverage)
    endif()
endif()

# Installation
install(TARGETS mylib myapp
    RUNTIME DESTINATION bin
    LIBRARY DESTINATION lib
    ARCHIVE DESTINATION lib
)

install(DIRECTORY include/ DESTINATION include)

# Custom commands
add_custom_command(
    OUTPUT ${CMAKE_BINARY_DIR}/version.h
    COMMAND ${CMAKE_COMMAND} -E echo
        "\#define VERSION \"${PROJECT_VERSION}\"" > version.h
    WORKING_DIRECTORY ${CMAKE_BINARY_DIR}
    COMMENT "Generating version header"
)

add_custom_target(version_header DEPENDS ${CMAKE_BINARY_DIR}/version.h)

# Print configuration summary
message(STATUS "")
message(STATUS "Configuration:")
message(STATUS "  Build type:    ${CMAKE_BUILD_TYPE}")
message(STATUS "  C++ standard:  ${CMAKE_CXX_STANDARD}")
message(STATUS "  Build tests:   ${BUILD_TESTS}")
message(STATUS "  Build docs:    ${BUILD_DOCS}")
message(STATUS "  Coverage:      ${ENABLE_COVERAGE}")
message(STATUS "")
