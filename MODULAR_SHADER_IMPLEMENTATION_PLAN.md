# AseVoxel Modular Shader System - Master Implementation Plan

**Date:** November 15, 2025  
**Version:** 1.1  
**Scope:** Complete native shader integration with Lua pipeline parity

---

## Revision History

**v1.1 (November 15, 2025):**
- **NEW Phase 0:** Windows dynamic path resolution using `debug.getinfo()`
- **NEW Phase 1:** Visibility culling with rotation bucketing and caching
- Updated shader invocation to use pre-computed visibility data from Lua
- Changed data structure to per-face colors (Option B)
- Modified testing to use Lua 5.4 with `tryRequire` pattern
- Clarified visibility strategy: Global visible faces (1-3) + per-voxel hidden faces
- Added 8 phases total (was 7), timeline now 25-34 days (was 21-28)

**v1.0 (November 15, 2025):**
- Initial comprehensive implementation plan
- 7 phases covering API extension through advanced features

---

## Executive Summary

This plan unifies the native shader system (C++ compiled shaders) with the Lua shader pipeline to achieve:

1. **Pipeline Parity:** Native shaders produce pixel-perfect identical output to Lua shaders
2. **Modular Architecture:** asevoxel_native.cpp loads and orchestrates native shader modules
3. **Testing Infrastructure:** Comprehensive test shim that simulates Aseprite environment
4. **Data Interchange:** JSON-based model export/import for testing and debugging

---

## Current State Analysis

### ✅ What We Have

**Native Shaders (C++):**
- `render/shaders/lighting/basic.cpp` - Lambert lighting with ambient
- `render/shaders/lighting/dynamic.cpp` - Phong lighting with specular
- `render/shaders/fx/faceshade.cpp` - Face-based coloring (partial)
- API: `native_shader_api.h` with v1.0 interface
- Loader: `native_shader_loader.cpp/.hpp` for dynamic loading

**Lua Shaders:**
- `render/shaders/lighting/basic.lua` - Camera-facing brightness modulation
- `render/shaders/lighting/dynamic.lua` - Directional light with pitch/yaw
- `render/shaders/fx/faceshade.lua` - Model-axis face brightness
- `render/shaders/fx/faceshade_camera.lua` - Camera-relative face brightness
- Infrastructure: `shader_stack.lua` for chaining, `shader_interface.lua` for contracts

**Native Renderer:**
- `asevoxel_native.cpp` - Lua C module with `render_basic()`, `render_stack()`, `render_dynamic()`
- Proven buffer management: C++ raster → Lua string → Aseprite Image
- FxStack support for old-style face shading modules

**Test Infrastructure:**
- `render/shaders/test_host_shim.cpp` - Minimal test harness (NO shader invocation)
- Hardcoded 4×4×4 hollow cube model
- PNG output via stb_image_write

### ❌ What's Missing

**Critical Gaps:**

1. **asevoxel_native.cpp doesn't invoke native shaders**
   - render_basic/dynamic/stack use hardcoded lighting formulas
   - Native shader modules are compiled but never called
   - No integration with native_shader_loader

2. **Shader API mismatch**
   - Lua shaders: Process `shaderData.faces[]` array (multiple faces per voxel)
   - Native shaders: `run_voxel()` returns single color (no per-face support)
   - FaceShade requires per-face colors but API doesn't support it

3. **Test shim doesn't test shaders**
   - Loads shaders via loader but never calls `run_voxel()`
   - Hardcoded Lambert lighting instead of shader execution
   - Not representative of Lua pipeline behavior

4. **No pipeline parity validation**
   - No test comparing Lua vs Native shader output
   - No pixel-diff testing infrastructure
   - No visual regression suite

5. **Data interchange missing**
   - No model export from AseVoxel to JSON
   - No model import in test shim
   - Manual test data creation required

---

## Architecture Vision

### Data Flow (Target State)

```
┌────────────────────────────────────────────────────────────────┐
│ ASEPRITE ENVIRONMENT                                           │
│                                                                │
│  Lua: preview_renderer.lua                                    │
│    ↓                                                           │
│  Lua: visibility_culling.lua (cache visible faces per model) │
│    ↓                                                           │
│  Lua: shader_stack.lua (Lua shaders OR native call)          │
│    ↓                                                           │
│  C++: asevoxel_native.cpp::render_stack()                    │
│    ↓                                                           │
│  C++: native_shader_loader (load .so shaders)                │
│    ↓                                                           │
│  C++: libnative_shader_*.so (compiled shaders)               │
│    ↓                                                           │
│  C++: rasterizer (buffer → Lua string)                       │
│    ↓                                                           │
│  Lua: Image{fromFile=pixels}                                 │
└────────────────────────────────────────────────────────────────┘

┌────────────────────────────────────────────────────────────────┐
│ TEST SHIM ENVIRONMENT                                          │
│                                                                │
│  C++: test_integration_shim (standalone executable)           │
│    ↓                                                           │
│  C++: Simulated Lua environment (mock tables, global state)  │
│    ↓                                                           │
│  C++: asevoxel_native entry points (render_stack, etc.)      │
│    ↓                                                           │
│  C++: native_shader_loader + libnative_shader_*.so           │
│    ↓                                                           │
│  C++: PNG export OR Lua string output                        │
└────────────────────────────────────────────────────────────────┘
```

### Key Principle: Shader Invocation Contract

**Visibility Culling Strategy:**
```lua
-- Global model visible faces (rotation-dependent):
-- - 1 face visible: Front view (0° or 180°)
-- - 2 faces visible: 45° profile views
-- - 3 faces visible: All other rotations (default isometric)

-- Per-voxel occlusion data:
-- Store which of the global visible faces are HIDDEN for each voxel
-- (due to neighboring voxels blocking them)

local visibilityCache = {
  [model_hash] = {
    [rotation_bucket] = {
      globalVisibleFaces = {"front", "top", "right"},  -- Max 3
      voxels = {
        [{x,y,z}] = {
          hiddenFaces = {"top"},  -- Max 2 (if 3 hidden, voxel not visible)
          faces = {
            {name="front", color=Color(...), normal={0,0,1}},
            {name="right", color=Color(...), normal={1,0,0}}
          }
        }
      }
    }
  }
}
```

**Lua Pipeline (preview_renderer.lua:1245):**
```lua
-- ONE shader call per voxel, processes ALL VISIBLE faces
params._shaderBatchResults = batchProcessShaderStack(
  faceBase,            -- { faceName → baseColor } (only visible faces)
  faceNormalsForShader, -- { faceName → normal } (only visible faces)
  params, 
  voxel_position
)

-- Result: { faceName → processedColor }
```

**Native Pipeline (MUST MATCH):**
```cpp
// For each visible voxel
for (auto& voxel : visible_voxels) {
    // Build faces array (only visible faces, 1-3 per voxel)
    std::vector<native_face_data_t> faces;
    for (const auto& face_data : voxel.faces) {
        faces.push_back({
            .x = voxel.x,
            .y = voxel.y,
            .z = voxel.z,
            .face_name = face_data.name.c_str(),  // "front", "back", etc.
            .normal = {face_data.normal.x, face_data.normal.y, face_data.normal.z},
            .base_rgba = {face_data.color.r, face_data.color.g, face_data.color.b, face_data.color.a}
        });
    }
    
    // Call shader ONCE per voxel with all visible faces
    shader->run_voxel_batch(instance, &ctx, faces.data(), faces.size(), out_colors);
    
    // Cache results
    for (int i = 0; i < faces.size(); i++) {
        cache[{voxel.pos, faces[i].face_name}] = {
            out_colors[i*4], out_colors[i*4+1], out_colors[i*4+2], out_colors[i*4+3]
        };
    }
}

// Render faces using cached colors
```

---

## Phase 0: Windows Path Resolution & Testing Infrastructure

**Goal:** Fix hardcoded Windows paths in nativebridge.lua and establish proper testing patterns

### Tasks

#### 0.1 Dynamic Extension Path Detection

**File:** `render/native_bridge.lua` (line 71)

**Problem:** Hardcoded user-specific path prevents portability:
```lua
if isWin then
  ok, nativeBridge._mod = pcall(package.loadlib(
    "C:/Users/matia/AppData/Roaming/Aseprite/extensions/asevoxel-viewer/asevoxel_native.dll",
    "luaopen_asevoxel_native"))
  nativeBridge._loadedPath = "C:/Users/matia/AppData/Roaming/Aseprite/extensions/asevoxel-viewer/asevoxel_native.dll"
end
```

**Solution:** Use `debug.getinfo()` to find extension directory dynamically:

```lua
-- Get extension installation directory
local function getExtensionDir()
  local info = debug.getinfo(1, "S")
  if info and info.source then
    local source = info.source:sub(2)  -- Remove leading '@'
    local dir = source:match("(.*/)")  -- Extract directory
    if dir then
      return dir:gsub("/render/native_bridge%.lua$", "")  -- Go to extension root
    end
  end
  return nil
end

-- Try to load native module
if isWin then
  local extDir = getExtensionDir()
  if extDir then
    local dllPath = extDir .. "/asevoxel_native.dll"
    ok, nativeBridge._mod = pcall(package.loadlib(dllPath, "luaopen_asevoxel_native"))
    if ok then
      nativeBridge._loadedPath = dllPath
      print("[nativeBridge] Loaded from: " .. dllPath)
    else
      print("[nativeBridge] WARNING: Failed to load " .. dllPath)
    end
  else
    print("[nativeBridge] WARNING: Could not determine extension directory")
  end
  
  -- No hardcoded user-specific fallbacks
end
```

