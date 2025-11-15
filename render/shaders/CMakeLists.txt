# CMakeLists.txt for AseVoxel Native Shaders
# Builds dynamic libraries (.so/.dylib/.dll) for shader modules

cmake_minimum_required(VERSION 3.12)
project(AseVoxelShaders VERSION 1.0.0 LANGUAGES CXX)

# C++17 required for modern C++ features
set(CMAKE_CXX_STANDARD 17)
set(CMAKE_CXX_STANDARD_REQUIRED ON)
set(CMAKE_CXX_EXTENSIONS OFF)

# Platform-specific settings
if(WIN32)
  set(SHADER_EXTENSION ".dll")
  set(CMAKE_WINDOWS_EXPORT_ALL_SYMBOLS ON)
elseif(APPLE)
  set(SHADER_EXTENSION ".dylib")
  set(CMAKE_MACOSX_RPATH ON)
else()
  set(SHADER_EXTENSION ".so")
endif()

# Output directory for compiled shaders
set(CMAKE_LIBRARY_OUTPUT_DIRECTORY "${CMAKE_BINARY_DIR}/shaders")
set(CMAKE_RUNTIME_OUTPUT_DIRECTORY "${CMAKE_BINARY_DIR}/shaders")

# ============================================================================
# Basic Lighting Shader
# ============================================================================
add_library(asev_shader_basic_lighting SHARED
  basic_lighting_shader.cpp
)

target_include_directories(asev_shader_basic_lighting PRIVATE
  ${CMAKE_CURRENT_SOURCE_DIR}/..  # For asev_shader_api.h
)

set_target_properties(asev_shader_basic_lighting PROPERTIES
  PREFIX "lib"
  SUFFIX "${SHADER_EXTENSION}"
  OUTPUT_NAME "asev_shader_basic_lighting"
)

# Ensure C ABI export (no name mangling)
target_compile_definitions(asev_shader_basic_lighting PRIVATE
  -DASEV_SHADER_EXPORTS
)

# ============================================================================
# Native Shader Loader
# ============================================================================
add_library(asev_shader_loader SHARED
  native_shader_loader.cpp
)

target_include_directories(asev_shader_loader PRIVATE
  ${CMAKE_CURRENT_SOURCE_DIR}/..  # For asev_shader_api.h
)

set_target_properties(asev_shader_loader PROPERTIES
  PREFIX "lib"
  SUFFIX "${SHADER_EXTENSION}"
  OUTPUT_NAME "asev_shader_loader"
)

target_link_libraries(asev_shader_loader PRIVATE dl)


# ============================================================================
# Dynamic Lighting Shader
# ============================================================================
add_library(asev_shader_dynamic_lighting SHARED
  dynamic_lighting_shader.cpp
)

target_include_directories(asev_shader_dynamic_lighting PRIVATE
  ${CMAKE_CURRENT_SOURCE_DIR}/..  # For asev_shader_api.h
)

set_target_properties(asev_shader_dynamic_lighting PROPERTIES
  PREFIX "lib"
  SUFFIX "${SHADER_EXTENSION}"
  OUTPUT_NAME "asev_shader_dynamic_lighting"
)

target_compile_definitions(asev_shader_dynamic_lighting PRIVATE
  -DASEV_SHADER_EXPORTS
)


# ============================================================================
# Installation Rules
# ============================================================================

# Install to bin/ directory in project root (for Aseprite to load)
install(TARGETS asev_shader_basic_lighting asev_shader_loader asev_shader_dynamic_lighting
  LIBRARY DESTINATION "${CMAKE_SOURCE_DIR}/../bin"
  RUNTIME DESTINATION "${CMAKE_SOURCE_DIR}/../bin"
)

# ============================================================================
# Build Instructions (printed at configure time)
# ============================================================================

message(STATUS "")
message(STATUS "==========================================================")
message(STATUS "AseVoxel Native Shader Build Configuration")
message(STATUS "==========================================================")
message(STATUS "Platform: ${CMAKE_SYSTEM_NAME}")
message(STATUS "Shader Extension: ${SHADER_EXTENSION}")
message(STATUS "Output Directory: ${CMAKE_LIBRARY_OUTPUT_DIRECTORY}")
message(STATUS "")
message(STATUS "Build Commands:")
message(STATUS "  mkdir -p build && cd build")
message(STATUS "  cmake ..")
message(STATUS "  cmake --build .")
message(STATUS "  cmake --install .")
message(STATUS "")
message(STATUS "Shaders will be installed to: ../bin/")
message(STATUS "==========================================================")
message(STATUS "")
