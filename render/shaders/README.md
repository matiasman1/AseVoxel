# AseVoxel Native Shaders

This directory contains native C++ shader modules that implement the **AseVoxel Native Shader API v1** (`asev_shader_api.h`).

## Overview

Each shader is compiled into a dynamic library (`.so`/`.dylib`/`.dll`) that exports a function table via the `asev_shader_get_v1()` C ABI entry point. The native render pipeline loads these shaders at runtime using `dlopen`/`LoadLibrary`.

## Available Shaders

### 1. Basic Lighting (`basic_lighting_shader.cpp`)
- **ID**: `pixelmatt.basic_lighting`
- **Type**: Face-based Lambert shading
- **Hooks**: `run_face`
- **Parameters**:
  - `ambient` (float): Base illumination (default 0.15)
  - `diffuse_strength` (float): Diffuse multiplier (default 1.0)
  - `light_dir` (vec3): Custom light direction
  - `use_custom_light` (bool): Override scene lights

### 2. Dominant Face (`dominant_face_shader.cpp`)
- **ID**: `pixelmatt.dominant_face`
- **Type**: TLR priority projected shading
- **Hooks**: `run_voxel`
- **Parameters**:
  - `ambient` (float): Base illumination (default 0.2)
  - `diffuse_strength` (float): Diffuse multiplier (default 0.8)
  - `tint` (color): RGBA color tint (default white)
- **Priority Order**: Top > Left > Right > Front > Back > Bottom

## Building

### Option 1: CMake (Recommended)
```bash
cd render/shaders
mkdir build && cd build
cmake ..
cmake --build .
cmake --install .
```

This will compile both shaders and install them to `AseVoxel/render/bin/`.

### Option 2: Makefile (Quick Build)
```bash
cd render/shaders
make
```

This will compile both shaders directly to `../../bin/`.

### Platform Notes

**Linux**:
- Produces `libasev_shader_*.so`
- Requires: `g++` or `clang++` with `-std=c++17`

**macOS**:
- Produces `libasev_shader_*.dylib`
- Requires: Xcode Command Line Tools

**Windows**:
- Produces `libasev_shader_*.dll`
- Requires: MinGW-w64 or MSVC with C++17 support
- For MSVC, use CMake with Visual Studio generator

## API Compliance

All shaders follow the **Native Shader API v1** specification:

1. **Entry Point**: `extern "C" const asev_shader_v1_t* asev_shader_get_v1(void)`
2. **Function Table**: Provides metadata, lifecycle, and execution hooks
3. **API Version**: Returns `{1, 0, 0}` from `api_version()`
4. **Parameter Schema**: Uses typed `asev_param_def_t` array
5. **Instance State**: Heap-allocated via `create()`, freed via `destroy()`

## Creating New Shaders

To add a new shader:

1. **Create** `my_shader.cpp` based on existing examples
2. **Implement** function table with required hooks:
   - `api_version()` - Return `{1, 0, 0}`
   - `shader_id()` - Unique identifier (e.g., `"vendor.shader_name"`)
   - `display_name()` - Human-readable name
   - `params_schema()` - Parameter definitions
   - `create()` / `destroy()` - Instance lifecycle
   - `set_param()` - Parameter updates
   - Choose execution hooks:
     - `run_voxel()` - Per-voxel processing (dominant face, voxel AO)
     - `run_face()` - Per-face processing (Lambert, Phong)
     - `run_image()` - Post-processing (fog, bloom, outlines)
3. **Export** `asev_shader_get_v1()` with C linkage
4. **Add** to `CMakeLists.txt` or `Makefile`
5. **Build** and test

## Testing

Test individual shader compilation:
```bash
make test  # Syntax check without linking
```

Test shader loading (requires native loader):
```bash
# From Lua console in Aseprite
local loader = require("render.native_shader_loader")
loader.scan_directory("bin/")
print(loader.list_shaders())
```

## Integration

Shaders are loaded by `render/native_shader_loader.cpp` and consumed by:
- `render/shader_stack.lua` - Shader composition layer
- `render/geometry_pipeline.lua` - Geometry dispatch
- `core/viewer.lua` - Main render coordinator

## Troubleshooting

**Symbol not found: asev_shader_get_v1**
- Ensure `extern "C"` linkage is used
- Check that function is not static
- Verify with: `nm -D libasev_shader_*.so | grep asev`

**API version mismatch**
- Shader returns `{1, 0, 0}` from `api_version()`
- Loader expects `ASEV_SHADER_API_VERSION == 1`
- Update shader if API has been incremented

**Segfault on load**
- Check that all function pointers in table are non-NULL (or explicitly NULL if unused)
- Verify instance state is properly initialized in `create()`
- Use `gdb` or `lldb` to trace crash location

## License

See `LICENSE` in project root.
