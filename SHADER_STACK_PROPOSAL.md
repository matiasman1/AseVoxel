# AseVoxel Shader Stack System Proposal

## Overview
Transform the current single-mode lighting system into a flexible shader stack architecture similar to FxStack, where multiple shader passes can be chained together to produce complex rendering effects.

---

## Architecture

### Core Concept
- **Shader Stack Pipeline**: Each shader receives the previous shader's output (color + lighting data per face)
- **Composable**: Shaders can be reordered, enabled/disabled, duplicated
- **Two Categories**: 
  - **Lighting Shaders** - Calculate illumination (Dynamic, Basic, etc.)
  - **FX Shaders** - Post-process colors (FaceShade, Outline, Palette Mapping, etc.)

### Data Flow
```
Voxel Geometry → [Lighting Shader 1] → [Lighting Shader 2] → [FX Shader 1] → [FX Shader 2] → Final Image
                      ↓                      ↓                    ↓                ↓
                 (normals, pos)         (lit colors)         (processed)      (final colors)
```

---

## Folder Structure

```
render/
  shaders/
    lighting/
      dynamic.lua          # Current Dynamic lighting (pitch/yaw/diffuse/ambient/rim)
      basic.lua            # Current Basic lighting (simple directional)
      ambient_occlusion.lua # NEW: Per-voxel AO based on neighbor density
      hemisphere.lua       # NEW: Sky/ground two-tone lighting
      point_light.lua      # NEW: Multiple point lights with falloff
      directional.lua      # NEW: Sun-like directional light
      emissive.lua         # NEW: Self-illumination based on color/material
    
    fx/
      faceshade.lua        # Current: Model-center-based face shading
      faceshade_camera.lua # NEW: Camera-normal-based face shading
      iso.lua              # Current: Isometric fixed shading
      outline.lua          # NEW: Edge detection & outline rendering
      palette_map.lua      # NEW: Color quantization to palette
      dither.lua           # NEW: Bayer/ordered/diffusion dithering
      cel_shade.lua        # NEW: Posterize lighting into bands
      fresnel.lua          # NEW: Edge glow/rim based on view angle
      gradient_map.lua     # NEW: Remap luminosity to gradient
      fog.lua              # NEW: Depth-based fog
      bloom.lua            # NEW: Glow on bright areas
      vignette.lua         # NEW: Darken edges
      chromatic_aberration.lua # NEW: RGB channel offset
      pixelate.lua         # NEW: Reduce effective resolution
      
  shader_stack.lua         # Stack management & execution
  shader_interface.lua     # Common shader interface/protocol
```

---

## Shader Categories & Detailed Specs

### 🔦 LIGHTING SHADERS

#### 1. **Dynamic Light** (existing, refactored)
- **Purpose**: Physically-inspired lighting with single directional light
- **Parameters**:
  - Pitch (-90 to 90°)
  - Yaw (0 to 360°)
  - Diffuse intensity (0-100%)
  - Ambient intensity (0-100%)
  - Light diameter (0-200)
  - Rim lighting (bool + intensity)
  - Light color (RGB)
- **Output**: Per-face RGB with diffuse + ambient + rim components

#### 2. **Basic Light** (existing, refactored)
- **Purpose**: Simple front-facing lighting based on face normal to camera angle
- **Parameters**:
  - Light intensity (0-100%) - brightness for faces toward camera
  - Shade intensity (0-100%) - darkness for faces away from camera
- **Algorithm**: 
  - Compute dot product between face normal and camera direction
  - Faces toward camera (dot > 0) get light intensity applied
  - Faces away from camera (dot < 0) get shade intensity applied
  - Simple, fast, camera-dependent lighting
- **Output**: Per-face RGB based on normal-to-camera angle

#### 3. **Ambient Occlusion** (NEW)
- **Purpose**: Darken voxels based on surrounding geometry density
- **Parameters**:
  - Sample radius (1-5 voxels)
  - Intensity (0-100%)
  - Bias (to prevent over-darkening)
- **Output**: Per-voxel occlusion factor multiplied into RGB

#### 4. **Hemisphere Lighting** (NEW)
- **Purpose**: Two-tone lighting (sky + ground) like outdoor scenes
- **Parameters**:
  - Sky color (RGB)
  - Ground color (RGB)
  - Sky intensity (0-100%)
  - Ground intensity (0-100%)
  - Gradient falloff
- **Output**: Per-face RGB based on normal direction (up = sky, down = ground)

#### 5. **Point Light** (NEW)
- **Purpose**: Multiple localized light sources with distance falloff
- **Parameters**:
  - Light positions (X, Y, Z) - up to 8 lights
  - Light colors (RGB per light)
  - Intensity per light
  - Falloff radius per light
  - Attenuation mode (linear/quadratic/none)
- **Output**: Per-face RGB accumulated from all point lights

#### 6. **Directional Light** (NEW)
- **Purpose**: Infinite distance light (sun-like) with shadows
- **Parameters**:
  - Direction vector (X, Y, Z)
  - Color (RGB)
  - Intensity (0-200%)
  - Cast shadows (bool)
  - Shadow softness
- **Output**: Per-face RGB with optional shadow casting

#### 7. **Emissive** (NEW)
- **Purpose**: Make certain colors/materials glow independently
- **Parameters**:
  - Emissive color range (match colors within threshold)
  - Emission intensity (0-500%)
  - Bloom amount (spreads glow to neighbors)
- **Output**: Adds emission to matched voxels, unaffected by other lighting

---

### 🎨 FX SHADERS

#### 8. **FaceShade** (existing, refactored)
- **Purpose**: Shade faces based on model-center normals
- **Parameters**:
  - Alpha mode (FULL only - applies brightness as multiplier 0-255)
  - Top face brightness (0-255)
  - Bottom face brightness (0-255)
  - Front face brightness (0-255)
  - Back face brightness (0-255)
  - Left face brightness (0-255)
  - Right face brightness (0-255)
- **Algorithm**:
  - Determine face direction from model center axis (not camera)
  - Multiply face RGB by (brightness/255)
  - Alpha channel unchanged
- **Output**: Multiplies face colors by direction-based factors
- **Note**: Does NOT support literal colors, material modes, or tint - only alpha full mode (brightness multiplier)

#### 9. **FaceShade Camera** (NEW)
- **Purpose**: Shade faces based on camera-facing angle instead of model-center axis
- **Parameters**:
  - Alpha mode (FULL only - applies brightness as multiplier 0-255)
  - Front-facing brightness (0-255) - faces toward camera
  - Top-facing brightness (0-255) - faces upward relative to camera
  - Left-facing brightness (0-255) - faces left relative to camera
  - Right-facing brightness (0-255) - faces right relative to camera
  - Bottom-facing brightness (0-255) - faces downward relative to camera
- **Algorithm**:
  - Project face normal to camera view space
  - Determine dominant direction (front/top/left/right/bottom)
  - Back faces never show, so no back parameter needed
  - Apply corresponding brightness as multiplier
- **Output**: Smooth camera-dependent shading
- **Benefit**: More realistic than fixed face shading, adapts to camera rotation
- **Note**: Only brightness multiplier mode (alpha full), no literal/material/tint modes

#### 10. **Iso** (existing, refactored)
- **Purpose**: Fixed isometric shading with Alpha/Literal modes and Material/Full options
- **Parameters**:
  - **Shading Mode**:
    - Alpha (brightness multiplier 0-255)
    - Literal (replace RGB with shade color)
  - **Alpha Tint**: Optional color tint when in Alpha mode
  - **Material vs Full**:
    - Material: Only shade non-pure colors (preserve pure R/G/B/C/M/Y/K/W)
    - Full: Shade all colors uniformly
  - **Face Brightnesses**:
    - Top face brightness (0-255) - applied to upward-facing faces
    - Left face brightness (0-255) - applied to left-facing faces (camera-relative)
    - Right face brightness (0-255) - applied to right-facing faces (camera-relative)
