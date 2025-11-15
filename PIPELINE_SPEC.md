# PipelineSpec Implementation Guide

> **Companion to:** RENDER_REFACTOR_PROPOSAL.md  
> **Status:** Reference implementation  
> **Date:** 2025-11-06

---

## Overview

`PipelineSpec` is the unified configuration object that defines how AseVoxel renders a frame. It's shared between Lua and C++ via JSON serialization, enabling seamless cross-language pipeline configuration.

---

## 1. JSON Schema

### 1.1 Complete Schema

```json
{
  "$schema": "http://json-schema.org/draft-07/schema#",
  "title": "AseVoxel PipelineSpec",
  "type": "object",
  "required": ["backend", "target", "draw", "shading"],
  "properties": {
    "backend": {
      "type": "string",
      "enum": ["Native", "Local"],
      "description": "Execution environment"
    },
    "target": {
      "type": "string",
      "enum": [
        "DirectCanvas.Path",
        "DirectCanvas.Rect",
        "OffscreenImage.Path",
        "OffscreenImage.Rasterizer"
      ],
      "description": "Rendering output method"
    },
    "draw": {
      "type": "string",
      "enum": ["Mesh.Greedy", "PerFace"],
      "description": "Geometry batching strategy"
    },
    "shading": {
      "type": "string",
      "enum": ["Volumetric", "Projected"],
      "description": "Lighting model"
    },
    "shader_stack": {
      "type": "array",
      "items": {
        "type": "object",
        "required": ["id"],
        "properties": {
          "id": {
            "type": "string",
            "description": "Stable shader identifier"
          },
          "params": {
            "type": "object",
            "description": "Shader-specific parameters",
            "additionalProperties": true
          }
        }
      },
      "default": []
    },
    "name": {
      "type": "string",
      "description": "Human-readable preset name"
    },
    "notes": {
      "type": "string",
      "description": "Optional description or usage notes"
    }
  }
}
```

### 1.2 Example Documents

#### Minimal (defaults)

```json
{
  "backend": "Local",
  "target": "DirectCanvas.Path",
  "draw": "Mesh.Greedy",
  "shading": "Projected"
}
```

#### Full (with shaders)

```json
{
  "backend": "Native",
  "target": "OffscreenImage.Rasterizer",
  "draw": "Mesh.Greedy",
  "shading": "Projected",
  "shader_stack": [
    {
      "id": "pixelmatt.dominant_face",
      "params": {
        "ambient": 0.15,
        "tint": [1.0, 0.9, 0.8, 1.0]
      }
    },
    {
      "id": "pixelmatt.hsl_bloom",
      "params": {
        "threshold": 0.7,
        "radius": 5,
        "intensity": 0.3
      }
    }
  ],
  "name": "Custom High-Perf",
  "notes": "Optimized for large models (128^3+)"
}
```

---

## 2. Lua Implementation

### 2.1 Module: `render/pipeline_spec.lua`

<details>
<summary>Full source code (click to expand)</summary>