**Rationale:**
- Works for any Windows user installation
- Follows existing pattern already used for Lua path resolution
- Maintains compatibility with manual testing outside Aseprite

#### 0.2 Update Testing Pattern

**File:** Phase 1 Task 1.4 Testing section

**Changes:**

```bash
# Test with Lua 5.4 (matches Aseprite's sandbox)
# Use tryRequire pattern from nativebridge.lua

# Create test script: test_native_loading.lua
cat > test_native_loading.lua << 'EOF'
-- Simulate Aseprite's tryRequire behavior
local function tryRequire(modname)
  local ok, result = pcall(require, modname)
  if ok then
    return result
  else
    print("WARNING: " .. tostring(result))
    return nil
  end
end

-- Determine native module path (similar to nativebridge.lua)
local function getNativeModulePath()
  local info = debug.getinfo(1, "S")
  if info and info.source then
    local source = info.source:sub(2)
    local dir = source:match("(.*/)")
    if dir then
      return dir .. "bin/asevoxel_native"
    end
  end
  return "./bin/asevoxel_native"
end

-- Load native module
package.cpath = package.cpath .. ";./bin/?.so;./bin/?.dll"
local nativePath = getNativeModulePath()
local native = tryRequire("asevoxel_native")

if not native then
  print("FAIL: Could not load native module")
  os.exit(1)
end

-- Test shader loading
local params = {
  width = 64,
  height = 64,
  nativeShaderDir = "./bin",
  shaderStack = {
    lighting = {{id = "pixelmatt.basic", enabled = true, params = {}}}
  }
}

local result = native.render_stack({}, params)
if result then
  print("SUCCESS: Native module loaded and render_stack callable")
  print("  Module path: " .. (native._loadedPath or "unknown"))
  print("  Result dimensions: " .. result.width .. "x" .. result.height)
else
  print("FAIL: render_stack returned nil")
  os.exit(1)
end
EOF

# Run with Lua 5.4
lua5.4 test_native_loading.lua

# Expected output:
# [nativeBridge] Loaded from: /path/to/extension/bin/asevoxel_native.so
# [asevoxel_native] Loaded 3 native shaders from ./bin
# SUCCESS: Native module loaded and render_stack callable
#   Module path: /path/to/extension/bin/asevoxel_native.so
#   Result dimensions: 64x64
```

**Testing:**
```bash
# Test 1: Verify dynamic path resolution on Windows
# (On Windows machine)
cd /c/Users/SomeOtherUser/AppData/Roaming/Aseprite/extensions/asevoxel-viewer
lua5.4 test_native_loading.lua
# Should succeed without hardcoded path

# Test 2: Verify Lua 5.4 compatibility
lua5.4 --version
# Should show: Lua 5.4.x

# Test 3: Verify tryRequire pattern
lua5.4 -e "local ok, mod = pcall(require, 'nonexistent'); print('Pattern works:', ok == false)"
# Should print: Pattern works: true
```

---

## Phase 1: Visibility Culling & Face Management

**Goal:** Implement rotation-aware visibility culling with per-face color management

### Tasks

#### 1.1 Visibility Culling Module (Lua)

**File:** `render/visibility_culling.lua` (NEW)

**Purpose:** Cache visible faces per rotation bucket, manage per-voxel occlusion

```lua
local visibilityCulling = {}

-- Rotation bucketing: Group similar rotations to reuse culling data
-- Bucket size: 5° increments to balance cache hits vs accuracy
local ROTATION_BUCKET_SIZE = 5

local function bucketRotation(xRot, yRot, zRot)
  local xBucket = math.floor(xRot / ROTATION_BUCKET_SIZE) * ROTATION_BUCKET_SIZE
  local yBucket = math.floor(yRot / ROTATION_BUCKET_SIZE) * ROTATION_BUCKET_SIZE
  local zBucket = math.floor(zRot / ROTATION_BUCKET_SIZE) * ROTATION_BUCKET_SIZE
  return string.format("%d,%d,%d", xBucket, yBucket, zBucket)
end

-- Hash model geometry for cache key
local function hashModel(voxels)
  local hash = 0
  for _, v in ipairs(voxels) do
    -- Simple hash: XOR of voxel coordinates
    hash = hash ~ (v.x * 73856093) ~ (v.y * 19349663) ~ (v.z * 83492791)
  end
  return hash
end

-- Determine global visible faces for rotation
-- Returns 1-3 face names based on viewing angle
local function getGlobalVisibleFaces(xRot, yRot, zRot)
  -- Normalize rotations to [0, 360)
  xRot = xRot % 360
  yRot = yRot % 360
  
  local faces = {}
  
  -- Determine primary viewing direction
  if math.abs(yRot) < 5 or math.abs(yRot - 180) < 5 then
    -- Front or back view (1 face)
    if yRot < 90 or yRot > 270 then
      table.insert(faces, "front")
    else
      table.insert(faces, "back")
    end
  elseif math.abs(yRot - 45) < 5 or math.abs(yRot - 135) < 5 or
         math.abs(yRot - 225) < 5 or math.abs(yRot - 315) < 5 then
    -- 45° profile view (2 faces)
    if yRot > 315 or yRot < 45 then
      table.insert(faces, "front")
      table.insert(faces, "right")
    elseif yRot >= 45 and yRot < 135 then
      table.insert(faces, "right")
      table.insert(faces, "back")
    elseif yRot >= 135 and yRot < 225 then
      table.insert(faces, "back")
      table.insert(faces, "left")
    else
      table.insert(faces, "left")
      table.insert(faces, "front")
    end
  else
    -- Isometric or oblique view (3 faces)
    -- Determine which 3 faces based on quadrant
    if yRot >= 0 and yRot < 90 then
      table.insert(faces, "front")
      table.insert(faces, "right")
      table.insert(faces, "top")
    elseif yRot >= 90 and yRot < 180 then
      table.insert(faces, "right")
      table.insert(faces, "back")
      table.insert(faces, "top")
    elseif yRot >= 180 and yRot < 270 then
      table.insert(faces, "back")
      table.insert(faces, "left")
      table.insert(faces, "top")
    else
      table.insert(faces, "left")
      table.insert(faces, "front")
      table.insert(faces, "top")
    end
  end
  
  return faces
end

-- Check if face is occluded by neighboring voxel
local function isFaceOccluded(voxels, voxelMap, x, y, z, faceName)
  local offsets = {
    front  = {0, 0, -1},
    back   = {0, 0, 1},
    left   = {-1, 0, 0},
    right  = {1, 0, 0},
    top    = {0, 1, 0},
    bottom = {0, -1, 0}
  }
  
  local offset = offsets[faceName]
  if not offset then return false end
  
  local neighborKey = string.format("%d,%d,%d", 
    x + offset[1], y + offset[2], z + offset[3])
  
  -- Face is occluded if neighbor exists
  return voxelMap[neighborKey] ~= nil
end

-- Compute visibility for model at specific rotation
function visibilityCulling.computeVisibility(voxels, xRot, yRot, zRot)
  local globalFaces = getGlobalVisibleFaces(xRot, yRot, zRot)
  
  -- Build voxel lookup map for occlusion testing
  local voxelMap = {}
  for _, v in ipairs(voxels) do
    local key = string.format("%d,%d,%d", v.x, v.y, v.z)
    voxelMap[key] = v
  end
  
  -- Compute per-voxel visible faces
  local result = {
    globalVisibleFaces = globalFaces,
    voxels = {}
  }
  
  for _, v in ipairs(voxels) do
    local voxelData = {
      x = v.x,
      y = v.y,
      z = v.z,
      hiddenFaces = {},
      faces = {}
    }
    
    -- Check each global face for occlusion
    for _, faceName in ipairs(globalFaces) do
      if isFaceOccluded(voxels, voxelMap, v.x, v.y, v.z, faceName) then
        table.insert(voxelData.hiddenFaces, faceName)
      else
        -- Face is visible, create face data
        local normal = {0, 0, 0}
        if faceName == "front" then normal = {0, 0, 1}
        elseif faceName == "back" then normal = {0, 0, -1}
        elseif faceName == "left" then normal = {-1, 0, 0}
        elseif faceName == "right" then normal = {1, 0, 0}
        elseif faceName == "top" then normal = {0, 1, 0}
        elseif faceName == "bottom" then normal = {0, -1, 0}
        end
        
        table.insert(voxelData.faces, {
          name = faceName,
          color = v.color,  -- Initially same as voxel color
          normal = normal
        })
      end
    end
    
    -- Only include voxel if it has visible faces
    if #voxelData.faces > 0 then
      table.insert(result.voxels, voxelData)
    end
  end
  
  return result
end

-- Cache management
local cache = {}

function visibilityCulling.getCachedVisibility(voxels, xRot, yRot, zRot)
  local modelHash = hashModel(voxels)
  local rotBucket = bucketRotation(xRot, yRot, zRot)
  
  -- Check cache
  if cache[modelHash] and cache[modelHash][rotBucket] then
    return cache[modelHash][rotBucket]
  end
  
  -- Compute and cache
  local visibility = visibilityCulling.computeVisibility(voxels, xRot, yRot, zRot)
  
  if not cache[modelHash] then
    cache[modelHash] = {}
  end
  cache[modelHash][rotBucket] = visibility
  
  return visibility
end

-- Invalidate cache when model changes
function visibilityCulling.invalidateModelCache(voxels)
  local modelHash = hashModel(voxels)
  cache[modelHash] = nil
end

return visibilityCulling
```