- **Algorithm**:
  - Determine face orientation: top (normal.y dominant), left/right (camera X projection)
  - Bottom faces use same brightness as top faces (most upward/downward)
  - In Alpha mode: multiply RGB by (brightness/255)
  - In Literal mode: replace RGB with shade color at brightness level
  - Material mode: skip pure colors (R=255,G=0,B=0 or similar pure hues)
- **Output**: Classic isometric look with configurable mode

---

## UI Organization

### Main Dialog Changes

#### Current Structure:
```
[Render] [Lighting] [Effects] [Animation] [Export] [Debug]
```

#### Proposed Structure:
```
[Render] [Shader Stack] [Animation] [Export] [Debug]
```

### "Shader Stack" Tab Layout

```
┌─────────────────────────────────────────────────────────┐
│  Shader Stack                                           │
├─────────────────────────────────────────────────────────┤
│  ┌───────────────────────────────────────────────────┐ │
│  │ 🔦 LIGHTING SHADERS                                │ │
│  ├───────────────────────────────────────────────────┤ │
│  │ ▼ Dynamic Light                    [↑] [↓] [×]    │ │
│  │   ├─ Pitch: [━━━●━━━] 25°                        │ │
│  │   ├─ Yaw: [━━━●━━━] 45°                          │ │
│  │   ├─ Diffuse: [━━━━●━] 60%                       │ │
│  │   ├─ Ambient: [━●━━━━] 30%                       │ │
│  │   ├─ Diameter: [━━━●━━] 100                      │ │
│  │   ├─ ☑ Rim Lighting                              │ │
│  │   └─ Light Color: [████]                         │ │
│  ├───────────────────────────────────────────────────┤ │
│  │ ▶ Ambient Occlusion               [↑] [↓] [×]    │ │
│  ├───────────────────────────────────────────────────┤ │
│  │ [+ Add Lighting Shader ▼]                        │ │
│  │    ├─ Dynamic Light                               │ │
│  │    ├─ Basic Light                                 │ │
│  │    ├─ Ambient Occlusion                           │ │
│  │    ├─ Hemisphere Light                            │ │
│  │    ├─ Point Light                                 │ │
│  │    ├─ Directional Light                           │ │
│  │    └─ Emissive                                    │ │
│  └───────────────────────────────────────────────────┘ │
│                                                          │
│  ┌───────────────────────────────────────────────────┐ │
│  │ 🎨 FX SHADERS                                      │ │
│  ├───────────────────────────────────────────────────┤ │
│  │ ▼ FaceShade (Camera)               [↑] [↓] [×]    │ │
│  │   ├─ Front Facing: [━━━━●━] 100%                 │ │
│  │   ├─ Side Facing: [━━●━━━━] 70%                  │ │
│  │   ├─ Away Facing: [━●━━━━━] 40%                  │ │
│  │   └─ Smoothness: [━━━●━━━] 50%                   │ │
│  ├───────────────────────────────────────────────────┤ │
│  │ ▼ Outline                          [↑] [↓] [×]    │ │
│  │   ├─ Mode: [Geometry ▼]                          │ │
│  │   ├─ Width: [━●━━━━━] 1.0 voxels                 │ │
│  │   ├─ Color: [Contrast ▼] or [████]               │ │
│  │   ├─ Directions: ☑X+ ☑X- ☑Y+ ☑Y- ☑Z+ ☑Z-        │ │
│  │   └─ Placement: [Outside ▼]                      │ │
│  ├───────────────────────────────────────────────────┤ │
│  │ ▶ Palette Mapping                  [↑] [↓] [×]    │ │
│  ├───────────────────────────────────────────────────┤ │
│  │ [+ Add FX Shader ▼]                              │ │
│  │    ├─ FaceShade                                   │ │
│  │    ├─ FaceShade (Camera)                          │ │
│  │    ├─ Iso                                         │ │
│  │    ├─ Outline                                     │ │
│  │    ├─ Palette Mapping                             │ │
│  │    ├─ Dither                                      │ │
│  │    ├─ Cel Shade                                   │ │
│  │    ├─ Fresnel                                     │ │
│  │    ├─ Gradient Map                                │ │
│  │    ├─ Fog                                         │ │
│  │    ├─ Bloom                                       │ │
│  │    ├─ Vignette                                    │ │
│  │    ├─ Chromatic Aberration                        │ │
│  │    └─ Pixelate                                    │ │
│  └───────────────────────────────────────────────────┘ │
│                                                          │
│  [Clear All]  [Load Preset ▼]  [Save Preset]          │
└─────────────────────────────────────────────────────────┘
```

### UI Features
- **Collapsible Sections**: Click header to collapse shader to one line
- **Reorder**: [↑] [↓] buttons to move shader up/down in stack
- **Remove**: [×] button to delete shader
- **Duplicate**: Right-click menu → "Duplicate" (allows multiple instances)
- **Enable/Disable**: Checkbox in collapsed header to temporarily disable without removing
- **Presets**: Save/load entire shader stacks as `.json` presets
- **Live Preview**: All changes update preview in real-time (with adaptive throttling)

---

## Migration Strategy

### Phase 1: Refactor Current System
1. Extract `Dynamic`, `Basic`, `Stack` (faceshade+dynamic) into separate shader modules
2. Create `shader_interface.lua` with common protocol:
   ```lua
   function shader.process(inputData, params)
     -- inputData = { faces = {{pos, normal, color, ...}}, voxels = {...} }
     -- returns modified inputData
   end
   ```
3. Keep backwards compatibility - current lighting modes work as before

### Phase 2: Implement Shader Stack
1. Create `shader_stack.lua` - manages stack execution
2. Add shader stack UI in new tab
3. Implement first new shaders:
   - FaceShade Camera
   - Outline (basic)
   - Palette Mapping (basic)

### Phase 3: Expand Shader Library
1. Add remaining lighting shaders (AO, Hemisphere, Point Light, etc.)
2. Add remaining FX shaders (Dither, Cel Shade, Fresnel, etc.)
3. Implement preset system

### Phase 4: Native Acceleration
1. Port performance-critical shaders to C++ (optional)
2. Keep Lua versions as fallback

---

## Backwards Compatibility

### Option A: Legacy Mode Toggle
- Keep current "Lighting" tab for simple use cases
- Add "Advanced: Use Shader Stack" checkbox that switches to new system
- Migrate user's selection to equivalent shader stack when toggled

### Option B: Automatic Migration
- Remove old "Lighting" tab entirely
- Auto-convert old settings to shader stack on first load:
  - `shadingMode="Basic"` → Adds "Basic Light" shader
  - `shadingMode="Dynamic"` → Adds "Dynamic Light" shader
  - `shadingMode="Stack"` → Adds "FaceShade" + "Dynamic Light"
  - FX settings → Adds equivalent FX shaders

**Recommendation**: Option B (automatic migration) for cleaner UX

---

## Shader Data Protocol

### Input/Output Structure
```lua
shaderData = {
  -- Per-face data (for face-based rendering)
  faces = {
    {
      voxel = {x, y, z},
      face = "top",  -- "top", "bottom", "front", "back", "left", "right"
      normal = {x, y, z},  -- world-space normal
      color = {r, g, b, a},  -- current color (modified by previous shaders)
      depth = 123.45,  -- camera distance
      screenPos = {x, y},  -- projected 2D position (if available)
      originalColor = {r, g, b, a},  -- untouched voxel color
    },
    -- ... more faces
  },
  
  -- Per-voxel data
  voxels = {
    {x=1, y=2, z=3, color={r,g,b,a}, neighbors={...}},
    -- ... more voxels
  },
  
  -- Global context
  camera = {
    position = {x, y, z},
    rotation = {x, y, z},
    direction = {x, y, z},
    fov = 45,
    orthogonal = false,
  },
  
  modelBounds = {minX, maxX, minY, maxY, minZ, maxZ},
  middlePoint = {x, y, z},
  
  -- Output target info
  width = 400,
  height = 400,
  voxelSize = 2.5,  -- pixels per voxel
}
```

