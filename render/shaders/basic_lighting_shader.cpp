// basic_lighting_shader.cpp
// Simple Lambert + ambient lighting shader
// Returns computed color via out_rgba[4] parameter

#include "../native_shader_api.h"
#include <stdlib.h>
#include <string.h>
#include <math.h>

// ============================================================================
// Shader Instance State
// ============================================================================

typedef struct {
  float ambient;           // Ambient light intensity (0-1)
  float diffuse_strength;  // Diffuse multiplier (0-2)
} BasicLightingState;

// ============================================================================
// Metadata Functions
// ============================================================================

static native_version_t api_version(void) {
  native_version_t v = {1, 0, 0};
  return v;
}

static const char* shader_id(void) {
  return "pixelmatt.basic";
}

static const char* display_name(void) {
  return "Basic Lighting (Lambert)";
}

// ============================================================================
// Parameter Schema
// ============================================================================

static const native_param_def_t PARAMS[] = {
  {
    "ambient",
    NATIVE_T_FLOAT,
    (const float[]){0.15f},
    "Ambient Light",
    "Base illumination level (0-1)"
  },
  {
    "diffuse_strength",
    NATIVE_T_FLOAT,
    (const float[]){0.8f},
    "Diffuse Strength",
    "Diffuse lighting multiplier (0-2)"
  }
};

static const native_param_def_t* params_schema(int* out_count) {
  *out_count = 2;
  return PARAMS;
}

// ============================================================================
// Lifecycle Functions
// ============================================================================

static void* create(void) {
  BasicLightingState* state = (BasicLightingState*)malloc(sizeof(BasicLightingState));
  if (!state) return NULL;
  
  state->ambient = 0.15f;
  state->diffuse_strength = 0.8f;
  
  return state;
}

static void destroy(void* instance) {
  if (instance) {
    free(instance);
  }
}

static int set_param(void* instance, const char* key, const void* value) {
  if (!instance || !key || !value) return 1;
  
  BasicLightingState* state = (BasicLightingState*)instance;
  
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

// Compute Lambert lighting and return via out_rgba
static int run_voxel(void* instance, const native_ctx_t* ctx, int x, int y, int z, unsigned char out_rgba[4]) {
  if (!instance || !ctx) return 1;
  
  BasicLightingState* state = (BasicLightingState*)instance;
  
  // Get voxel color from model
  unsigned char rgba[4];
  if (!native_model_get_voxel(ctx->model, x, y, z, rgba)) {
    return 1; // Voxel doesn't exist
  }
  
  // Simple approach: average all face normals for volumetric-like lighting
  float normal[3] = {0, 0, 0};
  int face_count = 0;
  
  // Check all 6 faces and average normals of exposed ones
  const int dx[] = {0, 0, -1, 1, 0, 0};
  const int dy[] = {1, -1, 0, 0, 0, 0};
  const int dz[] = {0, 0, 0, 0, 1, -1};
  const float nx[] = {0, 0, -1, 1, 0, 0};
  const float ny[] = {1, -1, 0, 0, 0, 0};
  const float nz[] = {0, 0, 0, 0, 1, -1};
  
  for (int i = 0; i < 6; ++i) {
    unsigned char neighbor[4];
    if (!native_model_get_voxel(ctx->model, x + dx[i], y + dy[i], z + dz[i], neighbor) || neighbor[3] == 0) {
      // Face is exposed
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
    // Normalize
    float len = sqrtf(normal[0]*normal[0] + normal[1]*normal[1] + normal[2]*normal[2]);
    if (len > 0.0001f) {
      normal[0] /= len;
      normal[1] /= len;
      normal[2] /= len;
    }
  }
  
  // Compute lighting from all lights
  float total_diffuse = 0.0f;
  for (int i = 0; i < ctx->num_lights && i < 8; ++i) {
    float ndotl = normal[0] * ctx->lights[i].dir[0] +
                  normal[1] * ctx->lights[i].dir[1] +
                  normal[2] * ctx->lights[i].dir[2];
    if (ndotl > 0.0f) {
      total_diffuse += ndotl * ctx->lights[i].intensity * state->diffuse_strength;
    }
  }
  
  float total_light = state->ambient + total_diffuse;
  if (total_light > 1.5f) total_light = 1.5f; // Allow slight overbright
  
  // Apply lighting to color
  out_rgba[0] = (unsigned char)(rgba[0] * total_light);
  out_rgba[1] = (unsigned char)(rgba[1] * total_light);
  out_rgba[2] = (unsigned char)(rgba[2] * total_light);
  out_rgba[3] = rgba[3]; // Preserve alpha
  
  // Clamp
  if (out_rgba[0] > 255) out_rgba[0] = 255;
  if (out_rgba[1] > 255) out_rgba[1] = 255;
  if (out_rgba[2] > 255) out_rgba[2] = 255;
  
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
