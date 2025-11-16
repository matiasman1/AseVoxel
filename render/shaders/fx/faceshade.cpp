// faceshade_shader.cpp
// FX shader that colors faces based on their orientation (normal direction)
// Used for debugging face visibility and testing shader stacking
// Returns face-specific colors via out_rgba[4] parameter

#include "../native_shader_api.h"
#include <stdlib.h>
#include <string.h>
#include <math.h>

// ============================================================================
// Shader Instance State
// ============================================================================

typedef struct {
  // Face colors (RGB, 0-255 range)
  unsigned char top_color[3];     // Yellow default
  unsigned char bottom_color[3];  // Blue default
  unsigned char front_color[3];   // Cyan default
  unsigned char back_color[3];    // Red default
  unsigned char left_color[3];    // Magenta default
  unsigned char right_color[3];   // Green default
  
  int mode;  // 0=literal (ignore input), 1=alpha (blend with input), 2=material (only affect specific color)
  unsigned char material_color[3];  // For material mode
} FaceShadeState;

// ============================================================================
// Metadata Functions
// ============================================================================

static native_version_t api_version(void) {
  return (native_version_t){1, 0, 0};
}

static const char* shader_id(void) {
  return "pixelmatt.faceshade";
}

static const char* display_name(void) {
  return "FaceShade (Debug Colors)";
}

// ============================================================================
// Parameter Schema
// ============================================================================

static const native_param_def_t PARAMS[] = {
  {
    "mode",
    NATIVE_T_INT,
    (const int[]){0},  // 0=literal, 1=alpha, 2=material
    "Mode",
    "0=Literal, 1=Alpha Blend, 2=Material Only"
  },
  {
    "top_r",
    NATIVE_T_INT,
    (const int[]){255},
    "Top Red",
    "Top face red component (0-255)"
  },
  {
    "top_g",
    NATIVE_T_INT,
    (const int[]){255},
    "Top Green",
    "Top face green component (0-255)"
  },
  {
    "top_b",
    NATIVE_T_INT,
    (const int[]){0},
    "Top Blue",
    "Top face blue component (0-255)"
  },
  {
    "bottom_r",
    NATIVE_T_INT,
    (const int[]){0},
    "Bottom Red",
    "Bottom face red component (0-255)"
  },
  {
    "bottom_g",
    NATIVE_T_INT,
    (const int[]){0},
    "Bottom Green",
    "Bottom face green component (0-255)"
  },
  {
    "bottom_b",
    NATIVE_T_INT,
    (const int[]){255},
    "Bottom Blue",
    "Bottom face blue component (0-255)"
  },
  {
    "front_r",
    NATIVE_T_INT,
    (const int[]){0},
    "Front Red",
    "Front face red component (0-255)"
  },
  {
    "front_g",
    NATIVE_T_INT,
    (const int[]){255},
    "Front Green",
    "Front face green component (0-255)"
  },
  {
    "front_b",
    NATIVE_T_INT,
    (const int[]){255},
    "Front Blue",
    "Front face blue component (0-255)"
  },
  {
    "back_r",
    NATIVE_T_INT,
    (const int[]){255},
    "Back Red",
    "Back face red component (0-255)"
  },
  {
    "back_g",
    NATIVE_T_INT,
    (const int[]){0},
    "Back Green",
    "Back face green component (0-255)"
  },
  {
    "back_b",
    NATIVE_T_INT,
    (const int[]){0},
    "Back Blue",
    "Back face blue component (0-255)"
  },
  {
    "left_r",
    NATIVE_T_INT,
    (const int[]){255},
    "Left Red",
    "Left face red component (0-255)"
  },
  {
    "left_g",
    NATIVE_T_INT,
    (const int[]){0},
    "Left Green",
    "Left face green component (0-255)"
  },
  {
    "left_b",
    NATIVE_T_INT,
    (const int[]){255},
    "Left Blue",
    "Left face blue component (0-255)"
  },
  {
    "right_r",
    NATIVE_T_INT,
    (const int[]){0},
    "Right Red",
    "Right face red component (0-255)"
  },
  {
    "right_g",
    NATIVE_T_INT,
    (const int[]){255},
    "Right Green",
    "Right face green component (0-255)"
  },
  {
    "right_b",
    NATIVE_T_INT,
    (const int[]){0},
    "Right Blue",
    "Right face blue component (0-255)"
  }
};

static const native_param_def_t* params_schema(int* out_count) {
  *out_count = sizeof(PARAMS) / sizeof(PARAMS[0]);
  return PARAMS;
}

// ============================================================================
// Lifecycle Functions
// ============================================================================

