// test_shader_load.cpp
// Simple test to verify shader modules can be loaded via dlopen

#include "../asev_shader_api.h"
#include <dlfcn.h>
#include <stdio.h>
#include <string.h>

int main() {
  printf("=== AseVoxel Native Shader Load Test ===\n\n");
  
  const char* shader_paths[] = {
    "../../bin/libasev_shader_basic_lighting.so",
    "../../bin/libasev_shader_dominant_face.so"
  };
  
  for (int i = 0; i < 2; ++i) {
    printf("Testing: %s\n", shader_paths[i]);
    
    // Open shader module
    void* handle = dlopen(shader_paths[i], RTLD_LAZY);
    if (!handle) {
      printf("  ✗ FAILED to load: %s\n\n", dlerror());
      continue;
    }
    printf("  ✓ Loaded successfully\n");
    
    // Resolve entry point
    typedef const asev_shader_v1_t* (*get_shader_fn)(void);
    get_shader_fn get_shader = (get_shader_fn)dlsym(handle, "asev_shader_get_v1");
    if (!get_shader) {
      printf("  ✗ FAILED to resolve entry point: %s\n\n", dlerror());
      dlclose(handle);
      continue;
    }
    printf("  ✓ Entry point resolved\n");
    
    // Get function table
    const asev_shader_v1_t* shader = get_shader();
    if (!shader) {
      printf("  ✗ FAILED: get_v1() returned NULL\n\n");
      dlclose(handle);
      continue;
    }
    printf("  ✓ Function table retrieved\n");
    
    // Validate API version
    asev_version_t ver = shader->api_version();
    printf("  API Version: %d.%d.%d\n", ver.major, ver.minor, ver.patch);
    if (ver.major != 1) {
      printf("  ✗ WARNING: Expected API v1.x.x\n");
    } else {
      printf("  ✓ API version valid\n");
    }
    
    // Get shader metadata
    printf("  Shader ID: %s\n", shader->shader_id());
    printf("  Display Name: %s\n", shader->display_name());
    
    // Get parameter schema
    int param_count = 0;
    const asev_param_def_t* params = shader->params_schema(&param_count);
    printf("  Parameters: %d\n", param_count);
    for (int j = 0; j < param_count; ++j) {
      const char* type_str = "UNKNOWN";
      switch (params[j].type) {
        case ASEV_T_BOOL: type_str = "bool"; break;
        case ASEV_T_INT: type_str = "int"; break;
        case ASEV_T_FLOAT: type_str = "float"; break;
        case ASEV_T_VEC3: type_str = "vec3"; break;
        case ASEV_T_COLOR: type_str = "color"; break;
        case ASEV_T_STRING: type_str = "string"; break;
      }
      printf("    - %s (%s): %s\n", params[j].key, type_str, params[j].display_name);
    }
    
    // Test instance lifecycle
    printf("  Testing instance lifecycle...\n");
    void* instance = shader->create();
    if (!instance) {
      printf("  ✗ FAILED: create() returned NULL\n\n");
      dlclose(handle);
      continue;
    }
    printf("    ✓ Instance created\n");
    
    // Test parameter setting
    if (strcmp(shader->shader_id(), "pixelmatt.basic_lighting") == 0) {
      float ambient = 0.25f;
      int result = shader->set_param(instance, "ambient", &ambient);
      if (result == 0) {
        printf("    ✓ Parameter 'ambient' set to 0.25\n");
      } else {
        printf("    ✗ Failed to set parameter 'ambient'\n");
      }
    } else if (strcmp(shader->shader_id(), "pixelmatt.dominant_face") == 0) {
      float tint[4] = {1.0f, 0.8f, 0.8f, 1.0f};
      int result = shader->set_param(instance, "tint", tint);
      if (result == 0) {
        printf("    ✓ Parameter 'tint' set to [1.0, 0.8, 0.8, 1.0]\n");
      } else {
        printf("    ✗ Failed to set parameter 'tint'\n");
      }
    }
    
    // Destroy instance
    shader->destroy(instance);
    printf("    ✓ Instance destroyed\n");
    
    // Check parallelism hint
    int parallel_hint = shader->parallelism_hint();
    printf("  Parallelism Hint: %d (0=auto)\n", parallel_hint);
    
    // Unload
    dlclose(handle);
    printf("  ✓ Unloaded successfully\n");
    printf("\n");
  }
  
  printf("=== Test Complete ===\n");
  return 0;
}