#### 1.2 Integrate Visibility Culling into Preview Renderer

**File:** `render/preview_renderer.lua`

**Changes:**

```lua
local visibilityCulling = dofile(scriptPath .. "/visibility_culling.lua")

-- In renderPreview function, before shader processing:
local function renderPreview(model, params)
  -- ... existing parameter setup ...
  
  -- Compute visible faces (with caching)
  local visibility = visibilityCulling.getCachedVisibility(
    model,
    params.xRotation or 0,
    params.yRotation or 0,
    params.zRotation or 0
  )
  
  -- Use visibility.voxels instead of raw model
  -- Each voxel now has .faces array with per-face colors
  
  -- For each visible voxel
  for _, voxelData in ipairs(visibility.voxels) do
    -- Process shader stack for this voxel's faces
    local faceBase = {}
    local faceNormals = {}
    
    for _, faceData in ipairs(voxelData.faces) do
      faceBase[faceData.name] = faceData.color
      faceNormals[faceData.name] = faceData.normal
    end
    
    -- Call shader stack
    local shaderResults = batchProcessShaderStack(
      faceBase,
      faceNormals,
      params,
      {x = voxelData.x, y = voxelData.y, z = voxelData.z}
    )
    
    -- Update face colors with shader results
    for _, faceData in ipairs(voxelData.faces) do
      faceData.color = shaderResults[faceData.name] or faceData.color
    end
  end
  
  -- Pass visibility data to native renderer or continue with Lua rendering
  -- ...
end
```

---

## Phase 2: API Extension & Core Integration

**Goal:** Extend native shader API to support per-face processing, integrate shader loader into asevoxel_native.cpp

### Tasks

#### 2.1 Extend native_shader_api.h

**File:** `render/native_shader_api.h`

**Changes:**

```cpp
// Add face data structure
typedef struct {
    int x, y, z;           // Voxel coordinates
    const char* face_name; // "front", "back", "right", "left", "top", "bottom"
    float normal[3];       // Face normal (world space)
    unsigned char base_rgba[4]; // Base color before shading
} native_face_data_t;

// Add batch processing callback
typedef struct {
    // ... existing callbacks ...
    
    // NEW: Process multiple faces of a voxel together
    int (*run_voxel_batch)(
        void* instance,
        const native_ctx_t* ctx,
        const native_face_data_t* faces, // Array of faces
        int num_faces,                   // Face count
        unsigned char* out_colors        // Output: num_faces * 4 bytes (RGBA)
    );
    
    // ALTERNATIVE: Per-face processing
    int (*run_face)(
        void* instance,
        const native_ctx_t* ctx,
        int x, int y, int z,
        const char* face_name,
        const float normal[3],
        const unsigned char base_rgba[4],
        unsigned char out_rgba[4]
    );
} native_shader_v1_t;
```

**Rationale:** 
- `run_voxel_batch()` matches Lua's batch processing model
- `run_face()` provides simpler per-face alternative
- Backward compatible (existing `run_voxel()` still works for lighting shaders)

#### 2.2 Update Shader Implementations

**Files:**
- `render/shaders/lighting/basic.cpp`
- `render/shaders/lighting/dynamic.cpp`
- `render/shaders/fx/faceshade.cpp`

**Changes:**

```cpp
// Example: basic.cpp
static int run_voxel_batch(
    void* instance,
    const native_ctx_t* ctx,
    const native_face_data_t* faces,
    int num_faces,
    unsigned char* out_colors
) {
    BasicLightingState* state = (BasicLightingState*)instance;
    
    // Camera direction (from context or default)
    float cam_dir[3] = {0.0f, 0.0f, 1.0f};
    // TODO: Extract from ctx->V matrix or ctx->q_view
    
    for (int i = 0; i < num_faces; i++) {
        const native_face_data_t& face = faces[i];
        unsigned char* out = &out_colors[i * 4];
        
        // Dot product: face normal · camera direction
        float ndotc = face.normal[0] * cam_dir[0] +
                     face.normal[1] * cam_dir[1] +
                     face.normal[2] * cam_dir[2];
        
        // Map [-1, 1] → [shade_intensity, light_intensity]
        float t = (ndotc + 1.0f) / 2.0f;
        float brightness = state->shade_intensity + 
                          (state->light_intensity - state->shade_intensity) * t;
        float factor = brightness / 100.0f;
        
        // Apply to base color
        out[0] = (unsigned char)(face.base_rgba[0] * factor);
        out[1] = (unsigned char)(face.base_rgba[1] * factor);
        out[2] = (unsigned char)(face.base_rgba[2] * factor);
        out[3] = face.base_rgba[3];
    }
    
    return 0;
}

// Update function table
static native_shader_v1_t SHADER_IFACE = {
    // ... existing ...
    run_voxel,       // Keep for backward compatibility
    run_voxel_batch, // NEW
    run_face,        // NEW (or NULL)
    // ...
};
```

**Testing:**
```bash
cd render/shaders
make clean && make
# Verify all shaders compile with new API
```

#### 2.3 Integrate Shader Loader into asevoxel_native.cpp

**File:** `asevoxel_native.cpp`

**Changes:**

```cpp
#include "render/shaders/native_shader_loader.hpp"

namespace {
    // Global shader registry (initialized once)
    static bool g_shaders_loaded = false;
    static std::string g_shader_dir;
    
    void ensure_shaders_loaded(const char* shader_dir) {
        if (!g_shaders_loaded || g_shader_dir != shader_dir) {
            int count = native_shader_loader::scan_directory(shader_dir);
            if (count > 0) {
                g_shaders_loaded = true;
                g_shader_dir = shader_dir;
                printf("[asevoxel_native] Loaded %d native shaders from %s\n", 
                       count, shader_dir);
            } else {
                fprintf(stderr, "[asevoxel_native] WARNING: No native shaders loaded\n");
            }
        }
    }
}

// Update render_stack to use native shaders
static int l_render_stack(lua_State* L) {
    // ... existing parameter extraction ...
    
    // Check if shader directory specified
    lua_getfield(L, 2, "nativeShaderDir");
    const char* shader_dir = lua_isstring(L, -1) ? lua_tostring(L, -1) : nullptr;
    lua_pop(L, 1);
    
    if (shader_dir) {
        ensure_shaders_loaded(shader_dir);
    }
    
    // Extract shader stack configuration
    lua_getfield(L, 2, "shaderStack");
    if (lua_istable(L, -1)) {
        // Parse lighting shaders
        lua_getfield(L, -1, "lighting");
        if (lua_istable(L, -1)) {
            int num_lighting = lua_rawlen(L, -1);
            for (int i = 1; i <= num_lighting; i++) {
                lua_rawgeti(L, -1, i);
                if (lua_istable(L, -1)) {
                    lua_getfield(L, -1, "id");
                    const char* shader_id = lua_tostring(L, -1);
                    lua_pop(L, 1);
                    
                    lua_getfield(L, -1, "enabled");
                    bool enabled = lua_toboolean(L, -1);
                    lua_pop(L, 1);
                    
                    if (enabled && shader_id) {
                        // Get shader interface
                        const native_shader_v1_t* shader = 
                            native_shader_loader::get_shader_interface(shader_id);
                        
                        if (shader) {
                            // Create shader instance
                            void* instance = 
                                native_shader_loader::create_shader_instance(shader_id);
                            
                            // Parse and set parameters
                            lua_getfield(L, -1, "params");
                            if (lua_istable(L, -1)) {
                                // Iterate params and call shader->set_param
                                // ... (parameter setting code) ...
                            }
                            lua_pop(L, 1);
                            
                            // Store shader + instance for execution
                            // ... (add to shader list) ...
                        }
                    }
                }
                lua_pop(L, 1);
            }
        }
        lua_pop(L, 1);
        
        // Parse FX shaders (same pattern)
        // ...
    }
    lua_pop(L, 1);
    
    // ... existing voxel iteration and rendering ...
    
    // For each unique voxel:
    //   1. Collect visible faces
    //   2. Build native_face_data_t array
    //   3. Call shader->run_voxel_batch()
    //   4. Cache results
    //   5. Use cached colors during rasterization
    
    // ... existing buffer return code ...
}
```

**Key Points:**
- Load shaders once per Lua VM (cache by directory)
- Parse `params.shaderStack` to get shader list and parameters
- Create shader instances on-demand
- Execute shaders during voxel iteration (before rasterization)

#### 2.4 Testing