```lua
-- render/pipeline_spec.lua
-- Composable render pipeline specification with presets and validation.

local json = require("json") -- Uses dkjson or compatible

local PipelineSpec = {}
PipelineSpec.__index = PipelineSpec

-- Enumerations (stable string values shared with C++)
local Backend = {
  Native = "Native",
  Local = "Local"
}

local Target = {
  DirectCanvas_Path = "DirectCanvas.Path",
  DirectCanvas_Rect = "DirectCanvas.Rect",
  OffscreenImage_Path = "OffscreenImage.Path",
  OffscreenImage_Rasterizer = "OffscreenImage.Rasterizer"
}

local Draw = {
  Mesh_Greedy = "Mesh.Greedy",
  PerFace = "PerFace"
}

local Shading = {
  Volumetric = "Volumetric",
  Projected = "Projected"
}

-- Feature detection (customize per host environment)
local Features = {
  has_native = function()
    return AseVoxel and AseVoxel.native_available == true
  end,
  has_gc_paths = function()
    -- Example: Check Aseprite API version
    return app and app.apiVersion and app.apiVersion >= 19
  end
}

-- Validation against current capabilities
local function validate(spec)
  local errors = {}
  
  if spec.backend == Backend.Native and not Features.has_native() then
    table.insert(errors, "Native backend not available (native module missing)")
  end
  
  local uses_dc = (spec.target == Target.DirectCanvas_Path or 
                   spec.target == Target.DirectCanvas_Rect)
  if uses_dc and not Features.has_gc_paths() then
    table.insert(errors, "DirectCanvas requires Aseprite with GraphicsContext API")
  end
  
  -- Shader availability check (Native backend only uses native-compiled shaders)
  if spec.backend == Backend.Native then
    local registry = AseVoxel and AseVoxel.native and AseVoxel.native.shader_registry
    for i, shader in ipairs(spec.shader_stack or {}) do
      if not (registry and registry[shader.id]) then
        table.insert(errors, string.format(
          "Shader '%s' has no native implementation", shader.id
        ))
      end
    end
  end
  
  return #errors == 0, errors
end

-- Deep clone table
local function clone_table(t)
  if type(t) ~= "table" then return t end
  local result = {}
  for k, v in pairs(t) do
    result[k] = clone_table(v)
  end
  return result
end

-- Constructor
function PipelineSpec.new(opts)
  opts = opts or {}
  local self = setmetatable({}, PipelineSpec)
  
  self.backend = opts.backend or Backend.Local
  self.target = opts.target or Target.DirectCanvas_Path
  self.draw = opts.draw or Draw.Mesh_Greedy
  self.shading = opts.shading or Shading.Projected
  self.shader_stack = clone_table(opts.shader_stack or {})
  self.name = opts.name
  self.notes = opts.notes
  
  return self
end

-- Serialize to table
function PipelineSpec:to_table()
  return {
    backend = self.backend,
    target = self.target,
    draw = self.draw,
    shading = self.shading,
    shader_stack = clone_table(self.shader_stack),
    name = self.name,
    notes = self.notes
  }
end

-- Serialize to JSON
function PipelineSpec:to_json()
  return json.encode(self:to_table())
end

-- Deserialize from table
function PipelineSpec.from_table(t)
  return PipelineSpec.new(t or {})
end

-- Deserialize from JSON
function PipelineSpec.from_json(json_str)
  local ok, t = pcall(json.decode, json_str)
  if not ok then
    error("PipelineSpec.from_json: Invalid JSON - " .. tostring(t))
  end
  return PipelineSpec.from_table(t)
end

-- Validate against current environment
function PipelineSpec:is_compatible()
  return validate(self)
end

-- Clone with overrides
function PipelineSpec:clone(overrides)
  local base = self:to_table()
  for k, v in pairs(overrides or {}) do
    base[k] = v
  end
  return PipelineSpec.new(base)
end

-- Presets (standard configurations)
local Presets = {}

Presets.VoxelLike = PipelineSpec.new{
  name = "Voxel-like",
  backend = Backend.Native,
  target = Target.DirectCanvas_Path,
  draw = Draw.Mesh_Greedy,
  shading = Shading.Volumetric,
  notes = "High-fidelity 3D look with volumetric lighting"
}

Presets.Fast = PipelineSpec.new{
  name = "Fast",
  backend = Backend.Native,
  target = Target.DirectCanvas_Rect,
  draw = Draw.PerFace,
  shading = Shading.Projected,
  notes = "Maximum speed, pixel-perfect rendering"
}

Presets.Balanced = PipelineSpec.new{
  name = "Balanced",
  backend = Backend.Native,
  target = Target.DirectCanvas_Rect,
  draw = Draw.Mesh_Greedy,
  shading = Shading.Projected,
  notes = "Good balance of speed and quality"
}

Presets.HQ_Path = PipelineSpec.new{
  name = "HQ-Path",
  backend = Backend.Local,
  target = Target.DirectCanvas_Path,
  draw = Draw.PerFace,
  shading = Shading.Volumetric,
  notes = "Full Lua ShaderStack support with volumetric rendering"
}

Presets.PreviewUltra = PipelineSpec.new{
  name = "Preview Ultra",
  backend = Backend.Local,
  target = Target.OffscreenImage_Rasterizer,
  draw = Draw.Mesh_Greedy,
  shading = Shading.Projected,
  notes = "Maximum compatibility, fast previews"
}

Presets.LegacyCompat = PipelineSpec.new{
  name = "Legacy-Compat",
  backend = Backend.Local,
  target = Target.OffscreenImage_Path,
  draw = Draw.PerFace,
  shading = Shading.Volumetric,
  notes = "Matches pre-refactor behavior"
}

Presets.DebugViz = PipelineSpec.new{
  name = "Debug Viz",
  backend = Backend.Local,
  target = Target.DirectCanvas_Rect,
  draw = Draw.PerFace,
  shading = Shading.Projected,
  notes = "Debugging overlays (normals, UVs, depth)"
}

-- Preset accessor
function PipelineSpec.get_preset(name)
  return Presets[name]
end

-- Apply preset with overrides
function PipelineSpec.apply_preset(preset_name, overrides)
  local base = Presets[preset_name]
  if not base then
    error("Unknown preset: " .. tostring(preset_name))
  end
  return base:clone(overrides)
end

-- List all preset names
function PipelineSpec.list_presets()
  local names = {}
  for name, _ in pairs(Presets) do
    table.insert(names, name)
  end
  table.sort(names)
  return names
end

-- Export public API
PipelineSpec.Enums = {
  Backend = Backend,
  Target = Target,
  Draw = Draw,
  Shading = Shading
}

PipelineSpec.Presets = Presets

return PipelineSpec
```

