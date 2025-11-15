# Native Shader Quick Reference

## Building

```bash
cd render/shaders
make clean && make
```

**Output**:
- `../../bin/libnative_shader_basic.so` - Basic lighting (Lambert)
- `../../bin/libnative_shader_dynamic.so` - Dynamic lighting (Phong)
- `../../bin/libnative_shader_loader.a` - Loader library
- `../../bin/test_host_shim` - Test executable

## Testing Shaders

```bash
cd /home/usuario/Documentos/AseVoxel

# Test basic shader
./bin/test_host_shim ./bin pixelmatt.basic test_basic.png

# Test dynamic shader
./bin/test_host_shim ./bin pixelmatt.dynamic test_dynamic.png
```

## Creating a New Shader

### 1. Create shader file: `render/shaders/my_shader.cpp`

```cpp
#include "../native_shader_api.h"
#include <cmath>
#include <cstring>

// Shader state (per-instance)
struct MyShaderState {
    float my_param;
};

// API version
static native_version_t api_version() {
    return {1, 0, 0};
}

// Unique shader ID (use your namespace)
static const char* shader_id() {
    return "yourname.myshader";
}

// Display name (shown in UI)
static const char* display_name() {
    return "My Custom Shader";
}

// Parameter schema (JSON)
static const char* params_schema() {
    return R"({
        "my_param": {"type": "number", "default": 1.0, "min": 0.0, "max": 2.0}
    })";
}

// Create instance
static void* create() {
    MyShaderState* state = new MyShaderState();
    state->my_param = 1.0f;
    return state;
}

// Destroy instance
static void destroy(void* instance) {
    delete (MyShaderState*)instance;
}

// Set parameter
static int set_param(void* instance, const char* key, const char* value) {
    MyShaderState* state = (MyShaderState*)instance;
    if (strcmp(key, "my_param") == 0) {
        state->my_param = atof(value);
        return 0;
    }
    return -1; // Unknown parameter
}

// Per-voxel processing (MAIN FUNCTION)
static int run_voxel(void* instance, const native_ctx_t* ctx, int x, int y, int z, unsigned char out_rgba[4]) {
    MyShaderState* state = (MyShaderState*)instance;
    
    // Get voxel color
    unsigned char voxel_rgba[4];
    if (!native_model_get_voxel(ctx->model, x, y, z, voxel_rgba)) {
        return 1; // Empty voxel
    }
    
    // YOUR SHADER LOGIC HERE
    // Example: Just return voxel color scaled by parameter
    out_rgba[0] = (unsigned char)(voxel_rgba[0] * state->my_param);
    out_rgba[1] = (unsigned char)(voxel_rgba[1] * state->my_param);
    out_rgba[2] = (unsigned char)(voxel_rgba[2] * state->my_param);
    out_rgba[3] = voxel_rgba[3];
    
    return 0; // Success
}

// Optional stages (can return -1 if not implemented)
static int run_pre(void* instance, const native_ctx_t* ctx) { return -1; }
static int run_face(void* instance, const native_ctx_t* ctx, int x, int y, int z, int face, unsigned char out_rgba[4]) { return -1; }
static int run_image(void* instance, const native_ctx_t* ctx) { return -1; }
static int run_post(void* instance, const native_ctx_t* ctx) { return -1; }

// Parallelism hint (0=sequential, 1=per-voxel safe, 2=per-face safe)
static int parallelism_hint(void* instance) { return 1; }

// Function table (REQUIRED)
static native_shader_v1_t g_iface = {
    api_version,
    shader_id,
    display_name,
    params_schema,
    create,
    destroy,
    set_param,
    run_pre,
    run_voxel,
    run_face,
    run_image,
    run_post,
    parallelism_hint
};

// Entry point (REQUIRED)
extern "C" const native_shader_v1_t* native_shader_get_v1() {
    return &g_iface;
}
```

### 2. Add to Makefile

