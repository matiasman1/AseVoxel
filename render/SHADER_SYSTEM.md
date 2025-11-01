# Shader Stack System

## Overview

The Shader Stack System is a modular rendering architecture that replaces the monolithic lighting modes with a flexible, extensible pipeline of shader modules.

## Architecture

### Core Components

1. **`shader_interface.lua`** - Defines the protocol that all shaders must follow
2. **`shader_stack.lua`** - Execution engine that runs the shader pipeline
3. **`shader_ui.lua`** - Auto-generates UI widgets from shader parameter schemas

### Shader Categories

- **Lighting Shaders** (`render/shaders/lighting/`) - Calculate illumination
- **FX Shaders** (`render/shaders/fx/`) - Post-process colors

## Available Shaders

### Lighting Shaders

#### Basic Light (`basicLight`)
Simple camera-facing lighting - faces toward camera are lit, faces away are shaded.

**Parameters:**
- `lightIntensity` (0-100): Brightness for faces toward camera
- `shadeIntensity` (0-100): Brightness for faces away from camera

**Algorithm:**
- Computes dot product between face normal and camera direction
- Maps dot from [-1, 1] to [shadeIntensity, lightIntensity]
- Applies brightness as RGB multiplier

#### Dynamic Light (`dynamicLight`)
Physically-inspired lighting with directional light, falloff, and rim.

**Parameters:**
- `pitch` (-90 to 90°): Vertical angle of light
- `yaw` (0 to 360°): Horizontal angle of light
- `diffuse` (0-100%): Diffuse lighting intensity
- `ambient` (0-100%): Ambient lighting intensity
- `diameter` (0-200): Light cone diameter (0 = no radial attenuation)
- `rimEnabled` (bool): Enable rim/silhouette lighting
- `lightColor` (RGB): Color of the light

**Algorithm:**
- Computes light direction from pitch/yaw
- Calculates Lambert diffuse (ndotl ^ exponent)
- Applies radial attenuation based on perpendicular distance from light axis
- Adds ambient term
- Optionally adds rim lighting (Fresnel effect)

### FX Shaders

#### FaceShade (`faceshade`)
Fixed face brightness based on model-center normals (Alpha Full only).

**Parameters:**
- `topBrightness` (0-255): Top faces
- `bottomBrightness` (0-255): Bottom faces
- `frontBrightness` (0-255): Front faces
- `backBrightness` (0-255): Back faces
- `leftBrightness` (0-255): Left faces
- `rightBrightness` (0-255): Right faces

**Algorithm:**
- Determines face direction from model-center axis
- Multiplies RGB by (brightness/255)
- Alpha unchanged

#### FaceShade Camera (`faceshadeCamera`)
Camera-relative face shading (no back faces).

**Parameters:**
- `frontBrightness` (0-255): Faces toward camera
- `topBrightness` (0-255): Upward-facing
- `leftBrightness` (0-255): Left-facing
- `rightBrightness` (0-255): Right-facing
- `bottomBrightness` (0-255): Downward-facing

**Algorithm:**
- Projects face normal to camera view space
- Determines dominant direction relative to camera
- Applies corresponding brightness

#### Iso (`iso`)
Classic isometric look with Alpha/Literal modes, Material filtering, optional Tint.

**Parameters:**
- `shadingMode` (alpha/literal): Alpha = brightness multiplier, Literal = replace RGB
- `materialMode` (bool): Skip pure colors (preserve pure R/G/B/C/M/Y/K/W)
- `enableTint` (bool): Apply color tint in Alpha mode
- `alphaTint` (RGB): Tint color for Alpha mode
- `topBrightness` (0-255): Top/bottom faces
- `leftBrightness` (0-255): Left faces
- `rightBrightness` (0-255): Right faces

**Algorithm:**
- Determines isometric role (top/left/right) based on normal
- In Material mode: skips pure colors
- In Alpha mode: multiplies RGB by brightness, optionally applies tint
- In Literal mode: replaces RGB with brightness level

## Shader Data Protocol

All shaders receive and return a `shaderData` structure:

```lua
shaderData = {
  -- Per-face data
  faces = {
    {
      voxel = {x, y, z},           -- Voxel position
      face = "top",                 -- Face name
      normal = {x, y, z},           -- World-space normal
      color = {r, g, b, a},         -- Current color
      depth = 123.45,               -- Camera distance (optional)
      screenPos = {x, y},           -- 2D projection (optional)
      originalColor = {r, g, b, a}  -- Untouched color (optional)
    },
    -- ... more faces
  },
  
  -- Per-voxel data (optional)
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
    orthogonal = false
  },
  
  modelBounds = {minX, maxX, minY, maxY, minZ, maxZ},
  middlePoint = {x, y, z},
  
  -- Output target
  width = 400,
  height = 400,
  voxelSize = 2.5
}
```

## Creating Custom Shaders

### Shader Module Template

