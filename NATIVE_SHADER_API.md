# AseVoxel Native Shader API Specification

> **Version:** 1.0  
> **API Level:** 1  
> **Date:** 2025-11-06

---

## Overview

The **Native Shader API** enables C/C++ developers to write high-performance, stackable shader modules for AseVoxel that integrate seamlessly with the existing Lua ShaderStack system. Shaders are loaded as dynamic libraries (.so/.dylib/.dll) and interact through a stable C ABI.

### Design Goals

1. **ABI Stability:** C interface ensures binary compatibility across compiler versions
2. **Hot-Loadable:** Shaders discovered and loaded at runtime
3. **Stackable:** Multiple shaders compose via defined stage hooks
4. **Typed Parameters:** Auto-generated UI from schema
5. **Thread-Safe:** Optional parallelism hints

---

## 1. API Versioning

```c
#define ASEV_SHADER_API_VERSION 1
```

- **Major version change:** Breaking ABI change; loader rejects mismatched shaders
- **Minor version change:** Additive features; backward compatible
- **Patch version change:** Bug fixes; no API changes

Shaders report their compiled API version via `api_version()` function.

---

## 2. Binary Format & Discovery

### 2.1 Artifact Naming

```
libasev_shader_<name>.<ext>
```

Examples:
- `libasev_shader_dominant_face.so` (Linux)
- `libasev_shader_hsl_bloom.dylib` (macOS)
- `libasev_shader_cel_outline.dll` (Windows)

### 2.2 Search Paths (Priority Order)

1. Extension directory: `<AseVoxel extension>/bin/`
2. User config: `~/.config/aseprite/extensions/AseVoxel/shaders/`
3. System (future): `/usr/local/lib/asevoxel/shaders/`

### 2.3 Entry Point Symbol

Every shader must export:

```c
const asev_shader_v1_t* asev_shader_get_v1(void);
```

Loader uses `dlsym()` (POSIX) or `GetProcAddress()` (Windows) to resolve this symbol.

---

## 3. Core API Header (`asev_shader_api.h`)

```c
// asev_shader_api.h
#pragma once

#define ASEV_SHADER_API_VERSION 1

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
} asev_version_t;

// ============================================================================
// Execution Context
// ============================================================================

typedef enum {
  ASEV_STAGE_PRE,    // Before any rendering
  ASEV_STAGE_VOXEL,  // Per-voxel processing
  ASEV_STAGE_FACE,   // Per-visible-face processing
  ASEV_STAGE_IMAGE,  // Post-geometry (fullscreen passes)
  ASEV_STAGE_POST    // Cleanup/metadata
} asev_stage_t;

typedef struct {
  // Transform matrices (column-major 4x4)
  float M[16];  // Model (world)
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
  void* model;  // Host provides query functions below

  // Render target (opaque handle)
  void* surface;  // GraphicsContext or Image buffer adapter

  // Time
  float time_sec;  // Seconds since render start
} asev_ctx_t;

// ============================================================================
// Parameter System
// ============================================================================

typedef enum {
  ASEV_T_BOOL,
  ASEV_T_INT,
  ASEV_T_FLOAT,
  ASEV_T_VEC3,
  ASEV_T_COLOR,   // RGBA (4 floats, 0-1 range)
  ASEV_T_STRING
} asev_type_t;

typedef struct {
  const char* key;        // Unique parameter key (e.g., "ambient")
  asev_type_t type;       // Value type
  const void* default_val; // Pointer to default value
  const char* display_name; // UI label (optional, can be NULL)
  const char* tooltip;      // Help text (optional)
} asev_param_def_t;

// ============================================================================
// Shader Interface (Function Table)
// ============================================================================

typedef struct {
  // Metadata
  asev_version_t (*api_version)(void);
  const char*    (*shader_id)(void);      // Stable ID (e.g., "pixelmatt.dominant_face")
  const char*    (*display_name)(void);   // UI name (e.g., "Dominant Face Shader")

  // Parameter schema
  const asev_param_def_t* (*params_schema)(int* out_count);

  // Lifecycle
  void*  (*create)(void);                 // Allocate shader instance
  void   (*destroy)(void* instance);      // Free shader instance
  int    (*set_param)(void* instance, const char* key, const void* value);

  // Execution hooks (return 0 on success, non-zero on error)
  int (*run_pre)(void* instance, const asev_ctx_t* ctx);
  int (*run_voxel)(void* instance, const asev_ctx_t* ctx, int x, int y, int z);
  int (*run_face)(void* instance, const asev_ctx_t* ctx, int x, int y, int z, int face_idx);
  int (*run_image)(void* instance, const asev_ctx_t* ctx);
  int (*run_post)(void* instance, const asev_ctx_t* ctx);

  // Threading hint
  int (*parallelism_hint)(void);  // 0 = auto, 1 = serial, N = preferred thread count
} asev_shader_v1_t;

// ============================================================================
// Host-Provided Helper Functions (linked by host)
// ============================================================================

// Voxel model queries
int    asev_model_get_size(void* model, int* out_x, int* out_y, int* out_z);
int    asev_model_get_voxel(void* model, int x, int y, int z, unsigned char* out_rgba);
int    asev_model_is_visible(void* model, int x, int y, int z);

// Surface operations (write-only during shader execution)
int    asev_surface_set_pixel(void* surface, int x, int y, unsigned char r, unsigned char g, unsigned char b, unsigned char a);
int    asev_surface_get_size(void* surface, int* out_w, int* out_h);

#ifdef __cplusplus
}
#endif
```