</details>

### 2.2 Usage Example

```lua
local PipelineSpec = require("render.pipeline_spec")

-- Create from preset
local spec = PipelineSpec.apply_preset("Balanced", {
  shading = PipelineSpec.Enums.Shading.Volumetric
})

-- Validate
local ok, errors = spec:is_compatible()
if not ok then
  app.alert("Pipeline incompatible:\n" .. table.concat(errors, "\n"))
  return
end

-- Serialize for native backend
local json_spec = spec:to_json()

-- Call native renderer
if AseVoxel.native and AseVoxel.native.render_dispatch then
  AseVoxel.native.render_dispatch(json_spec, model, view)
else
  -- Fallback to Lua
  local lua_renderer = require("render.lua_renderer")
  lua_renderer.dispatch(spec, model, view)
end
```

---

## 3. C++ Implementation

### 3.1 Header: `render/asev_pipeline_spec.hpp`

```cpp
#pragma once
#include <string>
#include <vector>
#include "nlohmann/json.hpp" // Single-header JSON library

namespace asev {

struct ShaderInstance {
  std::string id;
  nlohmann::json params;
  
  ShaderInstance() = default;
  ShaderInstance(std::string id_, nlohmann::json params_ = nlohmann::json::object())
    : id(std::move(id_)), params(std::move(params_)) {}
};

struct PipelineSpec {
  enum class Backend { Native, Local };
  enum class Target {
    DirectCanvas_Path,
    DirectCanvas_Rect,
    OffscreenImage_Path,
    OffscreenImage_Rasterizer
  };
  enum class Draw { Mesh_Greedy, PerFace };
  enum class Shading { Volumetric, Projected };
  
  Backend backend = Backend::Local;
  Target target = Target::DirectCanvas_Path;
  Draw draw = Draw::Mesh_Greedy;
  Shading shading = Shading::Projected;
  std::vector<ShaderInstance> shader_stack;
  std::string name;
  std::string notes;
  
  // Serialization
  static PipelineSpec from_json_string(const std::string& json_str);
  std::string to_json_string() const;
  
  // Validation (host provides feature flags)
  struct Features {
    bool has_native = false;
    bool has_gc_paths = true;
  };
  std::vector<std::string> validate(const Features& features) const;
  
  // Presets
  static PipelineSpec preset_voxel_like();
  static PipelineSpec preset_fast();
  static PipelineSpec preset_balanced();
  static PipelineSpec preset_hq_path();
  static PipelineSpec preset_preview_ultra();
  static PipelineSpec preset_legacy_compat();
  static PipelineSpec preset_debug_viz();
};

// String conversions
const char* to_string(PipelineSpec::Backend);
const char* to_string(PipelineSpec::Target);
const char* to_string(PipelineSpec::Draw);
const char* to_string(PipelineSpec::Shading);

PipelineSpec::Backend backend_from_string(const std::string&);
PipelineSpec::Target target_from_string(const std::string&);
PipelineSpec::Draw draw_from_string(const std::string&);
PipelineSpec::Shading shading_from_string(const std::string&);

} // namespace asev
```