```lua
local myShader = {}

-- Shader metadata
myShader.info = {
  id = "myShader",                    -- Unique identifier
  name = "My Shader",                 -- Display name
  version = "1.0.0",
  author = "Your Name",
  category = "lighting",              -- "lighting" or "fx"
  complexity = "O(n)",                -- Performance hint
  description = "What this shader does",
  supportsNative = false,             -- Has C++ implementation
  requiresNormals = true,             -- Needs face normals
  requiresGeometry = false,           -- Needs voxel positions
  requiresDepth = false,              -- Needs camera distance
  inputs = {"base_color", "normals"},
  outputs = {"color"}
}

-- Parameter schema (for auto-UI generation)
myShader.paramSchema = {
  {
    name = "intensity",
    type = "slider",
    min = 0,
    max = 100,
    default = 50,
    label = "Intensity",
    tooltip = "Controls shader strength"
  },
  -- Add more parameters as needed
}

-- Main processing function
function myShader.process(shaderData, params)
  -- Get parameters
  local intensity = params.intensity or 50
  
  -- Process each face
  for i, face in ipairs(shaderData.faces or {}) do
    if face.color then
      -- Modify face.color based on your algorithm
      -- Example: multiply by intensity
      local factor = intensity / 100
      face.color.r = math.floor(face.color.r * factor)
      face.color.g = math.floor(face.color.g * factor)
      face.color.b = math.floor(face.color.b * factor)
    end
  end
  
  return shaderData
end

-- Optional: Custom UI builder (overrides auto-generated UI)
function myShader.buildUI(dlg, params, onChange)
  -- Build custom Aseprite Dialog widgets
  -- Call onChange(paramName, newValue) when user changes values
end

return myShader
```

### Installing Custom Shaders

1. Place your shader file in:
   - `render/shaders/lighting/` for lighting shaders
   - `render/shaders/fx/` for FX shaders

2. The shader will be auto-registered on load

3. It will appear in the shader stack UI automatically

## Shader Stack Configuration

A shader stack is defined by a configuration:

```lua
local stackConfig = {
  lighting = {
    {
      id = "basicLight",
      enabled = true,
      params = {
        lightIntensity = 80,
        shadeIntensity = 40
      },
      inputFrom = "base_color"  -- or "previous", "geometry", etc.
    },
    {
      id = "dynamicLight",
      enabled = true,
      params = {
        pitch = 25,
        yaw = 45,
        diffuse = 60,
        ambient = 30,
        diameter = 100,
        rimEnabled = true,
        lightColor = {r=255, g=230, b=200}
      },
      inputFrom = "previous"
    }
  },
  fx = {
    {
      id = "faceshade",
      enabled = true,
      params = {
        topBrightness = 255,
        bottomBrightness = 128,
        frontBrightness = 200,
        backBrightness = 150,
        leftBrightness = 180,
        rightBrightness = 220
      },
      inputFrom = "previous"
    }
  }
}
```

## Execution Flow

1. **Lighting Phase**: Execute all enabled lighting shaders in order
   - Each shader receives input based on `inputFrom` parameter
   - Shaders modify face colors
   
2. **FX Phase**: Execute all enabled FX shaders in order
   - Each shader processes the output from previous shader
   - Final output is rendered

## Input Routing

The `inputFrom` parameter controls what data a shader receives:

- `"base_color"`: Original voxel colors (unmodified)
- `"previous"`: Output from previous shader in stack
- `"geometry"`: Voxel positions and geometry data only
- `"normals"`: Face normals only
- (Future) Named shader output: e.g., `"dynamicLight_01"`

## Testing

Run the test file to verify shader loading:

```bash
lua test_shader_stack.lua
```

Or from within Aseprite:
```lua
local test = dofile("test_shader_stack.lua")
test.test()
```

## Performance Considerations

- **Lazy Evaluation**: Only enabled shaders are executed
- **Caching**: Results can be cached when parameters unchanged
- **Native Acceleration**: Future C++ implementations for performance-critical shaders
- **Profiling**: Per-shader timing available in debug mode

## Backward Compatibility

The old `shadingMode` parameter system is still supported through an automatic migration layer in `preview_renderer.lua`. Old modes are converted to equivalent shader stacks:

- `"Basic"` → Basic Light shader
- `"Dynamic"` → Dynamic Light shader
- `"Stack"` → FaceShade + Iso shaders (from fxStack)

## Future Enhancements

### Planned Shaders

**Lighting:**
- Ambient Occlusion
- Hemisphere Lighting
- Point Light
- Directional Light
- Emissive

**FX:**
- Outline
- Palette Mapping
- Dither
- Cel Shade
- Fresnel
- Gradient Map
- Fog
- Bloom
- Vignette

### Features
- Preset system (save/load shader stacks)
- Native C++ acceleration
- User shader marketplace
- Visual shader editor
- Shader dependencies and validation

## API Reference

### shader_stack.lua

```lua
-- Load all shaders from directories
shaderStack.loadShaders()

-- Execute shader stack
local result = shaderStack.execute(shaderData, stackConfig)

-- Get shader by ID
local shader = shaderStack.getShader(shaderId, category)

-- List available shaders
local list = shaderStack.listShaders(category)

-- Validate stack configuration
local isValid = shaderStack.validate(stackConfig)
```

### shader_ui.lua

```lua
-- Build shader UI (auto-generated or custom)
shaderUI.buildShaderUI(dlg, shader, params, onChange)

-- Create collapsible shader entry
shaderUI.createShaderEntry(dlg, shader, params, callbacks)
```

## Troubleshooting

### Shader Not Loading

Check that:
1. File is in correct directory (`render/shaders/lighting/` or `render/shaders/fx/`)
2. File has `.lua` extension
3. Module returns a table with `info` and `process` fields
4. `info.id` is unique and matches expected format

### Shader Not Executing

Check that:
1. Shader is enabled in stack config
2. `process()` function doesn't error
3. Input routing is correct (`inputFrom` parameter)
4. Required data is available (normals, geometry, etc.)

### UI Not Generating

Check that:
1. `paramSchema` is defined
2. Parameter types are valid (slider, color, bool, choice, vector, material)
3. Default values are provided

## Contributing

To contribute a new shader:

1. Create shader module following template
2. Add to appropriate directory
3. Test with `test_shader_stack.lua`
4. Document parameters and algorithm
5. Submit pull request

---

**Version:** 1.0.0 (Phase 1)  
**Last Updated:** October 31, 2025