---

## 4. Execution Model

### 4.1 Stage Lifecycle

For each frame, the host calls shader hooks in this order:

```
1. PRE stage (all shaders in stack order)
2. For each visible voxel:
     a. VOXEL stage (all shaders)
     b. For each visible face:
          - FACE stage (all shaders)
3. IMAGE stage (all shaders)
4. POST stage (all shaders)
```

### 4.2 Hook Semantics

| Hook | Purpose | Parallelizable? | Read/Write Access |
|------|---------|-----------------|-------------------|
| `run_pre` | Initialize per-frame state, LUTs | No | Read model, write instance state |
| `run_voxel` | Modify voxel color/visibility | Yes* | Read model, write temp buffers |
| `run_face` | Adjust face lighting/normals | Yes* | Read model+voxel data, write buffers |
| `run_image` | Fullscreen effects (blur, grade) | No | Read/write surface |
| `run_post` | Finalize, export metadata | No | Read-only |

*If `parallelism_hint() > 1`

### 4.3 Data Flow

- **Read-only:** `asev_ctx_t` (transforms, lights, time)
- **Read-write:** Shader instance state (via `create()`/`destroy()`)
- **Write-only:** Surface (via `asev_surface_*` functions)
- **Unsafe:** Direct pixel buffer access (reserved for future API levels)

---

## 5. Parameter System

### 5.1 Schema Definition

Shaders declare parameters via `params_schema()`:

```c
static const asev_param_def_t SCHEMA[] = {
  {"ambient", ASEV_T_FLOAT, (const float[]){0.15f}, "Ambient Light", "Base illumination level"},
  {"tint", ASEV_T_COLOR, (const float[]){1.0f, 1.0f, 1.0f, 1.0f}, "Color Tint", NULL},
  {"enabled", ASEV_T_BOOL, (const int[]){1}, "Enable Effect", NULL}
};

const asev_param_def_t* my_params_schema(int* out_count) {
  *out_count = 3;
  return SCHEMA;
}
```

### 5.2 UI Auto-Generation

Host generates UI controls based on `asev_type_t`:

- `ASEV_T_BOOL` → Checkbox
- `ASEV_T_INT` → Number input
- `ASEV_T_FLOAT` → Slider (range inferred or specified via extended schema)
- `ASEV_T_VEC3` → 3 number inputs (X/Y/Z)
- `ASEV_T_COLOR` → Color picker (RGBA)
- `ASEV_T_STRING` → Text input

### 5.3 Value Passing

When user changes a param:

```c
float new_ambient = 0.25f;
int result = shader_iface->set_param(instance, "ambient", &new_ambient);
```