static void* create(void) {
  FaceShadeState* state = new FaceShadeState();
  
  // Default colors: Top=Yellow, Bottom=Blue, Front=Cyan, Back=Red, Left=Magenta, Right=Green
  state->top_color[0] = 255; state->top_color[1] = 255; state->top_color[2] = 0;     // Yellow
  state->bottom_color[0] = 0; state->bottom_color[1] = 0; state->bottom_color[2] = 255;  // Blue
  state->front_color[0] = 0; state->front_color[1] = 255; state->front_color[2] = 255;   // Cyan
  state->back_color[0] = 255; state->back_color[1] = 0; state->back_color[2] = 0;        // Red
  state->left_color[0] = 255; state->left_color[1] = 0; state->left_color[2] = 255;      // Magenta
  state->right_color[0] = 0; state->right_color[1] = 255; state->right_color[2] = 0;     // Green
  
  state->mode = 0;  // Default to literal mode
  state->material_color[0] = 255;
  state->material_color[1] = 0;
  state->material_color[2] = 0;
  
  return state;
}

static void destroy(void* instance) {
  if (instance) {
    delete (FaceShadeState*)instance;
  }
}

static int set_param(void* instance, const char* key, const void* value) {
  if (!instance || !key || !value) return -1;
  
  FaceShadeState* state = (FaceShadeState*)instance;
  
  if (strcmp(key, "mode") == 0) {
    state->mode = *(const int*)value;
    return 0;
  }
  
  // Top face colors
  if (strcmp(key, "top_r") == 0) { state->top_color[0] = (unsigned char)(*(const int*)value); return 0; }
  if (strcmp(key, "top_g") == 0) { state->top_color[1] = (unsigned char)(*(const int*)value); return 0; }
  if (strcmp(key, "top_b") == 0) { state->top_color[2] = (unsigned char)(*(const int*)value); return 0; }
  
  // Bottom face colors
  if (strcmp(key, "bottom_r") == 0) { state->bottom_color[0] = (unsigned char)(*(const int*)value); return 0; }
  if (strcmp(key, "bottom_g") == 0) { state->bottom_color[1] = (unsigned char)(*(const int*)value); return 0; }
  if (strcmp(key, "bottom_b") == 0) { state->bottom_color[2] = (unsigned char)(*(const int*)value); return 0; }
  
  // Front face colors
  if (strcmp(key, "front_r") == 0) { state->front_color[0] = (unsigned char)(*(const int*)value); return 0; }
  if (strcmp(key, "front_g") == 0) { state->front_color[1] = (unsigned char)(*(const int*)value); return 0; }
  if (strcmp(key, "front_b") == 0) { state->front_color[2] = (unsigned char)(*(const int*)value); return 0; }
  
  // Back face colors
  if (strcmp(key, "back_r") == 0) { state->back_color[0] = (unsigned char)(*(const int*)value); return 0; }
  if (strcmp(key, "back_g") == 0) { state->back_color[1] = (unsigned char)(*(const int*)value); return 0; }
  if (strcmp(key, "back_b") == 0) { state->back_color[2] = (unsigned char)(*(const int*)value); return 0; }
  
  // Left face colors
  if (strcmp(key, "left_r") == 0) { state->left_color[0] = (unsigned char)(*(const int*)value); return 0; }
  if (strcmp(key, "left_g") == 0) { state->left_color[1] = (unsigned char)(*(const int*)value); return 0; }
  if (strcmp(key, "left_b") == 0) { state->left_color[2] = (unsigned char)(*(const int*)value); return 0; }
  
  // Right face colors
  if (strcmp(key, "right_r") == 0) { state->right_color[0] = (unsigned char)(*(const int*)value); return 0; }
  if (strcmp(key, "right_g") == 0) { state->right_color[1] = (unsigned char)(*(const int*)value); return 0; }
  if (strcmp(key, "right_b") == 0) { state->right_color[2] = (unsigned char)(*(const int*)value); return 0; }
  
  return -1; // Unknown parameter
}

// ============================================================================
// Helper Functions
// ============================================================================

static void normalize(float v[3]) {
  float len = sqrtf(v[0]*v[0] + v[1]*v[1] + v[2]*v[2]);
  if (len > 1e-6f) {
    v[0] /= len;
    v[1] /= len;
    v[2] /= len;
  }
}