**Test 1: Shader Loading (Lua 5.4 with tryRequire pattern)**
```bash
# Use the test script created in Phase 0
lua5.4 test_native_loading.lua

# Verify output shows:
# [nativeBridge] Loaded from: <dynamic_path>/bin/asevoxel_native.so
# [asevoxel_native] Loaded 3 native shaders from ./bin
# SUCCESS: Native module loaded and render_stack callable
```

**Test 2: Parameter Passing**
```lua
-- test_shader_params.lua
local native = require("asevoxel_native")

local params = {
  width = 64,
  height = 64,
  nativeShaderDir = "./bin",
  shaderStack = {
    lighting = {
      {
        id = "pixelmatt.basic",
        enabled = true,
        params = {
          lightIntensity = 75,
          shadeIntensity = 25
        }
      }
    }
  }
}

-- Add debug flag to see parameter setting
params._debug = true

local result = native.render_stack({}, params)
print("Result: ", result and "OK" or "FAIL")
```

**Test 3: Visibility Data Passing**
```lua
-- test_visibility_integration.lua
local visibilityCulling = require("render.visibility_culling")
local native = require("asevoxel_native")

-- Create test model
local voxels = {
  {x=0, y=0, z=0, color=Color(200, 50, 50, 255)},
  {x=1, y=0, z=0, color=Color(50, 200, 50, 255)},
  {x=0, y=1, z=0, color=Color(50, 50, 200, 255)}
}

-- Compute visibility
local visibility = visibilityCulling.computeVisibility(voxels, 30, 45, 0)

print("Global visible faces:", table.concat(visibility.globalVisibleFaces, ", "))
print("Visible voxels:", #visibility.voxels)

for i, vData in ipairs(visibility.voxels) do
  print(string.format("  Voxel %d (%d,%d,%d): %d faces", 
    i, vData.x, vData.y, vData.z, #vData.faces))
  for j, fData in ipairs(vData.faces) do
    print(string.format("    - %s: color=(%d,%d,%d,%d)", 
      fData.name, fData.color.red, fData.color.green, 
      fData.color.blue, fData.color.alpha))
  end
end

-- Pass to native renderer
local params = {
  width = 128,
  height = 128,
  nativeShaderDir = "./bin",
  shaderStack = {lighting = {{id = "pixelmatt.basic", enabled = true, params = {}}}},
  _visibilityData = visibility  -- NEW: Pass pre-computed visibility
}

local result = native.render_stack(visibility.voxels, params)
print("Render result: ", result and "OK" or "FAIL")
```

**Expected Output:**
```
Global visible faces: front, right, top
Visible voxels: 3
  Voxel 1 (0,0,0): 3 faces
    - front: color=(200,50,50,255)
    - right: color=(200,50,50,255)
    - top: color=(200,50,50,255)
  Voxel 2 (1,0,0): 2 faces
    - right: color=(50,200,50,255)
    - top: color=(50,200,50,255)
  Voxel 3 (0,1,0): 2 faces
    - front: color=(50,50,200,255)
    - top: color=(50,50,200,255)
[asevoxel_native] Loaded 3 native shaders from ./bin
[asevoxel_native] Processing 3 voxels with visibility data
[pixelmatt.basic] run_voxel_batch: 3 faces
[pixelmatt.basic] run_voxel_batch: 2 faces
[pixelmatt.basic] run_voxel_batch: 2 faces
Render result: OK
```

---

## Phase 3: Batch Processing Implementation

**Goal:** Implement per-voxel batch shader execution matching Lua pipeline with visibility data

### Tasks

#### 3.1 Parse Visibility Data from Lua

**File:** `asevoxel_native.cpp` (in render_stack)

**Purpose:** Accept pre-computed visibility data from Lua, avoiding redundant culling in C++

```cpp
namespace {
    struct FaceData {
        std::string name;  // "front", "back", etc.
        float normal[3];
        unsigned char color[4];
    };
    
    struct VoxelWithFaces {
        int x, y, z;
        std::vector<FaceData> faces;
        std::vector<unsigned char> shader_colors; // Cache for shader output
    };
}

// In render_stack:
static int l_render_stack(lua_State* L) {
    // ... existing parameter extraction ...
    
    // NEW: Check for visibility data
    std::vector<VoxelWithFaces> voxels_with_visibility;
    
    lua_getfield(L, 2, "_visibilityData");
    bool has_visibility = lua_istable(L, -1);
    
    if (has_visibility) {
        // Parse visibility data from Lua
        lua_getfield(L, -1, "voxels");
        if (lua_istable(L, -1)) {
            int num_voxels = lua_rawlen(L, -1);
            voxels_with_visibility.reserve(num_voxels);
            
            for (int i = 1; i <= num_voxels; i++) {
                lua_rawgeti(L, -1, i);
                if (lua_istable(L, -1)) {
                    VoxelWithFaces voxel;
                    
                    // Extract voxel coordinates
                    lua_getfield(L, -1, "x");
                    voxel.x = lua_tointeger(L, -1);
                    lua_pop(L, 1);
                    
                    lua_getfield(L, -1, "y");
                    voxel.y = lua_tointeger(L, -1);
                    lua_pop(L, 1);
                    
                    lua_getfield(L, -1, "z");
                    voxel.z = lua_tointeger(L, -1);
                    lua_pop(L, 1);
                    
                    // Extract faces array
                    lua_getfield(L, -1, "faces");
                    if (lua_istable(L, -1)) {
                        int num_faces = lua_rawlen(L, -1);
                        voxel.faces.reserve(num_faces);
                        
                        for (int j = 1; j <= num_faces; j++) {
                            lua_rawgeti(L, -1, j);
                            if (lua_istable(L, -1)) {
                                FaceData face;
                                
                                // Face name
                                lua_getfield(L, -1, "name");
                                face.name = lua_tostring(L, -1);
                                lua_pop(L, 1);
                                
                                // Normal
                                lua_getfield(L, -1, "normal");
                                if (lua_istable(L, -1)) {
                                    lua_rawgeti(L, -1, 1); face.normal[0] = lua_tonumber(L, -1); lua_pop(L, 1);
                                    lua_rawgeti(L, -1, 2); face.normal[1] = lua_tonumber(L, -1); lua_pop(L, 1);
                                    lua_rawgeti(L, -1, 3); face.normal[2] = lua_tonumber(L, -1); lua_pop(L, 1);
                                }
                                lua_pop(L, 1);
                                
                                // Color
                                lua_getfield(L, -1, "color");
                                if (lua_isuserdata(L, -1)) {
                                    // Aseprite Color object
                                    Color* c = (Color*)lua_touserdata(L, -1);
                                    face.color[0] = c->red;
                                    face.color[1] = c->green;
                                    face.color[2] = c->blue;
                                    face.color[3] = c->alpha;
                                }
                                lua_pop(L, 1);
                                
                                voxel.faces.push_back(face);
                            }
                            lua_pop(L, 1);
                        }
                    }
                    lua_pop(L, 1);
                    
                    voxels_with_visibility.push_back(voxel);
                }
                lua_pop(L, 1);
            }
        }
        lua_pop(L, 1);
    }
    lua_pop(L, 1);
    
    // Use voxels_with_visibility for rendering...
}
```

#### 3.2 Shader Execution Loop

```cpp
// Phase 2: Execute shaders for each voxel with pre-computed visibility
for (auto& voxel : voxels_with_visibility) {
    int num_faces = voxel.faces.size();
    if (num_faces == 0) continue;
    
    // Build native face data array
    std::vector<native_face_data_t> native_faces(num_faces);
    for (int i = 0; i < num_faces; i++) {
        const FaceData& face = voxel.faces[i];
        native_faces[i].x = voxel.x;
        native_faces[i].y = voxel.y;
        native_faces[i].z = voxel.z;
        native_faces[i].face_name = face.name.c_str();
        memcpy(native_faces[i].normal, face.normal, sizeof(float) * 3);
        memcpy(native_faces[i].base_rgba, face.color, 4);
    }
    
    // Allocate output buffer for this voxel
    voxel.shader_colors.resize(num_faces * 4);
    unsigned char* current_colors = voxel.shader_colors.data();
    
    // Initialize with base colors
    for (int i = 0; i < num_faces; i++) {
        memcpy(&current_colors[i * 4], voxel.faces[i].color, 4);
    }
    
    // Execute lighting shader stack
    for (const auto& shader_entry : lighting_shaders) {
        if (shader_entry.shader->run_voxel_batch) {
            // Update face data with current colors (for chaining)
            for (int i = 0; i < num_faces; i++) {
                memcpy(native_faces[i].base_rgba, &current_colors[i * 4], 4);
            }
            
            // Execute shader batch
            shader_entry.shader->run_voxel_batch(
                shader_entry.instance,
                &ctx,
                native_faces.data(),
                num_faces,
                current_colors
            );
        }
    }
    
    // Execute FX shader stack
    for (const auto& shader_entry : fx_shaders) {
        if (shader_entry.shader->run_voxel_batch) {
            // Update face data
            for (int i = 0; i < num_faces; i++) {
                memcpy(native_faces[i].base_rgba, &current_colors[i * 4], 4);
            }
            
            // Execute shader
            shader_entry.shader->run_voxel_batch(
                shader_entry.instance,
                &ctx,
                native_faces.data(),
                num_faces,
                current_colors
            );
        }
    }
}
```

