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
- **Purpose**: Simple top-down directional lighting
- **Parameters**:
  - Light intensity (0-100%)
  - Shade intensity (0-100%)
- **Output**: Per-face RGB with basic top/side/bottom differentiation

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
  - Top face brightness (0-255)
  - Bottom face brightness (0-255)
  - Front face brightness (0-255)
  - Back face brightness (0-255)
  - Left face brightness (0-255)
  - Right face brightness (0-255)
- **Output**: Multiplies face colors by direction-based factors

#### 9. **FaceShade Camera** (NEW)
- **Purpose**: Shade faces based on camera-normal angle instead of model-center
- **Parameters**:
  - Front-facing brightness (0-255) - faces toward camera
  - Side-facing brightness (0-255) - faces 45° to camera
  - Away-facing brightness (0-255) - faces away from camera
  - Gradient smoothness (0-100%)
- **Output**: Smooth gradient based on dot(faceNormal, cameraDirection)
- **Benefit**: More realistic than fixed face shading, camera-dependent

#### 10. **Iso** (existing, refactored)
- **Purpose**: Fixed isometric shading (top=bright, sides=medium, etc.)
- **Parameters**:
  - Preset intensity (0-100%)
- **Output**: Classic isometric look regardless of rotation

#### 11. **Outline** (NEW)
- **Purpose**: Draw outlines around geometry edges
- **Parameters**:
  - **Detection Mode**: 
    - Geometry (elevation changes)
    - Material (color changes)
    - Both
  - **Outline Width**: 0.1 to 2.0 voxels
  - **Outline Color**: RGB or "contrast" (auto-calculate from voxel color)
  - **Direction Mask**: Which directions to check (X+, X-, Y+, Y-, Z+, Z-)
  - **Threshold**: Minimum difference to trigger outline
  - **Placement**: Outside, Inside, Both
  - **Depth Offset**: Push outline forward/back slightly
- **Output**: Draws outline voxels/faces where discontinuities detected
- **Algorithm**: For each visible face, check if neighbor voxel exists in selected directions; if missing or different material, draw outline

#### 12. **Palette Mapping** (NEW)
- **Purpose**: Quantize colors to limited palette (NES/GB style)
- **Parameters**:
  - **Palette Source**: 
    - Custom palette (user-defined colors)
    - Sprite palette (from current sprite)
    - Generated (auto-generate N colors from model)
  - **Max Colors**: 2-256 colors total
  - **Subsprite Grid**: Enable NES-style 8x8 tile constraints
    - Grid origin (X, Y)
    - Grid size (4x4, 8x8, 16x16, 32x32)
    - Colors per subsprite (2-4)
  - **Mapping Algorithm**:
    - Nearest luminosity
    - Nearest hue
    - Nearest saturation
    - Nearest euclidean (RGB distance)
    - Weighted combination
  - **Locked Colors**: Don't remap specific colors (keep transparency, keep black, etc.)
  - **Dithering**: None, Bayer 2x2, Bayer 4x4, Bayer 8x8, Floyd-Steinberg, Ordered
- **Output**: Remapped colors per face/voxel
- **Use Case**: Retro aesthetics, NES/GB/C64 palette constraints

#### 13. **Dither** (NEW)
- **Purpose**: Apply dithering patterns for color reduction or artistic effect
- **Parameters**:
  - **Pattern Type**: Bayer 2x2/4x4/8x8, Ordered, Random, Blue Noise, Floyd-Steinberg
  - **Intensity**: 0-100%
  - **Color Reduction**: Bits per channel (1-8)
  - **Pattern Scale**: 1x, 2x, 4x
  - **Apply To**: RGB, Alpha, Luminosity only
- **Output**: Dithered color values
- **Use Case**: Retro pixelart look, simulate CRT, reduce banding

#### 14. **Cel Shade** (NEW)
- **Purpose**: Posterize lighting into distinct bands (toon shading)
- **Parameters**:
  - Number of bands (2-8)
  - Band edges (adjustable thresholds)
  - Band smoothness (sharp vs gradient transitions)
  - Outline integration (combine with outline shader)
- **Output**: Quantized lighting levels
- **Use Case**: Anime/cartoon aesthetics

#### 15. **Fresnel** (NEW)
- **Purpose**: Highlight edges based on viewing angle (rim glow)
- **Parameters**:
  - Fresnel power (1-5)
  - Edge color (RGB)
  - Edge intensity (0-200%)
  - Affected by lighting (bool - respect previous lighting or override)
- **Output**: Adds glow to faces perpendicular to camera
- **Use Case**: Glass, force fields, magical effects

#### 16. **Gradient Map** (NEW)
- **Purpose**: Remap luminosity to color gradient (like Photoshop Gradient Map)
- **Parameters**:
  - Gradient stops (2-8 colors with positions 0-100%)
  - Blend mode (replace, multiply, overlay, screen)
  - Preserve hue (bool - only affect luminosity)
- **Output**: Colors remapped through gradient
- **Use Case**: Stylized looks, heat maps, mood shifts

#### 17. **Fog** (NEW)
- **Purpose**: Depth-based atmospheric fog
- **Parameters**:
  - Fog color (RGB)
  - Fog start distance (0-500 voxels)
  - Fog end distance (0-500 voxels)
  - Fog density (0-100%)
  - Fog mode (linear, exponential, exponential squared)
- **Output**: Blends voxel colors toward fog color based on camera distance
- **Use Case**: Atmospheric depth, hide distant geometry

#### 18. **Bloom** (NEW)
- **Purpose**: Glow effect on bright areas
- **Parameters**:
  - Threshold (only affect colors above this brightness)
  - Intensity (0-200%)
  - Blur radius (1-8 pixels)
  - Blur quality (fast, normal, high)
- **Output**: Additive glow around bright voxels
- **Use Case**: Magical effects, neon, lights

#### 19. **Vignette** (NEW)
- **Purpose**: Darken/desaturate edges of viewport
- **Parameters**:
  - Inner radius (0-100%)
  - Outer radius (0-100%)
  - Intensity (0-100%)
  - Color (RGB - default black)
  - Mode (darken, desaturate, colorize)
- **Output**: Radial gradient from center
- **Use Case**: Focus attention, cinematic look

#### 20. **Chromatic Aberration** (NEW)
- **Purpose**: Separate RGB channels for lens distortion effect
- **Parameters**:
  - Offset strength (0-10 pixels)
  - Direction (radial from center, or fixed direction)
  - Channel separation (which channels to offset)
- **Output**: RGB channels slightly misaligned
- **Use Case**: Retro CRT, glitch effects, lens imperfection

#### 21. **Pixelate** (NEW)
- **Purpose**: Reduce effective resolution
- **Parameters**:
  - Block size (2x2, 4x4, 8x8, 16x16, custom)
  - Sampling mode (nearest, average, dominant color)
- **Output**: Downsampled and upsampled image
- **Use Case**: Extra retro look, performance testing, artistic

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