### Shader Interface
```lua
-- All shaders must implement:
local myShader = {}

myShader.info = {
  name = "My Shader",
  category = "lighting",  -- "lighting" or "fx"
  version = "1.0",
  author = "Your Name",
  description = "Does something cool",
}

myShader.defaultParams = {
  intensity = 100,
  color = {r=255, g=255, b=255},
  -- ... shader-specific defaults
}

function myShader.process(shaderData, params)
  -- Modify shaderData.faces[].color based on params
  -- Return modified shaderData
  return shaderData
end

function myShader.buildUI(dlg, params, onChange)
  -- Build Aseprite Dialog widgets for shader parameters
  -- Call onChange(newParams) when user changes values
end

return myShader
```

---

## Additional Shader Ideas

### 🔦 More Lighting Shaders
- **Image-Based Lighting (IBL)**: Use an image as environment map
- **Subsurface Scattering**: Simulate light passing through thin objects
- **Volumetric Light**: God rays / light shafts through geometry
- **Bounce Light**: Simple 1-bounce indirect illumination

### 🎨 More FX Shaders
- **Edge Detect**: Sobel/Canny edge detection for technical drawings
- **Halftone**: Comic book dot patterns
- **ASCII Art**: Convert to ASCII characters (novelty)
- **Normal Map Overlay**: Display normals as RGB (debug/artistic)
- **Depth of Field**: Blur based on distance from focus plane
- **Motion Blur**: Blur based on animation velocity (future)
- **Color Grading**: LUT-based color correction
- **HSV Adjust**: Hue/Saturation/Value shifts
- **Invert**: Color inversion
- **Grayscale**: Desaturate with luminosity preservation
- **Sepia**: Vintage photo effect
- **Channel Swap**: Rearrange RGB channels (glitch art)
- **Threshold**: Binary black/white based on luminosity
- **Mosaic**: Stained glass / crystallize effect

---

## Performance Considerations

### Optimization Strategies
1. **Lazy Evaluation**: Only execute enabled shaders
2. **Caching**: Cache shader results when parameters unchanged
3. **LOD**: Reduce shader quality at high voxel counts
4. **Parallel**: Some shaders can process faces independently (future: multithreading)
5. **Native**: Move hotspots to C++ (outline detection, palette mapping)
6. **Early Exit**: If shader has no effect (intensity=0), skip processing

### Profiling Integration
- Add shader-specific profiling marks: `profiler.mark("shader_outline")`
- Show per-shader timing in performance report
- Identify bottleneck shaders

---

## Presets System

### Preset Examples
- **"Retro NES"**: Palette Mapping (16 colors) + Dither (Bayer 2x2) + Pixelate (8x8)
- **"Cel Shaded"**: Dynamic Light + Cel Shade (4 bands) + Outline (black, 1px)
- **"Atmospheric"**: Hemisphere Light + Ambient Occlusion + Fog + Vignette
- **"Neon Glow"**: Emissive + Bloom + Chromatic Aberration
- **"Classic Isometric"**: Basic Light + Iso + FaceShade
- **"Cinematic"**: Directional Light (with shadows) + Fresnel + Vignette + Bloom
- **"Pixelart"**: Basic Light + Palette Mapping (sprite colors) + Dither
- **"Technical Drawing"**: Edge Detect + Grayscale + Outline (geometry, white)

### Preset Format (JSON)
```json
{
  "name": "Retro NES",
  "version": "1.0",
  "shaders": [
    {
      "type": "basic_light",
      "category": "lighting",
      "enabled": true,
      "params": {
        "lightIntensity": 80,
        "shadeIntensity": 40
      }
    },
    {
      "type": "palette_map",
      "category": "fx",
      "enabled": true,
      "params": {
        "source": "custom",
        "colors": ["#000000", "#FFFFFF", "#FF0000", ...],
        "maxColors": 16,
        "algorithm": "luminosity",
        "dithering": "bayer_2x2"
      }
    }
  ]
}
```

---

## Questions for Review

1. **UI Placement**: Keep in main dialog or separate "Shader Stack" window?
2. **Naming**: "Shader Stack" vs "Render Pipeline" vs "FX Stack"?
3. **Migration**: Force migration or keep legacy modes?
4. **Shader Limit**: Cap at N shaders per stack for performance?
5. **Preview Quality**: Add "Draft Mode" toggle for faster preview during shader editing?
6. **Native Priority**: Which shaders need C++ acceleration first?
7. **Outline Shader**: Should it be pre-rendering (add outline geometry) or post-rendering (image effect)?
8. **Palette Mapping**: Should NES subsprite grid be separate shader or parameter?
9. **Backward Compat**: Support old `fxStack` parameter or deprecate entirely?
10. **Shader Marketplace**: Future: Allow community shader contributions?

---

## Implementation Priority (Suggested)

### MVP (Minimum Viable Product)
1. ✅ Shader stack architecture (`shader_stack.lua`, `shader_interface.lua`)
2. ✅ UI for stack management (collapsible, reorder, add/remove)
3. ✅ Refactor existing: Dynamic → `lighting/dynamic.lua`
4. ✅ Refactor existing: Basic → `lighting/basic.lua`
5. ✅ Refactor existing: FaceShade → `fx/faceshade.lua`
6. ✅ NEW: `fx/faceshade_camera.lua` (your requested camera-based shading)
7. ✅ NEW: `fx/outline.lua` (your requested outline shader)
8. ✅ NEW: `fx/palette_map.lua` (your requested NES palette mapping)

### Phase 2 (High Value)
9. `lighting/ambient_occlusion.lua`
10. `lighting/hemisphere.lua`
11. `fx/cel_shade.lua`
12. `fx/dither.lua`
13. Preset system (save/load)

### Phase 3 (Polish)
14. `lighting/point_light.lua`
15. `fx/fresnel.lua`
16. `fx/gradient_map.lua`
17. `fx/fog.lua`
18. Native C++ acceleration for outline + palette_map

### Phase 4 (Advanced)
19. Remaining shaders (bloom, vignette, chromatic, etc.)
20. Image-based lighting
21. Subsurface scattering
22. Community shader API

---

## Next Steps

**Please review and comment on:**
- Which shaders are highest priority for you?
- UI layout preferences (tabs, windows, organization)
- Any shader ideas I missed that you want?
- Migration strategy preference (A or B)
- Shader naming (good/confusing?)
- Any concerns about performance?
- Should outline be pre-render (geometry) or post-render (image)?

Once you approve the plan, I'll start implementation with the MVP shaders! 🚀


# AseVoxel Shader Stack Refactor Proposal

## Executive Summary

This document outlines the **complete refactor** of AseVoxel's rendering system from the current monolithic `preview_renderer.lua` + inline shading modes into a **modular shader stack architecture**. The goal is to:

1. **Separate concerns**: Extract Basic, Dynamic, FaceShade, and Iso shaders into discrete modules
2. **Enable extensibility**: Allow users to create custom lighting/FX shaders in Lua
3. **Preserve performance**: Maintain native C++ acceleration where available, with Lua fallback
4. **Replicate existing output**: Phase 1 produces **identical** visual results to current implementation
5. **Deprecate legacy**: Remove old `shadingMode` parameter system entirely after migration