#### 3.3 Render with Cached Colors

```cpp
// Phase 3: Rasterize faces using shader-computed colors
for (const auto& voxel : voxels_with_visibility) {
    for (int i = 0; i < voxel.faces.size(); i++) {
        const FaceData& face = voxel.faces[i];
        unsigned char* color = &voxel.shader_colors[i * 4];
        
        // Build quad vertices for this face
        std::array<Vec3, 4> vertices;
        build_face_quad(voxel.x, voxel.y, voxel.z, face.name, voxel_size, vertices);
        
        // Transform to screen space
        std::array<Vec2, 4> screen_pts;
        for (int v = 0; v < 4; v++) {
            screen_pts[v] = project_to_screen(vertices[v], mvp_matrix, width, height);
        }
        
        // Rasterize quad with shader color
        rasterQuad(screen_pts, color, buffer, width, height);
    }
}
```

#### 3.4 Testing

**Test 1: Visibility Data Parsing**
```cpp
// Add debug output in l_render_stack:
if (has_visibility) {
    printf("[asevoxel_native] Parsing visibility data...\n");
    printf("  Visible voxels: %zu\n", voxels_with_visibility.size());
    
    for (const auto& voxel : voxels_with_visibility) {
        printf("  Voxel (%d,%d,%d): %zu faces\n", 
               voxel.x, voxel.y, voxel.z, voxel.faces.size());
        for (const auto& face : voxel.faces) {
            printf("    - %s: normal=(%.2f,%.2f,%.2f) color=(%d,%d,%d,%d)\n",
                   face.name.c_str(),
                   face.normal[0], face.normal[1], face.normal[2],
                   face.color[0], face.color[1], face.color[2], face.color[3]);
        }
    }
}
```

**Test 2: Shader Invocation with Visibility**
```cpp
// In shader run_voxel_batch:
printf("[%s] Processing voxel (%d,%d,%d) with %d faces:\n",
       shader_id(), faces[0].x, faces[0].y, faces[0].z, num_faces);
for (int i = 0; i < num_faces; i++) {
    printf("  Face %d: %s, normal=(%.2f,%.2f,%.2f)\n",
           i, faces[i].face_name, 
           faces[i].normal[0], faces[i].normal[1], faces[i].normal[2]);
}
```

**Test 3: End-to-End Visibility Pipeline**
```bash
# Run complete pipeline test from Phase 2
lua5.4 test_visibility_integration.lua

# Verify shader is called correct number of times
# For 3 voxels with visibility: should see 3 shader calls
```

**Expected Output:**
```
Global visible faces: front, right, top
Visible voxels: 3
  Voxel 1 (0,0,0): 3 faces
    - front: color=(200,50,50,255)
    - right: color=(200,50,50,255)
    - top: color=(200,50,50,255)
  Voxel 2 (1,0,0): 2 faces
    - right: color=(50,200,50,255)
    - top: color=(50,200,50,255)
  Voxel 3 (0,1,0): 2 faces
    - front: color=(50,50,200,255)
    - top: color=(50,50,200,255)
[asevoxel_native] Loaded 3 native shaders from ./bin
[asevoxel_native] Parsing visibility data...
  Visible voxels: 3
  Voxel (0,0,0): 3 faces
    - front: normal=(0.00,0.00,1.00) color=(200,50,50,255)
    - right: normal=(1.00,0.00,0.00) color=(200,50,50,255)
    - top: normal=(0.00,1.00,0.00) color=(200,50,50,255)
  Voxel (1,0,0): 2 faces
    - right: normal=(1.00,0.00,0.00) color=(50,200,50,255)
    - top: normal=(0.00,1.00,0.00) color=(50,200,50,255)
  Voxel (0,1,0): 2 faces
    - front: normal=(0.00,0.00,1.00) color=(50,50,200,255)
    - top: normal=(0.00,1.00,0.00) color=(50,50,200,255)
[pixelmatt.basic] Processing voxel (0,0,0) with 3 faces:
  Face 0: front, normal=(0.00,0.00,1.00)
  Face 1: right, normal=(1.00,0.00,0.00)
  Face 2: top, normal=(0.00,1.00,0.00)
[pixelmatt.basic] Processing voxel (1,0,0) with 2 faces:
  Face 0: right, normal=(1.00,0.00,0.00)
  Face 1: top, normal=(0.00,1.00,0.00)
[pixelmatt.basic] Processing voxel (0,1,0) with 2 faces:
  Face 0: front, normal=(0.00,0.00,1.00)
  Face 1: top, normal=(0.00,1.00,0.00)
Render result: OK
```

---

## Phase 4: Integration Test Shim

**Goal:** Create comprehensive test harness that simulates Aseprite environment

### Tasks

#### 3.1 Create test_integration_shim.cpp

**File:** `render/shaders/test_integration_shim.cpp`

**Purpose:** Standalone executable that:
1. Simulates Lua environment (without Lua VM)
2. Loads asevoxel_native.so as shared library
3. Calls render_stack with simulated data
4. Exports results as PNG

**Architecture:**

```cpp
// Mock Lua C API (minimal subset needed by asevoxel_native)
extern "C" {
    struct lua_State {
        std::unordered_map<std::string, std::any> globals;
        std::vector<std::any> stack;
        int top = 0;
    };
    
    lua_State* luaL_newstate();
    void lua_close(lua_State* L);
    int lua_gettop(lua_State* L);
    void lua_settop(lua_State* L, int idx);
    // ... minimal Lua API implementation ...
}

// Load asevoxel_native.so dynamically
void* native_handle = dlopen("./bin/asevoxel_native.so", RTLD_LAZY);
auto luaopen_asevoxel_native = (int(*)(lua_State*))dlsym(native_handle, "luaopen_asevoxel_native");

// Create mock Lua state
lua_State* L = luaL_newstate();
luaopen_asevoxel_native(L);

// Build voxel table
lua_newtable(L);
for (const auto& voxel : model) {
    lua_newtable(L);
    lua_pushnumber(L, voxel.x); lua_setfield(L, -2, "x");
    lua_pushnumber(L, voxel.y); lua_setfield(L, -2, "y");
    lua_pushnumber(L, voxel.z); lua_setfield(L, -2, "z");
    // ... color, etc ...
    lua_rawseti(L, -2, i+1);
}

// Build params table
lua_newtable(L);
lua_pushinteger(L, 640); lua_setfield(L, -2, "width");
lua_pushinteger(L, 480); lua_setfield(L, -2, "height");
lua_pushstring(L, "./bin"); lua_setfield(L, -2, "nativeShaderDir");

// Build shaderStack table
lua_newtable(L);
// ... lighting and fx arrays ...
lua_setfield(L, -2, "shaderStack");

// Call render_stack
lua_getglobal(L, "asevoxel_native");
lua_getfield(L, -1, "render_stack");
lua_pushvalue(L, -3); // voxels
lua_pushvalue(L, -3); // params
int result = lua_pcall(L, 2, 1, 0);

// Extract result
lua_getfield(L, -1, "pixels");
size_t len;
const char* pixels = lua_tolstring(L, -1, &len);
lua_getfield(L, -2, "width");
int width = lua_tointeger(L, -1);
lua_getfield(L, -3, "height");
int height = lua_tointeger(L, -1);

// Write PNG
stbi_write_png("output.png", width, height, 4, pixels, width * 4);
```

**Rationale:**
- No Lua VM dependency (faster compilation, easier debugging)
- Full control over test data
- Direct access to asevoxel_native internals via dlopen

#### 3.2 Model JSON Format

**File:** `model_format_spec.json`

```json
{
  "version": "1.0",
  "format": "asevoxel_voxel_model",
  "metadata": {
    "name": "Hollow Cube",
    "author": "Test Suite",
    "created": "2025-11-15T00:00:00Z"
  },
  "dimensions": {
    "width": 4,
    "height": 4,
    "depth": 4
  },
  "voxels": [
    {
      "x": 0, "y": 0, "z": 0,
      "color": {"r": 200, "g": 50, "b": 50, "a": 255}
    },
    {
      "x": 1, "y": 0, "z": 0,
      "color": {"r": 200, "g": 50, "b": 50, "a": 255}
    }
    // ... etc ...
  ],
  "camera": {
    "position": {"x": 10, "y": 10, "z": 10},
    "rotation": {"x": 30, "y": 45, "z": 0},
    "fov": 60,
    "orthogonal": false
  },
  "render_params": {
    "width": 640,
    "height": 480,
    "scale": 4,
    "backgroundColor": {"r": 0, "g": 0, "b": 0, "a": 0}
  },
  "shader_stack": {
    "lighting": [
      {
        "id": "pixelmatt.basic",
        "enabled": true,
        "params": {
          "lightIntensity": 70,
          "shadeIntensity": 30
        }
      }
    ],
    "fx": [
      {
        "id": "pixelmatt.faceshade",
        "enabled": false,
        "params": {}
      }
    ]
  }
}
```

#### 3.3 JSON Parser

**File:** `render/shaders/model_loader.hpp`

