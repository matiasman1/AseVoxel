// dynamic_lighting_shader.cpp
// Advanced lighting with per-light contribution, specular highlights
// Returns computed color via out_rgba[4] parameter

#include "../native_shader_api.h"
#include <stdlib.h>
#include <string.h>
#include <math.h>

// ============================================================================
// Shader Instance State
// ============================================================================

typedef struct {
  float ambient;          // Ambient light intensity (0-1)
  float diffuse_strength; // Diffuse multiplier (0-2)
  float specular_strength;// Specular multiplier (0-2)
  float shininess;        // Specular exponent (1-128)
} DynamicLightingState;

// ============================================================================
// Metadata Functions
// ============================================================================

static native_version_t api_version(void) {
  native_version_t v = {1, 0, 0};
  return v;
}

static const char* shader_id(void) {
  return "pixelmatt.dynamic";
}

static const char* display_name(void) {
  return "Dynamic Lighting (Phong)";
}

// ============================================================================
// Parameter Schema
// ============================================================================

static const native_param_def_t PARAMS[] = {
  {
    "ambient",
    NATIVE_T_FLOAT,
    (const float[]){0.1f},
    "Ambient Light",
    "Base illumination level (0-1)"
  },
  {
    "diffuse_strength",
    NATIVE_T_FLOAT,
    (const float[]){0.7f},
    "Diffuse Strength",
    "Diffuse lighting multiplier (0-2)"
  },
  {
    "specular_strength",
    NATIVE_T_FLOAT,
    (const float[]){0.3f},
    "Specular Strength",
    "Specular highlight intensity (0-2)"
  },
  {
    "shininess",
    NATIVE_T_FLOAT,
    (const float[]){32.0f},
    "Shininess",
    "Specular exponent (1-128, higher = sharper)"
  }
};

static const native_param_def_t* params_schema(int* out_count) {
  *out_count = 4;
  return PARAMS;
}

// ============================================================================
// Lifecycle Functions
// ============================================================================

static void* create(void) {
  DynamicLightingState* state = (DynamicLightingState*)malloc(sizeof(DynamicLightingState));
  if (!state) return NULL;
  
  state->ambient = 0.1f;
  state->diffuse_strength = 0.7f;
  state->specular_strength = 0.3f;
  state->shininess = 32.0f;
  
  return state;
}

static void destroy(void* instance) {
  if (instance) {
    free(instance);
  }
}

static int set_param(void* instance, const char* key, const void* value) {
  if (!instance || !key || !value) return 1;
  
  DynamicLightingState* state = (DynamicLightingState*)instance;
  
  if (strcmp(key, "ambient") == 0) {
    state->ambient = *(const float*)value;
    if (state->ambient < 0.0f) state->ambient = 0.0f;
    if (state->ambient > 1.0f) state->ambient = 1.0f;
    return 0;
  }
  
  if (strcmp(key, "diffuse_strength") == 0) {
    state->diffuse_strength = *(const float*)value;
    if (state->diffuse_strength < 0.0f) state->diffuse_strength = 0.0f;
    if (state->diffuse_strength > 2.0f) state->diffuse_strength = 2.0f;
    return 0;
  }
  
  if (strcmp(key, "specular_strength") == 0) {
    state->specular_strength = *(const float*)value;
    if (state->specular_strength < 0.0f) state->specular_strength = 0.0f;
    if (state->specular_strength > 2.0f) state->specular_strength = 2.0f;
    return 0;
  }
  
  if (strcmp(key, "shininess") == 0) {
    state->shininess = *(const float*)value;
    if (state->shininess < 1.0f) state->shininess = 1.0f;
    if (state->shininess > 128.0f) state->shininess = 128.0f;
    return 0;
  }
  
  return 1; // Unknown parameter
}

// ============================================================================
// Execution Hooks
// ============================================================================

static int run_pre(void* instance, const native_ctx_t* ctx) {
  (void)instance;
  (void)ctx;
  return 0;
}

// Helper: normalize a vector
static void normalize(float v[3]) {
  float len = sqrtf(v[0]*v[0] + v[1]*v[1] + v[2]*v[2]);
  if (len > 0.0001f) {
    v[0] /= len;
    v[1] /= len;
    v[2] /= len;
  }
}

// Helper: dot product
static float dot(const float a[3], const float b[3]) {
  return a[0]*b[0] + a[1]*b[1] + a[2]*b[2];
}