Shader validates and stores the value in instance state.

---

## 6. Threading Model

### 6.1 Parallelism Hints

```c
int parallelism_hint(void) {
  return 0;  // Auto (host decides)
  // return 1;  // Force serial execution
  // return 8;  // Prefer 8 threads
}
```

### 6.2 Thread Safety Requirements

If `parallelism_hint() > 1`:
- **Reentrant:** `run_voxel()` and `run_face()` may be called concurrently
- **No shared writes:** Instance state must be read-only or use atomics
- **Host responsibility:** Synchronize surface writes

If `parallelism_hint() == 1`:
- **Serial guarantee:** Hooks called sequentially

---

## 7. Error Handling

### 7.1 Return Codes

- `0` — Success
- `1` — Recoverable error (skip shader this frame)
- `2` — Fatal error (disable shader permanently)

### 7.2 Error Reporting (Future)

```c
// Extended API (v2+)
const char* (*get_last_error)(void* instance);
```

For API v1, host displays generic error toast.

---

## 8. Example Shader: Dominant Face

```c
// dominant_face_shader.c
#include "asev_shader_api.h"
#include <stdlib.h>
#include <string.h>

// Instance state
typedef struct {
  float ambient;
  float tint[4];
} DominantFaceState;

// Metadata
static asev_version_t api_version(void) { return (asev_version_t){1, 0, 0}; }
static const char* shader_id(void) { return "pixelmatt.dominant_face"; }
static const char* display_name(void) { return "Dominant Face Shader"; }

// Parameters
static const asev_param_def_t PARAMS[] = {
  {"ambient", ASEV_T_FLOAT, (const float[]){0.1f}, "Ambient", "Base light level"},
  {"tint", ASEV_T_COLOR, (const float[]){1.0f, 1.0f, 1.0f, 1.0f}, "Tint", "Color multiplier"}
};

static const asev_param_def_t* params_schema(int* count) {
  *count = 2;
  return PARAMS;
}

// Lifecycle
static void* create(void) {
  DominantFaceState* s = malloc(sizeof(DominantFaceState));
  s->ambient = 0.1f;
  memcpy(s->tint, (float[]){1.0f, 1.0f, 1.0f, 1.0f}, sizeof(s->tint));
  return s;
}

static void destroy(void* instance) { free(instance); }

static int set_param(void* instance, const char* key, const void* value) {
  DominantFaceState* s = instance;
  if (strcmp(key, "ambient") == 0) {
    s->ambient = *(const float*)value;
  } else if (strcmp(key, "tint") == 0) {
    memcpy(s->tint, value, sizeof(s->tint));
  } else {
    return 1; // Unknown param
  }
  return 0;
}

// Execution hook (simplified TLR priority logic)
static int run_voxel(void* instance, const asev_ctx_t* ctx, int x, int y, int z) {
  DominantFaceState* s = instance;
  unsigned char rgba[4];
  
  if (!asev_model_get_voxel(ctx->model, x, y, z, rgba)) return 1;
  
  // Apply ambient + tint (simplified)
  rgba[0] = (unsigned char)(rgba[0] * s->tint[0] * (1.0f + s->ambient));
  rgba[1] = (unsigned char)(rgba[1] * s->tint[1] * (1.0f + s->ambient));
  rgba[2] = (unsigned char)(rgba[2] * s->tint[2] * (1.0f + s->ambient));
  
  // (In real implementation: compute screen pos, write to surface)
  return 0;
}

// Function table
static asev_shader_v1_t IFACE = {
  .api_version = api_version,
  .shader_id = shader_id,
  .display_name = display_name,
  .params_schema = params_schema,
  .create = create,
  .destroy = destroy,
  .set_param = set_param,
  .run_pre = NULL,
  .run_voxel = run_voxel,
  .run_face = NULL,
  .run_image = NULL,
  .run_post = NULL,
  .parallelism_hint = NULL  // Auto-detect
};

// Entry point
const asev_shader_v1_t* asev_shader_get_v1(void) { return &IFACE; }
```

### 8.1 Building the Example