```cpp
#pragma once
#include <string>
#include <vector>
#include <nlohmann/json.hpp> // https://github.com/nlohmann/json

struct Voxel {
    float x, y, z;
    unsigned char r, g, b, a;
};

struct Camera {
    float pos[3];
    float rot[3]; // Euler angles in degrees
    float fov;
    bool orthogonal;
};

struct ShaderEntry {
    std::string id;
    bool enabled;
    nlohmann::json params;
};

struct VoxelModel {
    std::vector<Voxel> voxels;
    int width, height, depth;
    Camera camera;
    int render_width, render_height;
    float scale;
    unsigned char bg_color[4];
    std::vector<ShaderEntry> lighting_shaders;
    std::vector<ShaderEntry> fx_shaders;
};

VoxelModel load_model_from_json(const std::string& filepath);
void save_model_to_json(const VoxelModel& model, const std::string& filepath);
```

#### 3.4 Makefile Updates

**File:** `render/shaders/Makefile`

```makefile
TEST_INTEGRATION := ../../bin/test_integration_shim

$(TEST_INTEGRATION): test_integration_shim.cpp model_loader.cpp $(LOADER_LIB)
	@echo "Building integration test shim..."
	$(CXX) $(CXXFLAGS) -I../../thirdparty/json/include \
		test_integration_shim.cpp model_loader.cpp \
		stb_image_write_impl.cpp \
		-ldl -o $@

test-integration: $(TEST_INTEGRATION)
	@echo "Running integration tests..."
	@./$(TEST_INTEGRATION) test_models/hollow_cube.json output_native.png
	@echo "✓ Test complete: output_native.png"
```

#### 3.5 Testing

**Test 1: Load Model JSON**
```bash
cd render/shaders
make test-integration

# Expected output:
# [model_loader] Loaded 56 voxels from test_models/hollow_cube.json
# [asevoxel_native] Loaded 3 native shaders from ./bin
# [test_integration_shim] Calling render_stack...
# [test_integration_shim] Result: 640x480 image (1228800 bytes)
# [test_integration_shim] Wrote output_native.png
# ✓ Test complete: output_native.png
```

**Test 2: Compare with Lua Output**
```bash
# Generate reference image with Lua shaders
lua5.3 test_lua_render.lua test_models/hollow_cube.json output_lua.png

# Compare pixel-by-pixel
python3 compare_images.py output_lua.png output_native.png

# Expected: 0 pixels different (perfect match)
```

---

## Phase 5: Pipeline Parity Validation

**Goal:** Ensure native shaders produce identical output to Lua shaders

### Tasks

#### 4.1 Lua Reference Renderer

**File:** `test/lua_reference_renderer.lua`

```lua
-- Standalone Lua script that uses shader_stack.lua
package.path = package.path .. ";../render/?.lua;../render/shaders/?.lua"

local json = require("thirdparty.json")
local shader_stack = require("shader_stack")
local preview_renderer = require("preview_renderer")

-- Load model
local model_data = json.decode(io.open(arg[1], "r"):read("*all"))

-- Build voxel array
local voxels = {}
for _, v in ipairs(model_data.voxels) do
    table.insert(voxels, {
        x = v.x, y = v.y, z = v.z,
        color = Color(v.color.r, v.color.g, v.color.b, v.color.a)
    })
end

-- Build params
local params = {
    width = model_data.render_params.width,
    height = model_data.render_params.height,
    scale = model_data.render_params.scale,
    xRotation = model_data.camera.rotation.x,
    yRotation = model_data.camera.rotation.y,
    zRotation = model_data.camera.rotation.z,
    orthogonal = model_data.camera.orthogonal,
    shaderStack = {
        lighting = model_data.shader_stack.lighting,
        fx = model_data.shader_stack.fx
    }
}

-- Render
local image = preview_renderer.renderPreview(voxels, params)

-- Export
image:saveAs(arg[2])
print("Saved Lua reference:", arg[2])
```

#### 4.2 Pixel Diff Tool

**File:** `test/compare_images.py`

```python
#!/usr/bin/env python3
import sys
from PIL import Image
import numpy as np

def compare_images(img1_path, img2_path, tolerance=0):
    img1 = Image.open(img1_path).convert('RGBA')
    img2 = Image.open(img2_path).convert('RGBA')
    
    if img1.size != img2.size:
        print(f"ERROR: Size mismatch: {img1.size} vs {img2.size}")
        return False
    
    arr1 = np.array(img1)
    arr2 = np.array(img2)
    
    diff = np.abs(arr1.astype(int) - arr2.astype(int))
    diff_pixels = np.any(diff > tolerance, axis=2)
    num_diff = np.sum(diff_pixels)
    
    if num_diff == 0:
        print(f"✓ Perfect match: 0 pixels different")
        return True
    else:
        total_pixels = diff_pixels.size
        pct = (num_diff / total_pixels) * 100
        max_diff = np.max(diff)
        avg_diff = np.mean(diff[diff_pixels])
        
        print(f"✗ Mismatch: {num_diff}/{total_pixels} pixels ({pct:.2f}%)")
        print(f"  Max channel diff: {max_diff}")
        print(f"  Avg channel diff: {avg_diff:.2f}")
        
        # Save diff image
        diff_img = Image.fromarray((diff_pixels * 255).astype(np.uint8), mode='L')
        diff_img.save('diff_mask.png')
        print(f"  Saved diff mask: diff_mask.png")
        
        return False

if __name__ == "__main__":
    if len(sys.argv) != 3:
        print("Usage: compare_images.py <image1> <image2>")
        sys.exit(1)
    
    match = compare_images(sys.argv[1], sys.argv[2], tolerance=1)
    sys.exit(0 if match else 1)
```

#### 4.3 Test Suite

**File:** `test/run_parity_tests.sh`

```bash
#!/bin/bash
set -e

echo "=== AseVoxel Native Shader Parity Tests ==="
echo ""

MODELS_DIR="test_models"
OUTPUT_DIR="test_output"
mkdir -p "$OUTPUT_DIR"

TESTS=(
    "hollow_cube:basic_lighting"
    "hollow_cube:dynamic_lighting"
    "hollow_cube:faceshade"
    "solid_cube:basic_lighting"
    "voxel_tree:dynamic_lighting"
)

PASSED=0
FAILED=0

for TEST in "${TESTS[@]}"; do
    MODEL="${TEST%%:*}"
    SHADER="${TEST##*:}"
    
    echo "Test: $MODEL with $SHADER"
    
    # Generate Lua reference
    lua5.3 lua_reference_renderer.lua \
        "$MODELS_DIR/${MODEL}_${SHADER}.json" \
        "$OUTPUT_DIR/${MODEL}_${SHADER}_lua.png"
    
    # Generate native output
    ../bin/test_integration_shim \
        "$MODELS_DIR/${MODEL}_${SHADER}.json" \
        "$OUTPUT_DIR/${MODEL}_${SHADER}_native.png"
    
    # Compare
    if python3 compare_images.py \
        "$OUTPUT_DIR/${MODEL}_${SHADER}_lua.png" \
        "$OUTPUT_DIR/${MODEL}_${SHADER}_native.png"; then
        echo "✓ PASS"
        ((PASSED++))
    else
        echo "✗ FAIL"
        ((FAILED++))
    fi
    echo ""
done

echo "=== Results ==="
echo "Passed: $PASSED"
echo "Failed: $FAILED"

if [ $FAILED -eq 0 ]; then
    echo "✓ All tests passed!"
    exit 0
else
    echo "✗ Some tests failed"
    exit 1
fi
```

#### 4.4 Testing

```bash
cd test
./run_parity_tests.sh

# Expected output:
# === AseVoxel Native Shader Parity Tests ===
# 
# Test: hollow_cube with basic_lighting
# ✓ Perfect match: 0 pixels different
# ✓ PASS
# 
# Test: hollow_cube with dynamic_lighting
# ✓ Perfect match: 0 pixels different
# ✓ PASS
# 
# ...
# 
# === Results ===
# Passed: 5
# Failed: 0
# ✓ All tests passed!
```

---

## Phase 6: Aseprite File Support

**Goal:** Load voxel models directly from .aseprite files

### Tasks

#### 5.1 Aseprite File Parser

**File:** `render/shaders/aseprite_loader.hpp`

```cpp
#pragma once
#include <string>
#include <vector>
#include "model_loader.hpp"

// Parse .aseprite file and extract voxel model
// Assumes AseVoxel conventions:
// - Each layer = Z slice
// - Pixel (x, y) in layer z → voxel (x, y, z)
// - Transparent pixels = empty voxels
VoxelModel load_model_from_aseprite(const std::string& filepath);
```

