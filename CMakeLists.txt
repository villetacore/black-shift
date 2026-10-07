cmake_minimum_required(VERSION 3.24)
project(BlackShift VERSION 0.3.0 LANGUAGES CXX)

set(CMAKE_CXX_STANDARD 17)
set(CMAKE_CXX_STANDARD_REQUIRED ON)
# Executables land directly in the build directory (e.g. build/client/Release/blackshift.exe).
set(CMAKE_RUNTIME_OUTPUT_DIRECTORY "${CMAKE_BINARY_DIR}")

option(BLACKSHIFT_CLIENT_TESTS "Build the native Qt/network integration test" OFF)
if(BLACKSHIFT_CLIENT_TESTS)
  enable_testing()
endif()

add_subdirectory(client/core)
add_subdirectory(client/app)