---

## Phase 1: Compatibility Refactor (Verbatim Output)

**Goal**: Transform existing code without changing visual output or breaking existing scenes.

### 1.1 Current Architecture (Before)

```
preview_renderer.lua
  ├─ renderPreview()
  │   ├─ if shadingMode == "Basic" → basicModeBrightness()
  │   ├─ if shadingMode == "Dynamic" → dynamic lighting inline
  │   └─ if shadingMode == "Stack" → fxStackModule.shadeFace()
  │
  ├─ shading.lua
  │   └─ shadeFaceColor() [dispatcher]
  │
  ├─ fx_stack.lua
  │   └─ shadeFace() [faceshade + iso logic]
  │
  └─ asevoxel_native.cpp
      ├─ render_basic()
      ├─ render_dynamic()
      └─ render_stack()
```

**Problems**:
- Lighting logic scattered across 3 files
- Native renderer has separate functions per mode (code duplication)
- Hard to add new shaders without modifying core renderer
- FX stack is separate from lighting (inconsistent)

### 1.2 Target Architecture (After Phase 1)

```
render/
  shaders/
    lighting/
      basic.lua          # Extracted from shading.lua::basicModeBrightness
      dynamic.lua        # Extracted from shading.lua + preview_renderer.lua
    fx/
      faceshade.lua      # Extracted from fx_stack.lua
      iso.lua            # Extracted from fx_stack.lua
  
  shader_stack.lua       # NEW: Stack execution engine
  shader_interface.lua   # NEW: Common shader protocol
  
  preview_renderer.lua   # MODIFIED: Uses shader_stack.lua
  shading.lua            # MODIFIED: Thin wrapper → shader_stack
  native_bridge.lua      # MODIFIED: Routes to shader_stack

asevoxel_native.cpp      # MODIFIED: Unified render_unified() function
```

**Key Changes**:
- All shaders follow same interface (lighting + FX treated equally)
- Native renderer has **one** function that accepts shader stack
- Backward compatibility via automatic migration layer

---

## 1.3 Shader Interface Protocol

Every shader (Lua or C++) implements this interface:

### `shader_interface.lua` (NEW)

```lua
-- Common protocol for all shaders (lighting + FX)

local shaderInterface = {}

-- Shader metadata structure
shaderInterface.ShaderInfo = {
  id = "unique_shader_id",           -- e.g. "dynamic_light_v1"
  name = "Human Readable Name",      -- e.g. "Dynamic Lighting"
  version = "1.0.0",
  author = "Author Name",
  category = "lighting",             -- "lighting" or "fx"
  complexity = "O(n)",               -- Performance hint: O(1), O(n), O(n²), etc.
  description = "What this shader does",
  
  -- Feature flags
  supportsNative = true,             -- Has C++ implementation
  requiresGeometry = true,           -- Needs neighbor voxel data
  requiresDepth = false,             -- Needs camera distance
  requiresNormals = true,            -- Needs face normals
  
  -- Input/output capabilities
  inputs = {
    "base_color",                    -- Can read original voxel color
    "previous_shader",               -- Can read previous shader output
    "geometry",                      -- Can read voxel positions
    "normals"                        -- Can read face normals
  },
  outputs = {
    "color",                         -- Produces color output
    "alpha"                          -- Produces alpha output
  }
}

-- Shader parameter schema (for auto-UI generation)
shaderInterface.ParamSchema = {
  {
    name = "intensity",
    type = "slider",                 -- slider, color, vector, bool, choice, material
    min = 0,
    max = 100,
    default = 50,
    label = "Intensity",
    tooltip = "Controls shader strength"
  },
  -- ... more parameters
}

-- Main shader interface
function shaderInterface.process(shaderData, params)
  -- shaderData structure:
  -- {
  --   faces = { {voxel={x,y,z}, face="top", normal={x,y,z}, color={r,g,b,a}, ...}, ... },
  --   voxels = { {x,y,z, color={r,g,b,a}, neighbors={...}}, ... },
  --   camera = {position={x,y,z}, rotation={x,y,z}, direction={x,y,z}, fov=45, ...},
  --   modelBounds = {minX, maxX, minY, maxY, minZ, maxZ},
  --   middlePoint = {x, y, z},
  --   width = 400,
  --   height = 400,
  --   voxelSize = 2.5
  -- }
  --
  -- params: table of shader-specific parameters
  --
  -- Returns: modified shaderData (with updated face colors)
  
  return shaderData
end

-- Optional: Custom UI builder (overrides auto-generated UI)
function shaderInterface.buildUI(dlg, params, onChange)
  -- dlg: Aseprite Dialog object
  -- params: current parameter values
  -- onChange: callback(newParams) when user changes values
  
  -- If not implemented, UI is auto-generated from ParamSchema
end

return shaderInterface
```

---

## 1.4 Shader Stack Execution Engine

### `shader_stack.lua` (NEW)

```lua
-- Executes shader pipeline (lighting → FX) with input routing

local shaderStack = {}

-- Shader registry (auto-populated on load)
shaderStack.registry = {
  lighting = {},  -- { shader_id = shaderModule, ... }
  fx = {}
}

-- Auto-register shaders from folders
function shaderStack.loadShaders()
  local fs = app.fs
  local shaderDirs = {
    lighting = fs.joinPath(AseVoxel.extensionPath, "render", "shaders", "lighting"),
    fx = fs.joinPath(AseVoxel.extensionPath, "render", "shaders", "fx")
  }
  
  for category, dir in pairs(shaderDirs) do
    if fs.isDirectory(dir) then
      for _, file in ipairs(fs.listFiles(dir)) do
        if file:match("%.lua$") then
          local shaderPath = fs.joinPath(dir, file)
          local shaderModule = dofile(shaderPath)
          
          if shaderModule and shaderModule.info and shaderModule.info.id then
            local shaderId = shaderModule.info.id
            
            -- Check for native implementation
            local hasNative = false
            if nativeBridge and nativeBridge.hasNativeShader then
              hasNative = nativeBridge.hasNativeShader(shaderId)
            end
            
            -- Check for Lua implementation
            local hasLua = (type(shaderModule.process) == "function")
            
            if not hasNative and not hasLua then
              print("[AseVoxel] Shader " .. shaderId .. " has no implementation (Lua or Native), skipping")
            else
              shaderStack.registry[category][shaderId] = shaderModule
              print("[AseVoxel] Registered shader: " .. shaderId .. 
                    (hasNative and " [Native]" or "") .. 
                    (hasLua and " [Lua]" or ""))
            end
          else
            print("[AseVoxel] Invalid shader file: " .. file)
          end
        end
      end
    end
  end
  
  -- Load user shaders from preferences folder (future)
  -- ...existing code...
end

-- Execute full shader stack
function shaderStack.execute(shaderData, stackConfig)
  -- stackConfig = {
  --   lighting = {
  --     { id="dynamic_light", enabled=true, params={...}, inputFrom="base_color" },
  --     { id="ambient_occlusion", enabled=true, params={...}, inputFrom="previous" }
  --   },
  --   fx = {
  --     { id="faceshade", enabled=true, params={...}, inputFrom="previous" },
  --     { id="outline", enabled=false, params={...}, inputFrom="geometry" }
  --   }
  -- }
  
  local result = shaderData
  
  -- Phase 1: Lighting shaders (top to bottom)
  for _, shaderEntry in ipairs(stackConfig.lighting or {}) do
    if shaderEntry.enabled then
      -- ...existing code... (route input, call shader.process, merge output)
    end
  end
  
  -- Phase 2: FX shaders (top to bottom)
  for _, shaderEntry in ipairs(stackConfig.fx or {}) do
    if shaderEntry.enabled then
      -- ...existing code... (route input, call shader.process, merge output)
    end
  end
  
  return result
end

-- Validate shader stack (check dependencies, circular refs, etc.)
function shaderStack.validate(stackConfig)
  -- ...existing code...
end

return shaderStack
```