**Implementation:**
```cpp
#include "aseprite_loader.hpp"
#include <aseprite/doc.h>

VoxelModel load_model_from_aseprite(const std::string& filepath) {
    // Use Aseprite's doc library to parse file
    aseprite::Document doc(filepath);
    
    VoxelModel model;
    model.width = doc.sprite()->width();
    model.height = doc.sprite()->height();
    model.depth = doc.sprite()->layers().size();
    
    int z = 0;
    for (const auto& layer : doc.sprite()->layers()) {
        const auto& cel = layer->cel(0); // First frame
        if (!cel) continue;
        
        const auto& image = cel->image();
        for (int y = 0; y < image->height(); y++) {
            for (int x = 0; x < image->width(); x++) {
                aseprite::color_t c = image->getPixel(x, y);
                if (aseprite::rgba_geta(c) == 0) continue; // Transparent
                
                Voxel v;
                v.x = x;
                v.y = model.height - 1 - y; // Flip Y (Aseprite is top-down)
                v.z = z;
                v.r = aseprite::rgba_getr(c);
                v.g = aseprite::rgba_getg(c);
                v.b = aseprite::rgba_getb(c);
                v.a = aseprite::rgba_geta(c);
                
                model.voxels.push_back(v);
            }
        }
        z++;
    }
    
    // Default camera and render params
    model.camera = {
        .pos = {10, 10, 10},
        .rot = {30, 45, 0},
        .fov = 60,
        .orthogonal = false
    };
    model.render_width = 640;
    model.render_height = 480;
    model.scale = 4.0f;
    
    return model;
}
```

**Note:** This requires linking against Aseprite's library, which may complicate the build. Alternative: Parse .aseprite as ZIP and extract PNG layers manually.

#### 5.2 Model Export from AseVoxel

**File:** `dialog/export_model_dialog.lua`

```lua
-- New dialog in AseVoxel UI to export current model as JSON

local exportModelDialog = {}

function exportModelDialog.show()
  local dlg = Dialog("Export Model for Testing")
  
  dlg:file{
    id = "outputPath",
    label = "Output File:",
    save = true,
    filename = "model.json",
    filetypes = {"json"}
  }
  
  dlg:check{
    id = "includeCamera",
    label = "Include Camera",
    selected = true
  }
  
  dlg:check{
    id = "includeShaders",
    label = "Include Shader Stack",
    selected = true
  }
  
  dlg:button{
    id = "export",
    text = "Export",
    onclick = function()
      local path = dlg.data.outputPath
      
      -- Get current model
      local model = AseVoxel.core.viewer.getCurrentModel()
      local params = AseVoxel.core.viewer.getRenderParams()
      
      -- Build JSON
      local data = {
        version = "1.0",
        format = "asevoxel_voxel_model",
        metadata = {
          name = app.activeSprite.filename or "Untitled",
          created = os.date("!%Y-%m-%dT%H:%M:%SZ")
        },
        dimensions = {
          width = model.bounds.width,
          height = model.bounds.height,
          depth = model.bounds.depth
        },
        voxels = {},
        camera = {},
        render_params = {},
        shader_stack = {}
      }
      
      -- Export voxels
      for _, v in ipairs(model) do
        table.insert(data.voxels, {
          x = v.x,
          y = v.y,
          z = v.z,
          color = {
            r = v.color.red,
            g = v.color.green,
            b = v.color.blue,
            a = v.color.alpha
          }
        })
      end
      
      -- Export camera
      if dlg.data.includeCamera then
        data.camera = {
          position = params.cameraPosition or {x = 10, y = 10, z = 10},
          rotation = {
            x = params.xRotation or 0,
            y = params.yRotation or 0,
            z = params.zRotation or 0
          },
          fov = params.fovDegrees or 60,
          orthogonal = params.orthogonal or false
        }
      end
      
      -- Export shader stack
      if dlg.data.includeShaders and params.shaderStack then
        data.shader_stack = {
          lighting = params.shaderStack.lighting or {},
          fx = params.shaderStack.fx or {}
        }
      end
      
      -- Write JSON
      local json = require("thirdparty.json")
      local file = io.open(path, "w")
      file:write(json.encode(data))
      file:close()
      
      app.alert("Model exported to " .. path)
      dlg:close()
    end
  }
  
  dlg:button{
    id = "cancel",
    text = "Cancel",
    onclick = function()
      dlg:close()
    end
  }
  
  dlg:show()
end

return exportModelDialog
```

#### 5.3 Integration

**File:** `main.lua` (add menu item)

```lua
local exportModelDialog = dofile(plugin_path .. "/dialog/export_model_dialog.lua")

plugin:newCommand{
  id = "asevoxel_export_model",
  title = "Export Model (JSON)...",
  group = "file_export",
  onclick = function()
    exportModelDialog.show()
  end
}
```

#### 5.4 Testing

**Test 1: Export from AseVoxel**
```
1. Open AseVoxel viewer
2. Load a sprite with voxel model
3. File → Export → Export Model (JSON)
4. Save as "my_model.json"
5. Verify JSON structure matches spec
```

**Test 2: Render Exported Model**
```bash
# With native shaders
./bin/test_integration_shim my_model.json output.png

# With Lua reference
lua5.3 test/lua_reference_renderer.lua my_model.json output_lua.png

# Compare
python3 test/compare_images.py output.png output_lua.png
```

---

## Phase 7: Production Integration

**Goal:** Enable native shaders in production AseVoxel

### Tasks

#### 6.1 Update native_bridge.lua

**File:** `render/native_bridge.lua`

```lua
-- Add shader loading support
function nativeBridge.renderWithNativeShaders(voxels, params)
  local m = mod()
  if not m or not m.render_stack then
    return nil, "native module missing render_stack"
  end
  
  -- Ensure shader directory is set
  if not params.nativeShaderDir then
    params.nativeShaderDir = app.fs.joinPath(
      app.fs.userConfigPath,
      "extensions",
      "asevoxel-viewer",
      "bin"
    )
  end
  
  -- Call native render_stack
  local ok, result = pcall(m.render_stack, voxels, params)
  
  if not ok then
    return nil, "render_stack failed: " .. tostring(result)
  end
  
  return result
end
```

#### 6.2 Update preview_renderer.lua

**File:** `render/preview_renderer.lua`

```lua
-- In renderPreview function:

-- Check if native shaders are enabled and available
local useNativeShaders = params.useNativeShaders and nativeBridge.isAvailable()

if useNativeShaders then
  local result = nativeBridge.renderWithNativeShaders(model, params)
  
  if result and result.pixels then
    -- Create Image from native buffer
    local img = Image{
      fromFile = result.pixels,
      width = result.width,
      height = result.height
    }
    
    -- Apply post-processing (outline, etc.) if needed
    if params.outline then
      img = previewRenderer.applyOutline(img, params.outlineSettings)
    end
    
    return img
  else
    -- Fallback to Lua shaders
    print("[AseVoxel] Native shaders failed, using Lua fallback")
  end
end

-- Existing Lua shader path...
```

#### 6.3 Add UI Toggle

**File:** `dialog/preview_dialog.lua`

```lua
-- In settings section:
dlg:check{
  id = "useNativeShaders",
  label = "Native Shaders",
  selected = false,
  tooltip = "Use compiled C++ shaders for faster rendering (experimental)"
}

-- Add status indicator
dlg:label{
  id = "nativeStatus",
  text = nativeBridge.isAvailable() and 
         "✓ Native available" or 
         "✗ Native not found"
}
```

#### 6.4 Testing

**Test 1: Toggle Native Shaders**
```
1. Open AseVoxel preview
2. Settings → Enable "Native Shaders"
3. Rotate model, change lighting
4. Verify rendering matches Lua shaders
5. Check console for "[asevoxel_native] Loaded N shaders"
```

**Test 2: Fallback Behavior**
```
1. Rename bin/libnative_shader_*.so to .so.bak
2. Enable "Native Shaders"
3. Verify fallback to Lua shaders
4. Check console for "Native shaders failed, using Lua fallback"
```

**Test 3: Performance Comparison**
```lua
-- In console:
local model = AseVoxel.core.viewer.getCurrentModel()
local params = AseVoxel.core.viewer.getRenderParams()

-- Lua timing
params.useNativeShaders = false
local t1 = os.clock()
local img1 = preview_renderer.renderPreview(model, params)
local lua_time = (os.clock() - t1) * 1000

-- Native timing
params.useNativeShaders = true
local t2 = os.clock()
local img2 = preview_renderer.renderPreview(model, params)
local native_time = (os.clock() - t2) * 1000

print("Lua:    " .. lua_time .. " ms")
print("Native: " .. native_time .. " ms")
print("Speedup: " .. (lua_time / native_time) .. "x")
```

**Expected:** 2-5x speedup for native shaders

---

## Phase 8: Advanced Features

**Goal:** Implement missing shader features and optimizations

### Tasks

#### 7.1 Shader Hot-Reload

**File:** `asevoxel_native.cpp`

```cpp
// Add file watcher for .so files
static std::unordered_map<std::string, time_t> g_shader_mtimes;

void check_shader_updates(const char* shader_dir) {
    DIR* dir = opendir(shader_dir);
    if (!dir) return;
    
    bool needs_reload = false;
    struct dirent* entry;
    
    while ((entry = readdir(dir)) != nullptr) {
        if (strncmp(entry->d_name, "libnative_shader_", 17) != 0) continue;
        
        std::string path = std::string(shader_dir) + "/" + entry->d_name;
        struct stat st;
        if (stat(path.c_str(), &st) == 0) {
            time_t old_mtime = g_shader_mtimes[path];
            if (old_mtime != 0 && st.st_mtime > old_mtime) {
                printf("[asevoxel_native] Shader modified: %s\n", entry->d_name);
                needs_reload = true;
            }
            g_shader_mtimes[path] = st.st_mtime;
        }
    }
    
    closedir(dir);
    
    if (needs_reload) {
        printf("[asevoxel_native] Reloading shaders...\n");
        native_shader_loader::unload_all();
        native_shader_loader::scan_directory(shader_dir);
        g_shaders_loaded = true;
    }
}

// Call in render_stack before shader execution
if (g_shaders_loaded) {
    check_shader_updates(shader_dir);
}
```