```makefile
SHADERS := \
    $(OUTDIR)/libnative_shader_basic$(EXT) \
    $(OUTDIR)/libnative_shader_dynamic$(EXT) \
    $(OUTDIR)/libnative_shader_myshader$(EXT)  # ADD THIS

# ... later ...

# My Custom Shader
$(OUTDIR)/libnative_shader_myshader$(EXT): my_shader.cpp ../native_shader_api.h
	@echo "Building $@..."
	$(CXX) $(CXXFLAGS) $(LDFLAGS)$@ $< -o $@
```

### 3. Build and test

```bash
cd render/shaders
make
./../../bin/test_host_shim ../../bin yourname.myshader test_my.png
```

## Host Helper Functions

Available to shaders via extern declarations (resolved at runtime):

```cpp
// Get voxel color at (x,y,z)
// Returns 1 if voxel exists, 0 if empty
int native_model_get_voxel(void* model, int x, int y, int z, unsigned char* out_rgba);

// Get model dimensions
int native_model_get_size(void* model, int* out_x, int* out_y, int* out_z);

// Check if voxel is visible (not occluded)
int native_model_is_visible(void* model, int x, int y, int z);
```

## Render Context (native_ctx_t)

Provided to shaders via `run_*` functions:

```cpp
typedef struct {
    // Matrices (column-major 4x4)
    float M[16];  // Model matrix
    float V[16];  // View matrix
    float P[16];  // Projection matrix
    
    // Lighting
    int num_lights;
    struct {
        float dir[3];      // Direction (normalized)
        float intensity;   // Multiplier
        float spec_power;  // Specular exponent
    } lights[8];
    
    // Model handle (opaque)
    void* model;
    
    // Output buffer (don't write directly - use out_rgba parameter!)
    unsigned char* output_buffer;
    int output_stride;
    
    // Frame info
    float time_sec;
    int width;
    int height;
} native_ctx_t;
```

## Common Lighting Patterns

### Lambert Diffuse
```cpp
float ndotl = nx * light_dir[0] + ny * light_dir[1] + nz * light_dir[2];
if (ndotl < 0.0f) ndotl = 0.0f;
float diffuse = ndotl * light_intensity;
```

### Phong Specular
```cpp
// Reflect: R = 2(N·L)N - L
float ndotl = nx * lx + ny * ly + nz * lz;
float rx = 2.0f * ndotl * nx - lx;
float ry = 2.0f * ndotl * ny - ly;
float rz = 2.0f * ndotl * nz - lz;

// View direction (towards camera)
float vx = 0.0f, vy = 0.0f, vz = -1.0f;

// Specular
float rdotv = rx * vx + ry * vy + rz * vz;
if (rdotv < 0.0f) rdotv = 0.0f;
float specular = powf(rdotv, shininess) * spec_power;
```

### Normal from Exposed Faces
```cpp
float nx = 0.0f, ny = 0.0f, nz = 0.0f;
int face_count = 0;

// Check +X face
unsigned char temp[4];
if (!native_model_get_voxel(ctx->model, x+1, y, z, temp)) {
    nx += 1.0f; face_count++;
}
// ... check other 5 faces ...

// Average
if (face_count > 0) {
    float len = sqrtf(nx*nx + ny*ny + nz*nz);
    nx /= len; ny /= len; nz /= len;
}
```

## Shader IDs (Reserved)

- `pixelmatt.basic` - Basic Lambert lighting
- `pixelmatt.dynamic` - Phong lighting
- `pixelmatt.flat` - (TODO) Unlit flat color
- `pixelmatt.fast` - (TODO) Dominant face only
- `pixelmatt.outline` - (TODO) Cel-shaded with outlines

Use your own namespace (e.g., `username.shadername`) for custom shaders.

## Troubleshooting

### "undefined symbol: native_model_get_voxel"
**Fix**: Host executable must be built with `-rdynamic` flag.

### "Failed to load shader: undefined symbol"
**Fix**: Check that shader uses `extern "C"` for `native_shader_get_v1()`.

### "API version mismatch"
**Fix**: Ensure shader returns `{1, 0, 0}` from `api_version()`.

### Shader crashes on run_voxel
**Fix**: Check bounds before calling host helpers. Validate pointers.

### Colors look wrong
**Fix**: Ensure out_rgba values are clamped to [0, 255] range.

---

**See also**: `NATIVE_SHADER_IMPLEMENTATION.md` for full documentation