---

## 1.5 Extracted Shader Modules

### `render/shaders/lighting/basic.lua` (NEW)

Extract from `shading.lua::basicModeBrightness()`:

```lua
-- Basic front-facing lighting (normal to camera)

local basicLight = {}

basicLight.info = {
  id = "basicLight",
  name = "Basic Light",
  version = "1.0.0",
  author = "AseVoxel",
  category = "lighting",
  complexity = "O(n)",
  description = "Simple camera-facing lighting - faces toward camera are lit, faces away are shaded",
  supportsNative = true,
  requiresNormals = true,
  inputs = {"base_color", "normals"},
  outputs = {"color"}
}

basicLight.paramSchema = {
  {name="lightIntensity", type="slider", min=0, max=100, default=50, label="Light Intensity"},
  {name="shadeIntensity", type="slider", min=0, max=100, default=50, label="Shade Intensity"}
}

function basicLight.process(shaderData, params)
  -- Algorithm:
  -- 1. For each face, compute dot(faceNormal, cameraDirection)
  -- 2. Map dot from [-1, 1] to [shadeIntensity, lightIntensity]
  -- 3. brightness = shadeIntensity + (lightIntensity - shadeIntensity) * ((dot + 1) / 2)
  -- 4. Multiply face RGB by (brightness / 100)
  
  -- For each face in shaderData.faces:
  --   1. Compute dot product: dot(faceNormal, cameraDirection)
  --   2. If dot > 0 (facing camera): apply light intensity
  --   3. If dot < 0 (facing away): apply shade intensity
  --   4. Brightness = lerp(shadeIntensity, lightIntensity, (dot+1)/2)
  --   5. Multiply face RGB by (brightness/100)
  
  return shaderData
end

return basicLight
```

### `render/shaders/lighting/dynamic.lua` (NEW)

Extract from `shading.lua` + `preview_renderer.lua` dynamic lighting code:

```lua
-- Physically-inspired lighting with pitch/yaw/diffuse/ambient/rim

local dynamicLight = {}

dynamicLight.info = {
  id = "dynamic_light_v1",
  name = "Dynamic Lighting",
  version = "1.0.0",
  author = "AseVoxel",
  category = "lighting",
  complexity = "O(n)",
  description = "Advanced lighting with directional light, falloff, and rim",
  supportsNative = true,
  requiresNormals = true,
  requiresGeometry = true,  -- For radial attenuation
  inputs = {"base_color", "normals", "geometry"},
  outputs = {"color"}
}

dynamicLight.paramSchema = {
  {name="pitch", type="slider", min=-90, max=90, default=25, label="Pitch"},
  {name="yaw", type="slider", min=0, max=360, default=25, label="Yaw"},
  {name="diffuse", type="slider", min=0, max=100, default=60, label="Diffuse"},
  {name="ambient", type="slider", min=0, max=100, default=30, label="Ambient"},
  {name="diameter", type="slider", min=0, max=200, default=100, label="Diameter"},
  {name="rimEnabled", type="bool", default=false, label="Rim Lighting"},
  {name="lightColor", type="color", default={r=255,g=255,b=255}, label="Light Color"}
}

function dynamicLight.process(shaderData, params)
  -- ...existing code... (port dynamic lighting logic from shading.lua)
  -- 1. Compute light direction from pitch/yaw
  -- 2. Cache rotated normals
  -- 3. For each face:
  --    a. Compute Lambert diffuse (ndotl ^ exponent)
  --    b. Apply radial attenuation (perpendicular distance from axis)
  --    c. Add ambient term
  --    d. Optionally add rim lighting (Fresnel)
  --    e. Multiply base color by lighting factors
  
  return shaderData
end

return dynamicLight
```

### `render/shaders/fx/faceshade.lua` (NEW)

Extract from `fx_stack.lua`:

```lua
-- Fixed face brightness based on model-center normals (Alpha Full only)

local faceshade = {}

faceshade.info = {
  id = "faceshade",
  name = "FaceShade",
  version = "1.0.0",
  author = "AseVoxel",
  category = "fx",
  complexity = "O(n)",
  description = "Shade faces based on model-center axis (brightness multiplier only)",
  supportsNative = true,
  requiresNormals = true,
  inputs = {"previous_shader"},
  outputs = {"color"}
}

faceshade.paramSchema = {
  {name="topBrightness", type="slider", min=0, max=255, default=255, label="Top"},
  {name="bottomBrightness", type="slider", min=0, max=255, default=128, label="Bottom"},
  {name="frontBrightness", type="slider", min=0, max=255, default=200, label="Front"},
  {name="backBrightness", type="slider", min=0, max=255, default=150, label="Back"},
  {name="leftBrightness", type="slider", min=0, max=255, default=180, label="Left"},
  {name="rightBrightness", type="slider", min=0, max=255, default=220, label="Right"}
}

function faceshade.process(shaderData, params)
  -- For each face:
  --   1. Determine face direction from model center (not camera): top/bottom/front/back/left/right
  --   2. Get corresponding brightness (0-255)
  --   3. Multiply RGB by (brightness/255), alpha unchanged
  -- NOTE: ONLY Alpha Full mode - no literal, material, or tint support
  
  return shaderData
end

return faceshade
```

### `render/shaders/fx/faceshade_camera.lua` (NEW - replaces old FaceShade Camera concept)

```lua
-- Camera-relative face shading (no back faces)

local faceshadeCamera = {}

faceshadeCamera.info = {
  id = "faceshadeCamera",
  name = "FaceShade (Camera)",
  version = "1.0.0",
  author = "AseVoxel",
  category = "fx",
  complexity = "O(n)",
  description = "Shade faces based on camera projection (Alpha Full only)",
  supportsNative = true,
  requiresNormals = true,
  inputs = {"previous_shader"},
  outputs = {"color"}
}

faceshadeCamera.paramSchema = {
  {name="frontBrightness", type="slider", min=0, max=255, default=255, label="Front"},
  {name="topBrightness", type="slider", min=0, max=255, default=220, label="Top"},
  {name="leftBrightness", type="slider", min=0, max=255, default=180, label="Left"},
  {name="rightBrightness", type="slider", min=0, max=255, default=200, label="Right"},
  {name="bottomBrightness", type="slider", min=0, max=255, default=128, label="Bottom"}
  -- NO backBrightness - back faces don't show in camera projection
}

function faceshadeCamera.process(shaderData, params)
  -- For each visible face:
  --   1. Project face normal to camera view space
  --   2. Determine dominant direction: front/top/left/right/bottom
  --   3. Back faces are never visible (culled/occluded)
  --   4. Apply corresponding brightness: RGB *= (brightness/255)
  -- NOTE: ONLY Alpha Full mode - no literal, material, or tint support
  
  return shaderData
end

return faceshadeCamera
```

### `render/shaders/fx/iso.lua` (NEW)

Extract from `fx_stack.lua`:

