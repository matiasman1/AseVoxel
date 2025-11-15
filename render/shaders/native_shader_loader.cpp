#include "native_shader_loader.hpp"
#include <dlfcn.h>
#include <dirent.h>
#include <string.h>
#include <unordered_map>
#include <vector>
#include <string>
#include <cstdio>

namespace native_shader_loader {

struct LoadedShader {
    void* dl_handle;                      // dlopen handle
    const native_shader_v1_t* iface;      // Shader interface
    std::string path;                      // Full path to .so file
    std::string id;                        // Shader ID (from shader_id())
};

// Registry: shader_id -> LoadedShader
static std::unordered_map<std::string, LoadedShader> g_registry;

// Ordered list of shader IDs (for indexed access)
static std::vector<std::string> g_shader_ids;

// Expected API version
static const int EXPECTED_MAJOR = 1;
static const int EXPECTED_MINOR = 0;

int scan_directory(const char* shader_dir) {
    // Clear existing registry
    unload_all();
    
    DIR* dir = opendir(shader_dir);
    if (!dir) {
        fprintf(stderr, "[native_shader_loader] Failed to open directory: %s\n", shader_dir);
        return 0;
    }
    
    struct dirent* entry;
    int loaded_count = 0;
    
    while ((entry = readdir(dir)) != nullptr) {
        const char* name = entry->d_name;
        
        // Check for libnative_shader_*.so pattern
        if (strncmp(name, "libnative_shader_", 17) != 0) {
            continue;
        }
        
        size_t len = strlen(name);
        if (len < 3 || strcmp(name + len - 3, ".so") != 0) {
            continue;
        }
        
        // Build full path
        std::string full_path = std::string(shader_dir) + "/" + name;
        
        // dlopen with RTLD_LAZY - don't resolve all symbols immediately
        // (host helpers like native_model_get_voxel will be provided at runtime)
        void* handle = dlopen(full_path.c_str(), RTLD_LAZY | RTLD_LOCAL);
        if (!handle) {
            fprintf(stderr, "[native_shader_loader] Failed to load %s: %s\n", name, dlerror());
            continue;
        }
        
        // Resolve entry point
        typedef const native_shader_v1_t* (*get_v1_fn)(void);
        get_v1_fn get_v1 = (get_v1_fn)dlsym(handle, "native_shader_get_v1");
        
        if (!get_v1) {
            fprintf(stderr, "[native_shader_loader] No native_shader_get_v1 in %s\n", name);
            dlclose(handle);
            continue;
        }
        
        // Get interface
        const native_shader_v1_t* iface = get_v1();
        if (!iface) {
            fprintf(stderr, "[native_shader_loader] native_shader_get_v1 returned null in %s\n", name);
            dlclose(handle);
            continue;
        }
        
        // Validate API version
        native_version_t ver = iface->api_version();
        if (ver.major != EXPECTED_MAJOR) {
            fprintf(stderr, "[native_shader_loader] API version mismatch in %s: got %d.%d, expected %d.x\n",
                    name, ver.major, ver.minor, EXPECTED_MAJOR);
            dlclose(handle);
            continue;
        }
        
        // Get shader ID
        const char* shader_id = iface->shader_id();
        if (!shader_id || strlen(shader_id) == 0) {
            fprintf(stderr, "[native_shader_loader] Invalid shader_id in %s\n", name);
            dlclose(handle);
            continue;
        }
        
        // Check for duplicate IDs
        if (g_registry.find(shader_id) != g_registry.end()) {
            fprintf(stderr, "[native_shader_loader] Duplicate shader ID '%s' in %s\n", shader_id, name);
            dlclose(handle);
            continue;
        }
        
        // Register shader
        LoadedShader loaded;
        loaded.dl_handle = handle;
        loaded.iface = iface;
        loaded.path = full_path;
        loaded.id = shader_id;
        
        g_registry[shader_id] = loaded;
        g_shader_ids.push_back(shader_id);
        
        loaded_count++;
        
        printf("[native_shader_loader] Loaded shader '%s' from %s (API v%d.%d)\n",
               shader_id, name, ver.major, ver.minor);
    }
    
    closedir(dir);
    return loaded_count;
}

int get_shader_count() {
    return (int)g_shader_ids.size();
}

const char* get_shader_id(int index) {
    if (index < 0 || index >= (int)g_shader_ids.size()) {
        return nullptr;
    }
    return g_shader_ids[index].c_str();
}

const native_shader_v1_t* get_shader_interface(const char* shader_id) {
    auto it = g_registry.find(shader_id);
    if (it == g_registry.end()) {
        return nullptr;
    }
    return it->second.iface;
}

void* create_shader_instance(const char* shader_id) {
    auto it = g_registry.find(shader_id);
    if (it == g_registry.end()) {
        return nullptr;
    }
    
    const native_shader_v1_t* iface = it->second.iface;
    if (!iface->create) {
        return nullptr;
    }
    
    return iface->create();
}

void destroy_shader_instance(const char* shader_id, void* instance) {
    if (!instance) return;
    
    auto it = g_registry.find(shader_id);
    if (it == g_registry.end()) {
        return;
    }
    
    const native_shader_v1_t* iface = it->second.iface;
    if (iface->destroy) {
        iface->destroy(instance);
    }
}

void unload_all() {
    // Destroy all shader modules
    for (auto& pair : g_registry) {
        if (pair.second.dl_handle) {
            dlclose(pair.second.dl_handle);
        }
    }
    
    g_registry.clear();
    g_shader_ids.clear();
}

} // namespace native_shader_loader