// Determine which face this voxel belongs to based on exposed neighbors
static void get_dominant_face_color(FaceShadeState* state, int x, int y, int z, const native_ctx_t* ctx, unsigned char out_color[3]) {
  // Check all 6 neighbors
  const int dx[] = {0, 0, -1, 1, 0, 0};
  const int dy[] = {1, -1, 0, 0, 0, 0};
  const int dz[] = {0, 0, 0, 0, 1, -1};
  
  // Accumulated normal from exposed faces
  float normal[3] = {0, 0, 0};
  int face_count = 0;
  
  const float nx[] = {0, 0, -1, 1, 0, 0};
  const float ny[] = {1, -1, 0, 0, 0, 0};
  const float nz[] = {0, 0, 0, 0, 1, -1};
  
  for (int i = 0; i < 6; ++i) {
    unsigned char neighbor[4];
    if (!native_model_get_voxel(ctx->model, x + dx[i], y + dy[i], z + dz[i], neighbor) || neighbor[3] == 0) {
      // This face is exposed
      normal[0] += nx[i];
      normal[1] += ny[i];
      normal[2] += nz[i];
      face_count++;
    }
  }
  
  if (face_count == 0) {
    // Interior voxel? Default to red
    out_color[0] = 255;
    out_color[1] = 0;
    out_color[2] = 0;
    return;
  }
  
  // Normalize the average normal
  normalize(normal);
  
  // Determine dominant direction
  float abs_x = fabsf(normal[0]);
  float abs_y = fabsf(normal[1]);
  float abs_z = fabsf(normal[2]);
  
  if (abs_y > abs_x && abs_y > abs_z) {
    // Y-dominant (top or bottom)
    if (normal[1] > 0) {
      // Top face (+Y)
      memcpy(out_color, state->top_color, 3);
    } else {
      // Bottom face (-Y)
      memcpy(out_color, state->bottom_color, 3);
    }
  } else if (abs_x > abs_z) {
    // X-dominant (left or right)
    if (normal[0] > 0) {
      // Right face (+X)
      memcpy(out_color, state->right_color, 3);
    } else {
      // Left face (-X)
      memcpy(out_color, state->left_color, 3);
    }
  } else {
    // Z-dominant (front or back)
    if (normal[2] > 0) {
      // Front face (+Z)
      memcpy(out_color, state->front_color, 3);
    } else {
      // Back face (-Z)
      memcpy(out_color, state->back_color, 3);
    }
  }
}

// ============================================================================
// Execution Hooks
// ============================================================================

static int run_pre(void* instance, const native_ctx_t* ctx) {
  (void)instance;
  (void)ctx;
  return 0;
}

// Apply face shading based on voxel normal/orientation
static int run_voxel(void* instance, const native_ctx_t* ctx, int x, int y, int z, unsigned char out_rgba[4]) {
  if (!instance || !ctx) return 1;
  
  FaceShadeState* state = (FaceShadeState*)instance;
  
  // Get voxel color from model (or previous shader in stack)
  unsigned char base_rgba[4];
  if (!native_model_get_voxel(ctx->model, x, y, z, base_rgba)) {
    return 1; // Voxel doesn't exist
  }
  
  // Get the face color based on dominant exposed face
  unsigned char face_color[3];
  get_dominant_face_color(state, x, y, z, ctx, face_color);
  
  // Apply based on mode
  if (state->mode == 0) {
    // Literal mode: replace color entirely (ignore base)
    out_rgba[0] = face_color[0];
    out_rgba[1] = face_color[1];
    out_rgba[2] = face_color[2];
    out_rgba[3] = base_rgba[3]; // Preserve alpha
  } else if (state->mode == 1) {
    // Alpha blend mode: blend face color with base
    float alpha = 0.7f; // 70% face color, 30% base
    out_rgba[0] = (unsigned char)(face_color[0] * alpha + base_rgba[0] * (1.0f - alpha));
    out_rgba[1] = (unsigned char)(face_color[1] * alpha + base_rgba[1] * (1.0f - alpha));
    out_rgba[2] = (unsigned char)(face_color[2] * alpha + base_rgba[2] * (1.0f - alpha));
    out_rgba[3] = base_rgba[3];
  } else {
    // Material mode: only affect specific color (red in this case)
    if (base_rgba[0] > 200 && base_rgba[1] < 100 && base_rgba[2] < 100) {
      // This is a red voxel, apply face shading
      out_rgba[0] = face_color[0];
      out_rgba[1] = face_color[1];
      out_rgba[2] = face_color[2];
      out_rgba[3] = base_rgba[3];
    } else {
      // Not red, pass through
      memcpy(out_rgba, base_rgba, 4);
    }
  }
  
  return 0;
}

static int run_post(void* instance, const native_ctx_t* ctx) {
  (void)instance;
  (void)ctx;
  return 0;
}

static int parallelism_hint(void) {
  return 1; // Safe for per-voxel parallelism
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
  run_voxel,
  NULL,  // run_face not implemented
  NULL,  // run_image not implemented
  run_post,
  parallelism_hint
};

// ============================================================================
// Entry Point
// ============================================================================

extern "C" {
  const native_shader_v1_t* native_shader_get_v1(void) {
    return &SHADER_IFACE;
  }
}