```lua
-- Isometric shading with Alpha/Literal modes and Material/Full options

local iso = {}

iso.info = {
  id = "iso",
  name = "Isometric Shade",
  version = "1.0.0",
  author = "AseVoxel",
  category = "fx",
  complexity = "O(n)",
  description = "Classic isometric look with Alpha/Literal modes, Material filtering, optional Tint",
  supportsNative = true,
  requiresNormals = true,
  inputs = {"previous_shader"},
  outputs = {"color"}
}

iso.paramSchema = {
  {name="shadingMode", type="choice", options={"alpha", "literal"}, default="alpha", label="Mode"},
  {name="materialMode", type="bool", default=false, label="Material Mode (skip pure colors)"},
  {name="enableTint", type="bool", default=false, label="Enable Tint (Alpha mode)"},
  {name="alphaTint", type="color", default={r=255, g=255, b=255}, label="Tint Color"},
  {name="topBrightness", type="slider", min=0, max=255, default=255, label="Top/Bottom"},
  {name="leftBrightness", type="slider", min=0, max=255, default=180, label="Left"},
  {name="rightBrightness", type="slider", min=0, max=255, default=220, label="Right"}
}

function iso.process(shaderData, params)
  -- For each face:
  --   1. Determine: top (normal.y dominant), left/right (camera X projection)
  --   2. Bottom uses topBrightness
  --   
  --   If materialMode:
  --     - Check if RGB is pure color (one channel 255, others 0/near-0)
  --     - If pure, skip this face
  --   
  --   If shadingMode == "alpha":
  --     - brightness = face orientation brightness (0-255)
  --     - If enableTint: RGB *= (brightness/255) * (tint/255)
  --     - Else: RGB *= (brightness/255)
  --   
  --   If shadingMode == "literal":
  --     - Replace RGB with {brightness, brightness, brightness}
  
  return shaderData
end

return iso
```

---

## 1.6 Native Bridge Integration

### `native_bridge.lua` (MODIFIED)

```lua
-- ...existing code...

-- NEW: Unified native render that accepts shader stack
function nativeBridge.renderUnified(voxels, params, shaderStack)
  -- shaderStack = {
  --   lighting = { {id="basic_light_v1", params={...}}, ... },
  --   fx = { {id="faceshade_v1", params={...}}, ... }
  -- }
  
  -- Check if ALL shaders in stack have native implementations
  local allNative = true
  for _, entry in ipairs(shaderStack.lighting or {}) do
    if not nativeBridge.hasNativeShader(entry.id) then
      allNative = false
      break
    end
  end
  for _, entry in ipairs(shaderStack.fx or {}) do
    if not nativeBridge.hasNativeShader(entry.id) then
      allNative = false
      break
    end
  end
  
  if allNative then
    -- Pure native path: all shaders in C++
    return asevoxel_native.render_unified(voxels, params, shaderStack)
  else
    -- Hybrid path: mix native + Lua shaders
    return nativeBridge.renderHybrid(voxels, params, shaderStack)
  end
end

function nativeBridge.renderHybrid(voxels, params, shaderStack)
  -- Execute native shaders in C++, Lua shaders via callback
  -- Native renderer calls Lua functions for missing shaders
  -- ...existing code...
end

-- ...existing code...
```

### asevoxel_native.cpp (MODIFIED)

```cpp
// ...existing code...

// NEW: Unified renderer that accepts shader stack
static int l_render_unified(lua_State* L) {
  // Args: (voxels, params, shaderStack)
  // ...existing code... (parse voxels array, params)
  
  // Parse shader stack
  lua_getfield(L, 3, "lighting");
  // ...existing code... (iterate lighting shaders, check if native impl exists)
  
  lua_getfield(L, 3, "fx");
  // ...existing code... (iterate FX shaders, check if native impl exists)
  
  // Execute shader pipeline:
  // 1. Geometry pass (visibility, depth sort) - reuse existing logic
  // 2. Lighting pass (call native shader functions or Lua callbacks)
  // 3. FX pass (call native shader functions or Lua callbacks)
  // 4. Rasterize final colors
  
  // ...existing code... (build Image, return)
}

// Native shader implementations (called by render_unified)
namespace shaders {
  void apply_basic_light(FacePoly* faces, int count, BasicLightParams params) {
    // ...existing code... (port render_basic lighting logic)
  }
  
  void apply_dynamic_light(FacePoly* faces, int count, DynamicLightParams params) {
    // ...existing code... (port render_dynamic lighting logic)
  }
  
  void apply_faceshade(FacePoly* faces, int count, FaceShadeParams params) {
    // ...existing code... (port render_stack faceshade logic)
  }
  
  void apply_iso(FacePoly* faces, int count, IsoParams params) {
    // ...existing code... (port render_stack iso logic)
  }
}

static const luaL_Reg FUNCS[] = {
  // ...existing code...
  {"render_unified", l_render_unified},  // NEW
  // Keep old functions for backward compat (marked deprecated):
  {"render_basic", l_render_basic},      // DEPRECATED
  {"render_dynamic", l_render_dynamic},  // DEPRECATED
  {"render_stack", l_render_stack},      // DEPRECATED
  {nullptr, nullptr}
};
```

---

## 1.7 Migration Layer (Backward Compatibility)

### `preview_renderer.lua` (MODIFIED)

```lua
-- ...existing code...

function previewRenderer.renderVoxelModel(model, params)
  _initModules()
  params = params or {}
  
  -- AUTO-MIGRATE LEGACY PARAMS
  if params.shadingMode then
    params.shaderStack = previewRenderer.migrateLegacyMode(params.shadingMode, params)
    print("[AseVoxel] Auto-migrated legacy shadingMode to shader stack")
  end
  
  -- NEW: Use shader stack if present
  if params.shaderStack then
    return previewRenderer.renderWithShaderStack(model, params)
  end
  
  -- FALLBACK: Old path (should never reach here after migration)
  return previewRenderer.renderPreview(model, params)
end

-- NEW: Migration logic
function previewRenderer.migrateLegacyMode(shadingMode, params)
  local stack = { lighting = {}, fx = {} }
  
  if shadingMode == "Basic" or shadingMode == "Simple" then
    table.insert(stack.lighting, {
      id = "basic_light_v1",
      enabled = true,
      params = {
        basicShadeIntensity = params.basicShadeIntensity or 50,
        basicLightIntensity = params.basicLightIntensity or 50
      },
      inputFrom = "base_color"
    })
  
  elseif shadingMode == "Dynamic" or shadingMode == "Complete" then
    table.insert(stack.lighting, {
      id = "dynamic_light_v1",
      enabled = true,
      params = {
        pitch = params.lighting and params.lighting.pitch or 25,
        yaw = params.lighting and params.lighting.yaw or 25,
        diffuse = params.lighting and params.lighting.diffuse or 60,
        ambient = params.lighting and params.lighting.ambient or 30,
        diameter = params.lighting and params.lighting.diameter or 100,
        rimEnabled = params.lighting and params.lighting.rimEnabled or false,
        lightColor = params.lighting and params.lighting.lightColor or {r=255,g=255,b=255}
      },
      inputFrom = "base_color"
    })
  
  elseif shadingMode == "Stack" then
    -- Parse old fxStack format
    if params.fxStack and params.fxStack.modules then
      for _, module in ipairs(params.fxStack.modules) do
        if module.shape == "FaceShade" then
          table.insert(stack.fx, {
            id = "faceshade_v1",
            enabled = true,
            params = {
              -- ...existing code... (extract colors from module)
            },
            inputFrom = "previous"
          })
        elseif module.shape == "Iso" then
          table.insert(stack.fx, {
            id = "iso_v1",
            enabled = true,
            params = { intensity = 100 },
            inputFrom = "previous"
          })
        end
      end
    end
  end
  
  return stack
end

-- NEW: Render with shader stack
function previewRenderer.renderWithShaderStack(model, params)
  local shaderStack = require("render.shader_stack")
  
  -- Build shaderData structure
  local shaderData = previewRenderer.buildShaderData(model, params)
  
  -- Execute shader stack
  local result = shaderStack.execute(shaderData, params.shaderStack)
  
  -- Rasterize final image
  return previewRenderer.rasterizeShaderResult(result, params)
end

-- ...existing code...
```

---

## 1.8 UI Changes (Phase 1: Minimal)