// Compute Phong lighting (diffuse + specular) and return via out_rgba
static int run_voxel(void* instance, const native_ctx_t* ctx, int x, int y, int z, unsigned char out_rgba[4]) {
  if (!instance || !ctx) return 1;
  
  DynamicLightingState* state = (DynamicLightingState*)instance;
  
  // Get voxel color from model
  unsigned char rgba[4];
  if (!native_model_get_voxel(ctx->model, x, y, z, rgba)) {
    return 1; // Voxel doesn't exist
  }
  
  // Compute average normal from exposed faces
  float normal[3] = {0, 0, 0};
  int face_count = 0;
  
  const int dx[] = {0, 0, -1, 1, 0, 0};
  const int dy[] = {1, -1, 0, 0, 0, 0};
  const int dz[] = {0, 0, 0, 0, 1, -1};
  const float nx[] = {0, 0, -1, 1, 0, 0};
  const float ny[] = {1, -1, 0, 0, 0, 0};
  const float nz[] = {0, 0, 0, 0, 1, -1};
  
  for (int i = 0; i < 6; ++i) {
    unsigned char neighbor[4];
    if (!native_model_get_voxel(ctx->model, x + dx[i], y + dy[i], z + dz[i], neighbor) || neighbor[3] == 0) {
      normal[0] += nx[i];
      normal[1] += ny[i];
      normal[2] += nz[i];
      face_count++;
    }
  }
  
  if (face_count > 0) {
    normal[0] /= face_count;
    normal[1] /= face_count;
    normal[2] /= face_count;
    normalize(normal);
  }
  
  // View direction (from voxel to camera)
  // Approximate camera position from quaternion (looking along -Z in view space)
  // For simplicity, use inverse of light direction as view dir
  float view_dir[3] = {0, 0, 1};
  if (ctx->num_lights > 0) {
    view_dir[0] = -ctx->lights[0].dir[0];
    view_dir[1] = -ctx->lights[0].dir[1];
    view_dir[2] = -ctx->lights[0].dir[2];
  }
  normalize(view_dir);
  
  // Compute lighting from all lights
  float total_diffuse = 0.0f;
  float total_specular = 0.0f;
  
  for (int i = 0; i < ctx->num_lights && i < 8; ++i) {
    const float* light_dir = ctx->lights[i].dir;
    float intensity = ctx->lights[i].intensity;
    
    // Diffuse (Lambert)
    float ndotl = dot(normal, light_dir);
    if (ndotl > 0.0f) {
      total_diffuse += ndotl * intensity * state->diffuse_strength;
      
      // Specular (Phong)
      // Reflect light direction around normal: R = 2(N·L)N - L
      float reflect[3];
      reflect[0] = 2.0f * ndotl * normal[0] - light_dir[0];
      reflect[1] = 2.0f * ndotl * normal[1] - light_dir[1];
      reflect[2] = 2.0f * ndotl * normal[2] - light_dir[2];
      normalize(reflect);
      
      float rdotv = dot(reflect, view_dir);
      if (rdotv > 0.0f) {
        float spec = powf(rdotv, state->shininess);
        total_specular += spec * ctx->lights[i].spec_power * state->specular_strength;
      }
    }
  }
  
  float total_light = state->ambient + total_diffuse;
  if (total_light > 1.5f) total_light = 1.5f;
  
  // Apply diffuse lighting to base color
  float lit_r = rgba[0] * total_light;
  float lit_g = rgba[1] * total_light;
  float lit_b = rgba[2] * total_light;
  
  // Add specular highlight (white)
  lit_r += total_specular * 255.0f;
  lit_g += total_specular * 255.0f;
  lit_b += total_specular * 255.0f;
  
  // Clamp to 0-255
  out_rgba[0] = (lit_r > 255.0f) ? 255 : (unsigned char)lit_r;
  out_rgba[1] = (lit_g > 255.0f) ? 255 : (unsigned char)lit_g;
  out_rgba[2] = (lit_b > 255.0f) ? 255 : (unsigned char)lit_b;
  out_rgba[3] = rgba[3]; // Preserve alpha
  
  return 0;
}

static int run_post(void* instance, const native_ctx_t* ctx) {
  (void)instance;
  (void)ctx;
  return 0;
}

static int parallelism_hint(void) {
  return 0; // Auto-detect
}

// ============================================================================
// Function Table
// ============================================================================

static native_shader_v1_t SHADER_IFACE = {
  api_version,
  shader_id,
  display_name,
  params_schema,
  create,
  destroy,
  set_param,
  run_pre,
  run_voxel,  // Main hook
  NULL,       // run_face (not used)
  NULL,       // run_image (not used)
  run_post,
  parallelism_hint
};

// ============================================================================
// Entry Point (C ABI export)
// ============================================================================

extern "C" const native_shader_v1_t* native_shader_get_v1(void) {
  return &SHADER_IFACE;
}
