// native_shader_api.h
// AseVoxel Native Shader API v1.0
// Stable C ABI for stackable shader modules
#pragma once

#define NATIVE_SHADER_API_VERSION 1

#ifdef __cplusplus
extern "C" {
#endif

// ============================================================================
// Version & Metadata
// ============================================================================

typedef struct {
  int major;
  int minor;
  int patch;
} native_version_t;

// ============================================================================
// Execution Context
// ============================================================================

typedef enum {
  NATIVE_STAGE_PRE,    // Before any rendering (setup, LUTs)
  NATIVE_STAGE_VOXEL,  // Per-voxel processing
  NATIVE_STAGE_FACE,   // Per-visible-face processing
  NATIVE_STAGE_IMAGE,  // Post-geometry fullscreen passes
  NATIVE_STAGE_POST    // Cleanup/metadata
} native_stage_t;

// Execution context passed to shader hooks
typedef struct {
  // Transform matrices (column-major 4x4)
  float M[16];  // Model (world transform)
  float V[16];  // View
  float P[16];  // Projection
  
  // Camera orientation (quaternion: x, y, z, w)
  float q_view[4];
  
  // Lighting (up to 8 lights)
  int num_lights;
  struct {
    float dir[3];       // Direction (unit vector)
    float intensity;    // Diffuse multiplier
    float spec_power;   // Specular exponent
  } lights[8];
  
  // Voxel model accessor (opaque handle)
  void* model;  // Host provides query functions
  
  // Output buffer (host-provided RGBA buffer for shader to write to)
  unsigned char* output_buffer;  // Shader writes computed colors here
  int output_stride;             // Bytes per row (usually width*4)
  
  // Time
  float time_sec;  // Seconds since render start
  
  // Frame info
  int width;
  int height;
} native_ctx_t;

// ============================================================================
// Parameter System
// ============================================================================

typedef enum {
  NATIVE_T_BOOL,
  NATIVE_T_INT,
  NATIVE_T_FLOAT,
  NATIVE_T_VEC3,
  NATIVE_T_COLOR,   // RGBA (4 floats, 0-1 range)
  NATIVE_T_STRING
} native_type_t;

typedef struct {
  const char* key;        // Unique parameter key (e.g., "ambient")
  native_type_t type;       // Value type
  const void* default_val; // Pointer to default value
  const char* display_name; // UI label (optional, can be NULL)
  const char* tooltip;      // Help text (optional)
} native_param_def_t;

// ============================================================================
// Shader Interface (Function Table)
// ============================================================================

typedef struct {
  // Metadata
  native_version_t (*api_version)(void);
  const char*    (*shader_id)(void);      // Stable ID (e.g., "pixelmatt.basic_lighting")
  const char*    (*display_name)(void);   // UI name (e.g., "Basic Lighting")
  
  // Parameter schema
  const native_param_def_t* (*params_schema)(int* out_count);
  
  // Lifecycle
  void*  (*create)(void);                 // Allocate shader instance
  void   (*destroy)(void* instance);      // Free shader instance
  int    (*set_param)(void* instance, const char* key, const void* value);
  
  // Execution hooks (return 0 on success, non-zero on error)
  int (*run_pre)(void* instance, const native_ctx_t* ctx);
  // New: run_voxel/run_face must fill out_rgba[4] with computed color (0-255)
  int (*run_voxel)(void* instance, const native_ctx_t* ctx, int x, int y, int z, unsigned char out_rgba[4]);
  int (*run_face)(void* instance, const native_ctx_t* ctx, int x, int y, int z, int face_idx, unsigned char out_rgba[4]);
  int (*run_image)(void* instance, const native_ctx_t* ctx);
  int (*run_post)(void* instance, const native_ctx_t* ctx);
  
  // Threading hint
  int (*parallelism_hint)(void);  // 0 = auto, 1 = serial, N = preferred thread count
} native_shader_v1_t;

// ============================================================================
// Host-Provided Helper Functions
// (These are implemented by the host and available to shaders)
// ============================================================================

// Voxel model queries (preferred prefix: native_)
int native_model_get_size(void* model, int* out_x, int* out_y, int* out_z);
int native_model_get_voxel(void* model, int x, int y, int z, unsigned char* out_rgba);
int native_model_is_visible(void* model, int x, int y, int z);

// Surface operations (write-only during shader execution) - host should provide
int native_surface_set_pixel(void* surface, int x, int y, unsigned char r, unsigned char g, unsigned char b, unsigned char a);
int native_surface_get_size(void* surface, int* out_w, int* out_h);

// Backwards-compatible aliases (old prefix `asev_` -> new `native_`)
#define asev_model_get_size native_model_get_size
#define asev_model_get_voxel native_model_get_voxel
#define asev_model_is_visible native_model_is_visible
#define asev_surface_set_pixel native_surface_set_pixel
#define asev_surface_get_size native_surface_get_size

// Math helpers
float asev_dot3(const float* a, const float* b);
void asev_normalize3(float* v);
void asev_cross3(const float* a, const float* b, float* out);

// ============================================================================
// Entry Point (required export from shader module)
// ============================================================================

// Every shader module MUST export this function
const native_shader_v1_t* native_shader_get_v1(void);

#ifdef __cplusplus
}
#endif