### Current UI Tabs:
```
[Render] [Lighting] [Effects] [Animation] [Export] [Debug]
```

### Phase 1 UI (Backward Compatible):
```
[Render] [Lighting] [Shader Stack] [Animation] [Export] [Debug]
```

**"Lighting" Tab** (DEPRECATED but kept):
- Add banner: "⚠️ Legacy mode. Switch to Shader Stack for advanced control."
- Keep existing Basic/Dynamic/Stack radio buttons (auto-migrate on selection)

**"Shader Stack" Tab** (NEW):
```
┌─────────────────────────────────────────────┐
│ 🔦 LIGHTING SHADERS                         │
├─────────────────────────────────────────────┤
│ ☑ Basic Light                    [↑] [↓] [×]│
│   [Open parameters]                         │
│                                             │
├─────────────────────────────────────────────┤
| (popupdialog)

├─────────────────────────────────────────────┤
│ [+ Add Lighting Shader ▼]                   │
│    ├─ Basic Light                           │ │
│    ├─ Dynamic Light                         │ │
│    ├─ Ambient Occlusion                     │ │
│    ├─ Hemisphere Light                      │ │
│    ├─ Point Light                           │ │
│    ├─ Directional Light                     │ │
│    └─ Emissive                              │ │
└─────────────────────────────────────────────┘

┌─────────────────────────────────────────────┐
│ 🎨 FX SHADERS                               │
├─────────────────────────────────────────────┤
│ (empty - click "+" to add)                  │
├─────────────────────────────────────────────┤
│ [+ Add FX Shader ▼]                         │
│    ├─ FaceShade                             │ │
│    ├─ FaceShade (Camera)                    │ │
│    ├─ Iso                                   │ │
│    ├─ Outline                               │ │
│    ├─ Palette Mapping                       │ │
│    ├─ Dither                                │ │
│    ├─ Cel Shade                             │ │
│    ├─ Fresnel                               │ │
│    ├─ Gradient Map                          │ │
│    ├─ Fog                                   │ │
│    ├─ Bloom                                 │ │
│    ├─ Vignette                              │ │
│    ├─ Chromatic Aberration                  │ │
│    └─ Pixelate                              │ │
│  └─────────────────────────────────────────────┘
│                                             │
│  [Clear All]  [Load Preset ▼]  [Save Preset]│
└─────────────────────────────────────────────┘
```

---

## 1.9 Scene File Format (.asevoxel)

### Scene Archive Structure:
```
scene.asevoxel  (ZIP archive renamed)
  ├─ manifest.json
  ├─ model.aseprite  (or model.png / model.gif)
  ├─ shader_stack.json
  └─ shaders/  (optional: bundled custom shaders)
      ├─ custom_light_01.lua
      └─ custom_light_01.json
```

### `manifest.json`:
```json
{
  "version": "1.0",
  "aseVoxelVersion": "1.5.0",
  "modelFile": "model.aseprite",
  "created": "2025-01-15T10:30:00Z",
  "author": "User Name"
}
```

### `shader_stack.json`:
```json
{
  "version": "1.0",
  "camera": {
    "xRotation": 25,
    "yRotation": 45,
    "zRotation": 0,
    "orthogonal": false,
    "fovDegrees": 45,
    "perspectiveScaleRef": "middle"
  },
  "render": {
    "width": 400,
    "height": 400,
    "scale": 2.0,
    "backgroundColor": {"r": 0, "g": 0, "b": 0, "a": 0}
  },
  "shaderStack": {
    "lighting": [
      {
        "id": "dynamic_light_v1",
        "enabled": true,
        "name": "Main Light",  // User-renamed
        "inputFrom": "base_color",
        "params": {
          "pitch": 25,
          "yaw": 45,
          "diffuse": 60,
          "ambient": 30,
          "diameter": 100,
          "rimEnabled": true,
          "lightColor": {"r": 255, "g": 230, "b": 200}
        }
      }
    ],
    "fx": [
      {
        "id": "faceshade_v1",
        "enabled": true,
        "name": "FaceShade",
        "inputFrom": "previous",
        "params": {
          "topBrightness": 255,
          "bottomBrightness": 100,
          "frontBrightness": 200,
          "backBrightness": 150,
          "leftBrightness": 180,
          "rightBrightness": 220
        }
      }
    ]
  }
}
```

---

## 1.10 Shader Parameter Widget System (Auto-UI)

### `render/shader_ui.lua` (NEW)

```lua
-- Auto-generate UI from shader parameter schemas

local shaderUI = {}

-- Widget builders for each parameter type
shaderUI.widgets = {
  slider = function(dlg, param, value, onChange)
    dlg:slider{
      id = param.name,
      label = param.label or param.name,
      min = param.min or 0,
      max = param.max or 100,
      value = value or param.default,
      onchange = function() onChange(param.name, dlg.data[param.name]) end
    }
  end,
  
  color = function(dlg, param, value, onChange)
    local c = value or param.default or {r=255, g=255, b=255}
    dlg:color{
      id = param.name,
      label = param.label or param.name,
      color = Color(c.r, c.g, c.b),
      onchange = function()
        local col = dlg.data[param.name]
        onChange(param.name, {r=col.red, g=col.green, b=col.blue})
      end
    }
  end,
  
  bool = function(dlg, param, value, onChange)
    dlg:check{
      id = param.name,
      label = param.label or param.name,
      selected = value or param.default or false,
      onchange = function() onChange(param.name, dlg.data[param.name]) end
    }
  end,
  
  vector = function(dlg, param, value, onChange)
    -- Pitch + Yaw sliders with optional cone preview
    local v = value or param.default or {pitch=0, yaw=0}
    dlg:slider{
      id = param.name .. "_pitch",
      label = (param.label or param.name) .. " Pitch",
      min = param.pitchMin or -90,
      max = param.pitchMax or 90,
      value = v.pitch,
      onchange = function()
        onChange(param.name, {
          pitch = dlg.data[param.name .. "_pitch"],
          yaw = dlg.data[param.name .. "_yaw"]
        })
      end
    }
    dlg:slider{
      id = param.name .. "_yaw",
      label = (param.label or param.name) .. " Yaw",
      min = param.yawMin or 0,
      max = param.yawMax or 360,
      value = v.yaw,
      onchange = function()
        onChange(param.name, {
          pitch = dlg.data[param.name .. "_pitch"],
          yaw = dlg.data[param.name .. "_yaw"]
        })
      end
    }
  end,
  
  material = function(dlg, param, value, onChange)
    -- Color picker + material selector (opaque/glass/metal/etc)
    local v = value or param.default or {r=255, g=255, b=255, type="opaque"}
    dlg:color{
      id = param.name .. "_color",
      label = param.label or param.name,
      color = Color(v.r, v.g, v.b),
      onchange = function()
        local col = dlg.data[param.name .. "_color"]
        onChange(param.name, {
          r = col.red, g = col.green, b = col.blue,
          type = dlg.data[param.name .. "_type"]
        })
      end
    }
    dlg:combobox{
      id = param.name .. "_type",
      option = v.type,
      options = {"opaque", "glass", "metal", "emissive", "dither"},
      onchange = function()
        local col = dlg.data[param.name .. "_color"]
        onChange(param.name, {
          r = col.red, g = col.green, b = col.blue,
          type = dlg.data[param.name .. "_type"]
        })
      end
    }
  end,
  
  choice = function(dlg, param, value, onChange)
    dlg:combobox{
      id = param.name,
      label = param.label or param.name,
      option = value or param.default,
      options = param.options or {"option1", "option2"},
      onchange = function() onChange(param.name, dlg.data[param.name]) end
    }
  end
}

-- Build UI for shader (auto-generated or custom)
function shaderUI.buildShaderUI(dlg, shader, params, onChange)
  if shader.buildUI then
    -- Custom UI provided by shader
    shader.buildUI(dlg, params, onChange)
  else
    -- Auto-generate from param schema
    for _, paramDef in ipairs(shader.paramSchema or {}) do
      local widgetBuilder = shaderUI.widgets[paramDef.type]
      if widgetBuilder then
        widgetBuilder(dlg, paramDef, params[paramDef.name], onChange)
      else
        print("[AseVoxel] Unknown param type: " .. tostring(paramDef.type))
      end
    end
  end
end

return shaderUI
```