### 3.2 Implementation: `render/asev_pipeline_spec.cpp`

<details>
<summary>Full source code (click to expand)</summary>

```cpp
#include "asev_pipeline_spec.hpp"
#include <stdexcept>

using json = nlohmann::json;

namespace asev {

// ============================================================================
// String Conversions
// ============================================================================

const char* to_string(PipelineSpec::Backend v) {
  switch (v) {
    case PipelineSpec::Backend::Native: return "Native";
    case PipelineSpec::Backend::Local: return "Local";
  }
  return "Local";
}

const char* to_string(PipelineSpec::Target v) {
  switch (v) {
    case PipelineSpec::Target::DirectCanvas_Path: return "DirectCanvas.Path";
    case PipelineSpec::Target::DirectCanvas_Rect: return "DirectCanvas.Rect";
    case PipelineSpec::Target::OffscreenImage_Path: return "OffscreenImage.Path";
    case PipelineSpec::Target::OffscreenImage_Rasterizer: return "OffscreenImage.Rasterizer";
  }
  return "DirectCanvas.Path";
}

const char* to_string(PipelineSpec::Draw v) {
  switch (v) {
    case PipelineSpec::Draw::Mesh_Greedy: return "Mesh.Greedy";
    case PipelineSpec::Draw::PerFace: return "PerFace";
  }
  return "Mesh.Greedy";
}

const char* to_string(PipelineSpec::Shading v) {
  switch (v) {
    case PipelineSpec::Shading::Volumetric: return "Volumetric";
    case PipelineSpec::Shading::Projected: return "Projected";
  }
  return "Projected";
}

PipelineSpec::Backend backend_from_string(const std::string& s) {
  if (s == "Native") return PipelineSpec::Backend::Native;
  return PipelineSpec::Backend::Local;
}

PipelineSpec::Target target_from_string(const std::string& s) {
  if (s == "DirectCanvas.Path") return PipelineSpec::Target::DirectCanvas_Path;
  if (s == "DirectCanvas.Rect") return PipelineSpec::Target::DirectCanvas_Rect;
  if (s == "OffscreenImage.Path") return PipelineSpec::Target::OffscreenImage_Path;
  return PipelineSpec::Target::OffscreenImage_Rasterizer;
}

PipelineSpec::Draw draw_from_string(const std::string& s) {
  if (s == "PerFace") return PipelineSpec::Draw::PerFace;
  return PipelineSpec::Draw::Mesh_Greedy;
}

PipelineSpec::Shading shading_from_string(const std::string& s) {
  if (s == "Volumetric") return PipelineSpec::Shading::Volumetric;
  return PipelineSpec::Shading::Projected;
}

// ============================================================================
// Serialization
// ============================================================================

PipelineSpec PipelineSpec::from_json_string(const std::string& json_str) {
  json j = json::parse(json_str);
  PipelineSpec spec;
  
  if (j.contains("backend"))
    spec.backend = backend_from_string(j["backend"].get<std::string>());
  if (j.contains("target"))
    spec.target = target_from_string(j["target"].get<std::string>());
  if (j.contains("draw"))
    spec.draw = draw_from_string(j["draw"].get<std::string>());
  if (j.contains("shading"))
    spec.shading = shading_from_string(j["shading"].get<std::string>());
  if (j.contains("name"))
    spec.name = j["name"].get<std::string>();
  if (j.contains("notes"))
    spec.notes = j["notes"].get<std::string>();
  
  spec.shader_stack.clear();
  if (j.contains("shader_stack")) {
    for (const auto& shader_json : j["shader_stack"]) {
      ShaderInstance s;
      s.id = shader_json.value("id", std::string{});
      s.params = shader_json.contains("params") ? shader_json["params"] : json::object();
      spec.shader_stack.push_back(std::move(s));
    }
  }
  
  return spec;
}

std::string PipelineSpec::to_json_string() const {
  json j;
  j["backend"] = to_string(backend);
  j["target"] = to_string(target);
  j["draw"] = to_string(draw);
  j["shading"] = to_string(shading);
  
  if (!name.empty()) j["name"] = name;
  if (!notes.empty()) j["notes"] = notes;
  
  json shader_arr = json::array();
  for (const auto& s : shader_stack) {
    json shader_obj;
    shader_obj["id"] = s.id;
    shader_obj["params"] = s.params;
    shader_arr.push_back(std::move(shader_obj));
  }
  j["shader_stack"] = std::move(shader_arr);
  
  return j.dump();
}

// ============================================================================
// Validation
// ============================================================================

std::vector<std::string> PipelineSpec::validate(const Features& features) const {
  std::vector<std::string> errors;
  
  if (backend == Backend::Native && !features.has_native) {
    errors.emplace_back("Native backend not available");
  }
  
  bool uses_dc = (target == Target::DirectCanvas_Path || target == Target::DirectCanvas_Rect);
  if (uses_dc && !features.has_gc_paths) {
    errors.emplace_back("DirectCanvas requires GraphicsContext API support");
  }
  
  for (const auto& shader : shader_stack) {
    if (shader.id.empty()) {
      errors.emplace_back("Shader with empty ID in stack");
    }
  }
  
  return errors;
}

// ============================================================================
// Presets
// ============================================================================

PipelineSpec PipelineSpec::preset_voxel_like() {
  PipelineSpec s;
  s.name = "Voxel-like";
  s.backend = Backend::Native;
  s.target = Target::DirectCanvas_Path;
  s.draw = Draw::Mesh_Greedy;
  s.shading = Shading::Volumetric;
  s.notes = "High-fidelity 3D look";
  return s;
}

PipelineSpec PipelineSpec::preset_fast() {
  PipelineSpec s;
  s.name = "Fast";
  s.backend = Backend::Native;
  s.target = Target::DirectCanvas_Rect;
  s.draw = Draw::PerFace;
  s.shading = Shading::Projected;
  s.notes = "Maximum speed";
  return s;
}

PipelineSpec PipelineSpec::preset_balanced() {
  PipelineSpec s;
  s.name = "Balanced";
  s.backend = Backend::Native;
  s.target = Target::DirectCanvas_Rect;
  s.draw = Draw::Mesh_Greedy;
  s.shading = Shading::Projected;
  s.notes = "Speed + quality balance";
  return s;
}

PipelineSpec PipelineSpec::preset_hq_path() {
  PipelineSpec s;
  s.name = "HQ-Path";
  s.backend = Backend::Local;
  s.target = Target::DirectCanvas_Path;
  s.draw = Draw::PerFace;
  s.shading = Shading::Volumetric;
  s.notes = "Full Lua ShaderStack";
  return s;
}

PipelineSpec PipelineSpec::preset_preview_ultra() {
  PipelineSpec s;
  s.name = "Preview Ultra";
  s.backend = Backend::Local;
  s.target = Target::OffscreenImage_Rasterizer;
  s.draw = Draw::Mesh_Greedy;
  s.shading = Shading::Projected;
  s.notes = "Max compatibility";
  return s;
}

PipelineSpec PipelineSpec::preset_legacy_compat() {
  PipelineSpec s;
  s.name = "Legacy-Compat";
  s.backend = Backend::Local;
  s.target = Target::OffscreenImage_Path;
  s.draw = Draw::PerFace;
  s.shading = Shading::Volumetric;
  s.notes = "Pre-refactor behavior";
  return s;
}

PipelineSpec PipelineSpec::preset_debug_viz() {
  PipelineSpec s;
  s.name = "Debug Viz";
  s.backend = Backend::Local;
  s.target = Target::DirectCanvas_Rect;
  s.draw = Draw::PerFace;
  s.shading = Shading::Projected;
  s.notes = "Debugging overlays";
  return s;
}

} // namespace asev
```

