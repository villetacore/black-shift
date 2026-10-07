# Builds the Rust client core with Cargo and exposes it as the imported target blackshift::core.
find_program(CARGO_EXECUTABLE cargo REQUIRED)

set(RUST_TARGET_DIR "${CMAKE_CURRENT_BINARY_DIR}/target")
if(WIN32)
  set(RUST_LIBRARY "${RUST_TARGET_DIR}/release/blackshift_core.lib")
else()
  set(RUST_LIBRARY "${RUST_TARGET_DIR}/release/libblackshift_core.a")
endif()

file(GLOB_RECURSE RUST_SOURCES CONFIGURE_DEPENDS "${CMAKE_CURRENT_SOURCE_DIR}/src/*.rs")
add_custom_command(
  OUTPUT "${RUST_LIBRARY}"
  COMMAND "${CARGO_EXECUTABLE}" build --release
          --manifest-path "${CMAKE_CURRENT_SOURCE_DIR}/Cargo.toml" --target-dir "${RUST_TARGET_DIR}"
  DEPENDS ${RUST_SOURCES} "${CMAKE_CURRENT_SOURCE_DIR}/Cargo.toml"
  COMMENT "Building Rust client core"
  VERBATIM)
add_custom_target(blackshift_core_build DEPENDS "${RUST_LIBRARY}")

add_library(blackshift_core STATIC IMPORTED GLOBAL)
add_library(blackshift::core ALIAS blackshift_core)
set_target_properties(blackshift_core PROPERTIES
  IMPORTED_LOCATION "${RUST_LIBRARY}"
  INTERFACE_INCLUDE_DIRECTORIES "${CMAKE_CURRENT_SOURCE_DIR}/include")
add_dependencies(blackshift_core blackshift_core_build)

# System libraries required by the Rust standard library.
if(WIN32)
  target_link_libraries(blackshift_core INTERFACE ws2_32 userenv bcrypt ntdll advapi32)
elseif(APPLE)
  target_link_libraries(blackshift_core INTERFACE iconv)
elseif(UNIX)
  target_link_libraries(blackshift_core INTERFACE ${CMAKE_DL_LIBS} pthread m)
endif()