---

## 1.11 Shader Auto-Registration

### `shader_stack.lua::loadShaders()` (IMPLEMENTATION)

```lua
-- ...existing code...

function shaderStack.loadShaders()
  local fs = app.fs
  local shaderDirs = {
    lighting = fs.joinPath(AseVoxel.extensionPath, "render", "shaders", "lighting"),
    fx = fs.joinPath(AseVoxel.extensionPath, "render", "shaders", "fx")
  }
  
  for category, dir in pairs(shaderDirs) do
    if fs.isDirectory(dir) then
      for _, file in ipairs(fs.listFiles(dir)) do
        if file:match("%.lua$") then
          local shaderPath = fs.joinPath(dir, file)
          local shaderModule = dofile(shaderPath)
          
          if shaderModule and shaderModule.info and shaderModule.info.id then
            local shaderId = shaderModule.info.id
            
            -- Check for native implementation
            local hasNative = false
            if nativeBridge and nativeBridge.hasNativeShader then
              hasNative = nativeBridge.hasNativeShader(shaderId)
            end
            
            -- Check for Lua implementation
            local hasLua = (type(shaderModule.process) == "function")
            
            if not hasNative and not hasLua then
              print("[AseVoxel] Shader " .. shaderId .. " has no implementation (Lua or Native), skipping")
            else
              shaderStack.registry[category][shaderId] = shaderModule
              print("[AseVoxel] Registered shader: " .. shaderId .. 
                    (hasNative and " [Native]" or "") .. 
                    (hasLua and " [Lua]" or ""))
            end
          else
            print("[AseVoxel] Invalid shader file: " .. file)
          end
        end
      end
    end
  end
  
  -- Load user shaders from preferences folder (future)
  -- ...existing code...
end

-- Call on module load
shaderStack.loadShaders()

-- ...existing code...
```

---

## 1.12 Order of Implementation (Suggested)

### Week 1: Core Infrastructure
1. ✅ Create `shader_interface.lua` (protocol definition)
2. ✅ Create `shader_stack.lua` (execution engine skeleton)
3. ✅ Create `shader_ui.lua` (auto-UI generator)
4. ✅ Extract basic.lua (working implementation)
5. ✅ Test Basic Light shader in isolation (unit test)

### Week 2: Extract Remaining Shaders
6. ✅ Extract dynamic.lua
7. ✅ Extract faceshade.lua
8. ✅ Extract iso.lua
9. ✅ Implement `previewRenderer.migrateLegacyMode()`
10. ✅ Test migration layer (verify verbatim output)

### Week 3: Native Integration
11. ✅ Modify asevoxel_native.cpp (add `render_unified`)
12. ✅ Implement native versions of 4 core shaders
13. ✅ Implement hybrid path (Native + Lua shader mixing)
14. ✅ Performance testing (verify no regression)

### Week 4: UI & Polish
15. ✅ Add "Shader Stack" tab to main dialog
16. ✅ Implement shader list (collapsible, reorderable)
17. ✅ Implement "Add Shader" dropdown menu
18. ✅ Implement scene save/load (.asevoxel format)
19. ✅ Documentation + deprecation warnings

---

## 1.13 Success Criteria (Phase 1)

### Visual Output
- ✅ `shadingMode="Basic"` → Shader Stack → **Identical** rendered image (pixel-perfect)
- ✅ `shadingMode="Dynamic"` → Shader Stack → **Identical** rendered image
- ✅ `shadingMode="Stack"` (old FX) → Shader Stack → **Identical** rendered image

### Performance
- ✅ Native path: **Same or better** performance vs old `render_basic/dynamic/stack`
- ✅ Lua path: **No worse than 10% slower** (acceptable for extensibility)
- ✅ Hybrid path: **Graceful degradation** when mixing Native + Lua

### Backward Compatibility
- ✅ Old scene files auto-migrate on load (one-time conversion)
- ✅ Old API calls (`params.shadingMode`) still work (with deprecation warning)
- ✅ No breaking changes to existing user workflows

### Extensibility
- ✅ User can drop `.lua` shader in lighting → Auto-loads
- ✅ User can write custom shader without modifying core code
- ✅ Shader UI auto-generates from `paramSchema`

---

## Questions for Clarification

Based on your responses:

### 1. **Shader Input Routing** ✅ ANSWERED
You chose **B) Graph-Based**: Shaders can reference:
- `base_color` (original voxel color)
- `previous` (previous shader output)
- `geometry` (voxel positions)
- `normals` (face normals)
- Any named shader output (e.g. `dynamicLight_01`)

**Implementation**: Add `inputFrom` field to shader stack entries.

### 2. **Native Shader Fallback** ✅ ANSWERED
You chose: **Native tries C++ first, falls back to Lua, errors if neither exists**

**Implementation**: `nativeBridge.renderUnified()` checks shader registry, calls native if available, else calls Lua, else logs error and disables shader.

### 3. **Shader Registration** ✅ ANSWERED
You chose **C) Auto-register on load** + batch install for user packs

**Implementation**: `shaderStack.loadShaders()` scans folders on startup. User packs install to prefs folder.

### 4. **Backward Compat** ✅ ANSWERED
You chose **C) Complete refactor with deprecation**

**Implementation**: Auto-migrate old params, show warning, remove legacy code in v2.0.

### 5. **UI Interaction** ✅ ANSWERED
You chose **B) Separate stacks (Lighting + FX) but with cross-referencing**

**Implementation**: Two collapsible sections in UI. `inputFrom` dropdown shows options from both stacks.

### 6. **Scene Files** ✅ ANSWERED
You chose **B) Relative paths** + save position/rotation per model (future multi-model scenes)

**Implementation**: Scene JSON stores shader IDs (relative), camera per model (future), icon preview.

### 7. **Shader Execution** ✅ ANSWERED
You chose **B) Layered** - each shader outputs color+alpha, combine at end

**Implementation**: Lighting shaders multiply colors (additive), FX shaders process sequentially.

### 8. **Rendering API** ✅ ANSWERED
You chose **B) Per-Face API**

**Implementation**: `shaderData.faces` array with per-face color/normal/depth.

### 9. **UI Generation** ✅ ANSWERED
You chose **B) Declarative UI from schema** (with opt-out for custom)

**Implementation**: `shader_ui.lua` auto-generates widgets. Shader sets `buildUI` to override.

### 10. **Complexity Warnings** ✅ ANSWERED
You chose **B) Warn on stack** when total time exceeds threshold

**Implementation**: Profiler measures shader times, shows warning if >100ms for current rotation.

---

## Next Steps

1. **Review this proposal** - Does the Phase 1 plan match your vision? YES
2. **Approve extraction order** - Start with Basic Light, then Dynamic, then FX
3. **Confirm UI mockup** - Does the "Shader Stack" tab layout work? YES
4. **Shader naming** - Any preference changes (e.g. "basic_light_v1" vs "basicLight")? basicLight, version in json manifest
5. **Priority questions** - Which shaders need native C++ first (Outline? Palette Map)? exactly those two

Once approved, I'll start implementing Phase 1 (Core Infrastructure + Basic Light extraction) as a PR-ready refactor! 🚀