</details>

### 3.3 Usage Example

```cpp
#include "asev_pipeline_spec.hpp"
#include <iostream>

extern "C" int asev_render_dispatch(const char* json_spec_str) {
  using namespace asev;
  
  // Parse from Lua-provided JSON
  PipelineSpec spec = PipelineSpec::from_json_string(json_spec_str);
  
  // Validate
  PipelineSpec::Features features{true, true}; // Native + GC available
  auto errors = spec.validate(features);
  if (!errors.empty()) {
    for (const auto& err : errors) {
      std::cerr << "Pipeline error: " << err << std::endl;
    }
    return -1;
  }
  
  // Route to appropriate renderer
  switch (spec.backend) {
    case PipelineSpec::Backend::Native:
      // native_render(spec, model, view);
      break;
    case PipelineSpec::Backend::Local:
      // Should not reach here (Lua handles Local)
      break;
  }
  
  return 0;
}
```

---

## 4. Interop Bridge

### 4.1 Lua → C++ (via FFI)

```lua
-- Serialize spec to JSON
local json_str = spec:to_json()

-- Call C++ function (via Aseprite plugin binding or LuaJIT FFI)
AseVoxel.native.render_dispatch(json_str, model_ptr, view_ptr)
```

### 4.2 C++ Export (for Aseprite plugin)

