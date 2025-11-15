#ifndef NATIVE_SHADER_LOADER_HPP
#define NATIVE_SHADER_LOADER_HPP

#include "../native_shader_api.h"
#include <string>

// C++ interface for loading and managing native shader modules
namespace native_shader_loader {

// Initialize the loader and scan for shader modules in the given directory
// Returns the number of shaders loaded
int scan_directory(const char* shader_dir);

// Get the count of loaded shaders
int get_shader_count();

// Get the shader ID at the given index (0-based)
// Returns nullptr if index is out of bounds
const char* get_shader_id(int index);

// Get the shader interface by ID
// Returns nullptr if shader not found
const native_shader_v1_t* get_shader_interface(const char* shader_id);

// Create an instance of the shader with the given ID
// Returns nullptr on failure
void* create_shader_instance(const char* shader_id);

// Destroy a shader instance
void destroy_shader_instance(const char* shader_id, void* instance);

// Unload all shaders and clean up
void unload_all();

} // namespace native_shader_loader

#endif // NATIVE_SHADER_LOADER_HPP