#### 7.2 Shader Profiling

```cpp
struct ShaderStats {
    std::string id;
    uint64_t total_calls = 0;
    uint64_t total_time_ns = 0;
    uint64_t total_faces = 0;
};

static std::unordered_map<std::string, ShaderStats> g_shader_stats;

// In shader execution loop:
auto start = std::chrono::high_resolution_clock::now();

shader->run_voxel_batch(instance, &ctx, faces.data(), num_faces, colors);

auto end = std::chrono::high_resolution_clock::now();
auto duration = std::chrono::duration_cast<std::chrono::nanoseconds>(end - start);

g_shader_stats[shader_id].total_calls++;
g_shader_stats[shader_id].total_time_ns += duration.count();
g_shader_stats[shader_id].total_faces += num_faces;

// Report at end of frame
for (const auto& [id, stats] : g_shader_stats) {
    double avg_time_us = (stats.total_time_ns / stats.total_calls) / 1000.0;
    double faces_per_call = (double)stats.total_faces / stats.total_calls;
    printf("[%s] %lu calls, %.2f µs/call, %.1f faces/call\n",
           id.c_str(), stats.total_calls, avg_time_us, faces_per_call);
}
```

#### 7.3 Multi-threading

```cpp
// In shader execution loop:
if (shader->parallelism_hint() > 0) {
    // Parallel execution
    #pragma omp parallel for
    for (int i = 0; i < voxel_map.size(); i++) {
        auto it = std::next(voxel_map.begin(), i);
        execute_shader_for_voxel(it->first, it->second);
    }
} else {
    // Serial execution
    for (auto& [key, data] : voxel_map) {
        execute_shader_for_voxel(key, data);
    }
}
```

---

## Testing Strategy

### Unit Tests

**File:** `test/test_native_shaders.cpp`

```cpp
#include <gtest/gtest.h>
#include "../render/shaders/native_shader_loader.hpp"

TEST(NativeShaderLoader, LoadShaders) {
    int count = native_shader_loader::scan_directory("../bin");
    EXPECT_GT(count, 0);
}

TEST(NativeShaderLoader, GetShaderInterface) {
    native_shader_loader::scan_directory("../bin");
    auto shader = native_shader_loader::get_shader_interface("pixelmatt.basic");
    ASSERT_NE(shader, nullptr);
    EXPECT_STREQ(shader->shader_id(), "pixelmatt.basic");
}

TEST(BasicShader, ProcessFaces) {
    native_shader_loader::scan_directory("../bin");
    auto shader = native_shader_loader::get_shader_interface("pixelmatt.basic");
    auto instance = native_shader_loader::create_shader_instance("pixelmatt.basic");
    
    native_face_data_t face = {
        .x = 0, .y = 0, .z = 0,
        .face_name = "front",
        .normal = {0, 0, 1},
        .base_rgba = {200, 50, 50, 255}
    };
    
    native_ctx_t ctx = {}; // Initialize with test data
    unsigned char out[4];
    
    int result = shader->run_face(instance, &ctx, 0, 0, 0, "front", 
                                  face.normal, face.base_rgba, out);
    
    EXPECT_EQ(result, 0);
    EXPECT_GT(out[0], 0); // Some color output
    
    native_shader_loader::destroy_shader_instance("pixelmatt.basic", instance);
}
```

### Integration Tests

```bash
# Run all parity tests
cd test
./run_parity_tests.sh

# Expected: 100% pass rate

# Run performance benchmarks
./run_performance_tests.sh

# Expected: Native 2-5x faster than Lua
```

### Visual Regression Tests

**File:** `test/visual_regression.sh`

```bash
#!/bin/bash

# Generate reference images (Lua)
for model in test_models/*.json; do
    name=$(basename "$model" .json)
    lua5.3 lua_reference_renderer.lua "$model" "refs/${name}.png"
done

# Generate test images (Native)
for model in test_models/*.json; do
    name=$(basename "$model" .json)
    ../bin/test_integration_shim "$model" "test/${name}.png"
done

# Compare all
for ref in refs/*.png; do
    name=$(basename "$ref")
    python3 compare_images.py "refs/$name" "test/$name"
done
```

---

## Documentation Updates

### User Documentation

**File:** `docs/native_shaders_guide.md`

- How to enable native shaders in UI
- Performance benefits
- Troubleshooting (missing .so files, version mismatches)
- Fallback behavior

### Developer Documentation

**File:** `docs/native_shader_development.md`

- Writing custom native shaders
- Building and installing shaders
- Debugging shaders
- API reference

### Migration Guide

**File:** `docs/lua_to_native_migration.md`

- Converting Lua shaders to C++
- API equivalence table
- Performance optimization tips
- Testing checklist

---

## Success Criteria

### Phase 0 ✓
- [ ] Windows path resolution using `debug.getinfo()` implemented
- [ ] nativebridge.lua loads from dynamic extension directory
- [ ] Lua 5.4 testing infrastructure established
- [ ] tryRequire pattern validated

### Phase 1 ✓
- [ ] Visibility culling module created (`visibility_culling.lua`)
- [ ] Rotation bucketing system works (5° increments)
- [ ] Global visible faces detection (1-3 faces based on rotation)
- [ ] Per-voxel occlusion culling with neighbor checking
- [ ] Cache invalidation on model changes
- [ ] Integration with preview_renderer.lua complete

### Phase 2 ✓
- [ ] Native shader API extended with `run_voxel_batch()` and `run_face()`
- [ ] All existing shaders updated to new API
- [ ] Shaders compile without errors
- [ ] Shader loader integrated into asevoxel_native.cpp
- [ ] Lua 5.4 testing with tryRequire pattern passes

### Phase 3 ✓
- [ ] Visibility data parsing from Lua to C++ implemented
- [ ] Per-face color storage in native structures
- [ ] Shader execution loop processes visible faces only
- [ ] Cached colors used during rasterization
- [ ] No crashes or memory leaks
- [ ] Debug output confirms correct face counts per voxel

### Phase 4 ✓
- [ ] test_integration_shim compiles and runs
- [ ] JSON model format documented with per-face colors
- [ ] Model loader parses JSON correctly
- [ ] PNG export works
- [ ] Visibility data can be serialized to JSON

### Phase 5 ✓
- [ ] Lua reference renderer produces correct output
- [ ] Pixel diff tool detects mismatches
- [ ] Parity test suite passes with 0 failures
- [ ] Native output matches Lua pixel-perfect
- [ ] Visibility culling produces identical results in Lua and C++

### Phase 6 ✓
- [ ] .aseprite file parser works
- [ ] Model export from AseVoxel UI includes visibility data
- [ ] Exported models load correctly
- [ ] Round-trip test passes

### Phase 7 ✓
- [ ] Native shaders toggle in UI
- [ ] Fallback to Lua works correctly
- [ ] Performance improvement measured (2-5x)
- [ ] No regressions in existing features
- [ ] Visibility cache improves performance for rotation changes

### Phase 8 ✓
- [ ] Shader hot-reload works
- [ ] Profiling data is useful
- [ ] Multi-threading improves performance
- [ ] Documentation complete
- [ ] Visibility culling profiling shows cache hit rates

---

## Timeline Estimate

**Phase 0:** 1-2 days (Windows path fix + testing setup)  
**Phase 1:** 3-4 days (Visibility culling Lua implementation)  
**Phase 2:** 3-4 days (API extension + shader loader integration)  
**Phase 3:** 4-5 days (Batch processing with visibility data)  
**Phase 4:** 3-4 days (Integration test shim)  
**Phase 5:** 2-3 days (Pipeline parity validation)  
**Phase 6:** 3-4 days (Aseprite file support)  
**Phase 7:** 2-3 days (Production integration)  
**Phase 8:** 4-5 days (Advanced features)  

**Total:** 25-34 days (4-5 weeks full-time)

---

## Risk Mitigation

### Risk 1: API Incompatibility
**Mitigation:** Maintain backward compatibility, keep `run_voxel()` for simple shaders

### Risk 2: Performance Regression
**Mitigation:** Benchmark each phase, optimize hot paths

### Risk 3: Lua VM Integration Issues
**Mitigation:** Test with multiple Lua versions (5.3, 5.4), use conservative API subset

### Risk 4: Platform Differences
**Mitigation:** Test on Linux, macOS, Windows; use platform-agnostic code

### Risk 5: Pixel Diff Failures
**Mitigation:** Allow 1-2 channel tolerance for floating-point rounding, investigate systematically

---

## Conclusion

This plan provides a complete roadmap for integrating native compiled shaders with the AseVoxel Lua pipeline. The phased approach ensures:

1. **Incremental progress** with testable milestones
2. **Backward compatibility** with existing Lua shaders
3. **Performance gains** through C++ optimization
4. **Robust testing** with parity validation
5. **Production readiness** with fallback mechanisms

The result will be a modular shader system where Lua and native shaders coexist, allowing users to choose performance vs. flexibility based on their needs.