```cpp
extern "C" {
  int asev_render_dispatch_ffi(lua_State* L) {
    const char* json_spec = luaL_checkstring(L, 1);
    void* model = lua_touserdata(L, 2);
    void* view = lua_touserdata(L, 3);
    
    int result = asev_render_dispatch(json_spec);
    lua_pushinteger(L, result);
    return 1;
  }
}
```

---

## 5. Testing

### 5.1 Unit Tests (Lua)

```lua
local PipelineSpec = require("render.pipeline_spec")

-- Test serialization round-trip
local spec1 = PipelineSpec.new{
  backend = "Native",
  target = "DirectCanvas.Rect",
  draw = "Mesh.Greedy",
  shading = "Projected"
}

local json_str = spec1:to_json()
local spec2 = PipelineSpec.from_json(json_str)

assert(spec1.backend == spec2.backend)
assert(spec1.target == spec2.target)
print("✓ Serialization test passed")

-- Test preset application
local balanced = PipelineSpec.get_preset("Balanced")
assert(balanced.name == "Balanced")
print("✓ Preset test passed")
```

### 5.2 Unit Tests (C++)

```cpp
#include "asev_pipeline_spec.hpp"
#include <cassert>

void test_serialization() {
  using namespace asev;
  
  PipelineSpec spec1 = PipelineSpec::preset_balanced();
  std::string json_str = spec1.to_json_string();
  PipelineSpec spec2 = PipelineSpec::from_json_string(json_str);
  
  assert(spec1.backend == spec2.backend);
  assert(spec1.target == spec2.target);
  std::cout << "✓ C++ serialization test passed\n";
}

int main() {
  test_serialization();
  return 0;
}
```

---

## 6. Migration Checklist

- [ ] Add `nlohmann/json.hpp` to C++ dependencies
- [ ] Add `dkjson.lua` (or compatible) to Lua dependencies
- [ ] Implement `render/pipeline_spec.lua`
- [ ] Implement `render/asev_pipeline_spec.hpp/cpp`
- [ ] Wire Lua→C++ FFI binding for `render_dispatch`
- [ ] Update MainDialog to generate PipelineSpec from UI
- [ ] Add preset selector dropdown
- [ ] Implement validation error display
- [ ] Write integration tests for all presets

---

## 7. Appendix: Preset Comparison Table

| Preset | Backend | Target | Draw | Shading | Use Case |
|--------|---------|--------|------|---------|----------|
| Voxel-like | Native | DC.Path | Greedy | Volumetric | High fidelity |
| Fast | Native | DC.Rect | PerFace | Projected | Max speed |
| Balanced | Native | DC.Rect | Greedy | Projected | General use |
| HQ-Path | Local | DC.Path | PerFace | Volumetric | Full shaders |
| Preview Ultra | Local | OI.Raster | Greedy | Projected | Compatibility |
| Legacy-Compat | Local | OI.Path | PerFace | Volumetric | Old behavior |
| Debug Viz | Local | DC.Rect | PerFace | Projected | Development |

**Legend:**
- DC = DirectCanvas
- OI = OffscreenImage

---

**Status:** Ready for implementation · See IMPLEMENTATION_PLAN.md for work breakdown.