```bash
# Linux
gcc -shared -fPIC -o libasev_shader_dominant_face.so dominant_face_shader.c

# macOS
clang -dynamiclib -o libasev_shader_dominant_face.dylib dominant_face_shader.c

# Windows (MinGW)
gcc -shared -o libasev_shader_dominant_face.dll dominant_face_shader.c -Wl,--out-implib,libasev_shader_dominant_face.a
```

---

## 9. Loader Implementation (Host Side)

### 9.1 Pseudocode

```cpp
// native_shader_loader.cpp
#include <dlfcn.h> // POSIX
#include <vector>
#include <string>

struct LoadedShader {
  void* lib_handle;
  const asev_shader_v1_t* iface;
  void* instance;
};

std::vector<LoadedShader> g_shaders;

bool load_shader(const std::string& path) {
  void* handle = dlopen(path.c_str(), RTLD_LAZY);
  if (!handle) return false;

  auto get_v1 = (const asev_shader_v1_t* (*)())dlsym(handle, "asev_shader_get_v1");
  if (!get_v1) { dlclose(handle); return false; }

  const asev_shader_v1_t* iface = get_v1();
  if (!iface || iface->api_version().major != ASEV_SHADER_API_VERSION) {
    dlclose(handle);
    return false;
  }

  void* instance = iface->create ? iface->create() : nullptr;
  g_shaders.push_back({handle, iface, instance});
  return true;
}

void unload_all_shaders() {
  for (auto& s : g_shaders) {
    if (s.iface->destroy && s.instance) s.iface->destroy(s.instance);
    dlclose(s.lib_handle);
  }
  g_shaders.clear();
}
```

### 9.2 Discovery

```cpp
void discover_shaders(const std::string& dir) {
  // Scan directory for libasev_shader_*.so|dylib|dll
  // For each found: load_shader(path)
}
```

---

## 10. Integration with PipelineSpec

When `backend = "Native"`:

1. Filter `shader_stack` to only include shaders present in loader registry
2. Pass each shader's params via `set_param()` before rendering
3. Call hooks according to stage model
4. Collect errors and display in UI

**UI Behavior:**

```lua
if pipeline_spec.backend == "Native" then
  -- Show only native-available shaders
  available_shaders = AseVoxel.native.shader_registry.list()
else
  -- Show all Lua shaders
  available_shaders = AseVoxel.lua_shaders.list()
end
```

---

## 11. Future API Levels

### API v2 (Tentative)

- Direct pixel buffer access (zero-copy)
- Compute shader support (GPU dispatch)
- Shader-to-shader communication (render passes)
- Extended error reporting

### API v3 (Speculative)

- Hot reload without restart
- Live parameter animation
- Multi-pass render targets

---

## 12. Security Considerations

- **Code Execution:** Native shaders run with full process privileges
- **Sandboxing:** Not implemented in v1; community shaders should be audited
- **Crash Isolation:** Shader errors should not crash host (return codes)

**Recommendation:** Only load shaders from trusted sources.

---

## 13. Reference Implementations

Planned example shaders to ship with AseVoxel:

1. **Dominant Face** — TLR priority projected shading
2. **HSL Bloom** — Image-space glow effect
3. **Cel Outline** — Edge detection with thickness control
4. **Ambient Occlusion** — Per-voxel neighborhood sampling

Source code will be in `AseVoxel/render/shaders/reference/`.

---

## Appendix: Helper Function Details

### `asev_model_get_voxel`

```c
int asev_model_get_voxel(void* model, int x, int y, int z, unsigned char* out_rgba);
```

- **Returns:** `1` if voxel exists, `0` if empty/out-of-bounds
- **Output:** `out_rgba[0..3]` = R, G, B, A (0-255)

### `asev_surface_set_pixel`

```c
int asev_surface_set_pixel(void* surface, int x, int y, unsigned char r, unsigned char g, unsigned char b, unsigned char a);
```

- **Returns:** `0` on success, non-zero if out-of-bounds
- **Coordinates:** Screen space (post-projection)

---

**Status:** Draft for review · Feedback welcome via GitHub issues.
