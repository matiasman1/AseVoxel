# Shader Updates - Material Mode & Tint Support

## Summary of Changes

Updated shader specifications to match original behavior from monolithic previewRenderer:

### ✅ Basic Lighting Shader (`basic.lua`)
**Status:** Already Correct ✓

**Behavior:**
- Uses dot product of face normal to camera direction
- Maps dot product from [-1, 1] to [shadeIntensity, lightIntensity]
- Formula: `brightness = shadeIntensity + (lightIntensity - shadeIntensity) * ((dot + 1) / 2)`

**Parameters:**
- `lightIntensity` (0-100): Brightness for faces toward camera
- `shadeIntensity` (0-100): Brightness for faces away from camera

**No changes needed** - Already implements correct algorithm ✅

---

### ✅ FaceShade Shader (`faceshade.lua`)
**Status:** UPDATED - Added Material Mode & Tint Support

**New Features:**
1. **Shading Mode:**
   - `alpha`: Brightness multiplier (default) - preserves original colors
   - `literal`: Replace RGB with brightness level - grayscale shading

2. **Material Mode:**
   - When enabled, skips pure colors (preserves pure R/G/B/C/M/Y/K/W)
   - Useful for pixel art where pure colors have special meaning
   - Uses 10-unit threshold for "near zero" detection

3. **Tint Support:**
   - Optional color tint in Alpha mode
   - Applies multiplicative tint: `color * brightness * tint`
   - Disabled by default

**Parameters (10 total):**
- `shadingMode`: "alpha" | "literal"
- `materialMode`: bool (skip pure colors)
- `enableTint`: bool (apply tint in alpha mode)
- `alphaTint`: color (r, g, b) - tint color
- `topBrightness`: 0-255 (default 255)
- `bottomBrightness`: 0-255 (default 128)
- `frontBrightness`: 0-255 (default 200)
- `backBrightness`: 0-255 (default 150)
- `leftBrightness`: 0-255 (default 180)
- `rightBrightness`: 0-255 (default 220)

**Face Direction Algorithm:**
- Determines face based on dominant normal axis
- Y dominant → top/bottom
- X dominant → right/left
- Z dominant → front/back

---

### ✅ Isometric Shader (`iso.lua`)
**Status:** Already Correct ✓

**Features:**
1. **Shading Mode:**
   - `alpha`: Brightness multiplier (default)
   - `literal`: Replace RGB with brightness level

2. **Material Mode:**
   - Skips pure colors (same as faceshade)

3. **Tint Support:**
   - Optional tint in Alpha mode

**Parameters (7 total):**
- `shadingMode`: "alpha" | "literal"
- `materialMode`: bool
- `enableTint`: bool
- `alphaTint`: color (r, g, b)
- `topBrightness`: 0-255 (default 255) - for top AND bottom
- `leftBrightness`: 0-255 (default 180)
- `rightBrightness`: 0-255 (default 220)

**Isometric Role Algorithm:**
- If Y dominant → "top"
- Else if X < 0 → "left"
- Else → "right"
- Only 3 roles (simplified for isometric view)

---

## Comparison: FaceShade vs Iso

| Feature | FaceShade | Iso |
|---------|-----------|-----|
| Face Directions | 6 (top, bottom, front, back, left, right) | 3 (top, left, right) |
| Face Detection | Based on model-center normals | Camera-relative projection |
| Use Case | Cel-shading, material shading | Isometric games, pixel art |
| Material Mode | ✅ Yes | ✅ Yes |
| Tint Support | ✅ Yes | ✅ Yes |
| Alpha/Literal | ✅ Yes | ✅ Yes |

---

## Usage Examples

### Example 1: Basic Pixel Art Lighting
```lua
shaderStack = {
  lighting = {
    { id = "basic", params = { lightIntensity = 70, shadeIntensity = 30 } }
  },
  fx = {}
}
```

### Example 2: Isometric Game Style
```lua
shaderStack = {
  lighting = {
    { id = "basic", params = { lightIntensity = 50, shadeIntensity = 50 } }
  },
  fx = {
    { 
      id = "iso", 
      params = { 
        shadingMode = "alpha",
        materialMode = true,  -- Preserve pure colors
        topBrightness = 255,
        leftBrightness = 180,
        rightBrightness = 220
      }
    }
  }
}
```

### Example 3: Cel-Shaded with Tint
```lua
shaderStack = {
  lighting = {
    { id = "dynamic", params = { pitch = 45, yaw = 30, diffuse = 70, ambient = 20 } }
  },
  fx = {
    { 
      id = "faceshade", 
      params = { 
        shadingMode = "alpha",
        enableTint = true,
        alphaTint = { r = 255, g = 200, b = 150 },  -- Warm tint
        topBrightness = 255,
        bottomBrightness = 100,
        frontBrightness = 200,
        backBrightness = 120,
        leftBrightness = 160,
        rightBrightness = 200
      }
    }
  }
}
```

### Example 4: Material-Aware Shading
```lua
shaderStack = {
  lighting = {
    { id = "basic", params = { lightIntensity = 60, shadeIntensity = 40 } }
  },
  fx = {
    { 
      id = "faceshade", 
      params = { 
        shadingMode = "alpha",
        materialMode = true,  -- Skip pure R/G/B/C/M/Y/K/W
        topBrightness = 255,
        bottomBrightness = 128,
        frontBrightness = 200,
        backBrightness = 150,
        leftBrightness = 180,
        rightBrightness = 220
      }
    }
  }
}
```

---

## Pure Color Detection Algorithm

Used by both `faceshade` and `iso` in Material Mode:

```lua
-- Threshold: 10 units
-- Pure Red: r >= 245, g <= 10, b <= 10
-- Pure Green: g >= 245, r <= 10, b <= 10
-- Pure Blue: b >= 245, r <= 10, g <= 10
-- Pure Cyan: g >= 245, b >= 245, r <= 10
-- Pure Magenta: r >= 245, b >= 245, g <= 10
-- Pure Yellow: r >= 245, g >= 245, b <= 10
-- Pure Black: r <= 10, g <= 10, b <= 10
-- Pure White: r >= 245, g >= 245, b >= 245
```

This allows for a 10-unit tolerance around pure values to account for slight color variations.

---

## Shading Mode Details

### Alpha Mode (Multiplicative)
- Preserves original color relationships
- Formula: `outputColor = inputColor * (brightness / 255) * tint`
- Good for realistic shading that respects material colors
- Tint is optional multiplicative modifier

### Literal Mode (Replace)
- Replaces color with grayscale brightness
- Formula: `outputColor = { r=brightness, g=brightness, b=brightness }`
- Good for debug visualization or stylized monochrome effects
- Ignores tint (tint only works in Alpha mode)

---

## Testing the Updated Shaders

### Test 1: FaceShade with Material Mode
1. Create sprite with pure red, green, blue pixels
2. Add some mixed-color pixels (e.g., orange, purple)
3. Add FaceShade shader with materialMode = true
4. **Expected:** Pure colors unchanged, mixed colors shaded

### Test 2: FaceShade with Tint
1. Create simple voxel model
2. Add FaceShade shader with:
   - enableTint = true
   - alphaTint = {r=255, g=150, b=100} (warm orange tint)
3. **Expected:** All colors tinted orange, darker on bottom/back

### Test 3: Alpha vs Literal
1. Add FaceShade with shadingMode = "alpha"
2. Observe colors are multiplied
3. Change to shadingMode = "literal"
4. **Expected:** Colors become grayscale levels

### Test 4: 6-Direction Control
1. Add FaceShade shader
2. Configure different brightness for each direction:
   - top = 255 (brightest)
   - bottom = 100 (darkest)
   - front/back/left/right = varying
3. Rotate model to see all faces
4. **Expected:** Each face direction has distinct brightness

---

## Files Modified

- ✅ `render/shaders/fx/faceshade.lua`
  - Added `shadingMode` parameter ("alpha" | "literal")
  - Added `materialMode` parameter (bool)
  - Added `enableTint` parameter (bool)
  - Added `alphaTint` parameter (color)
  - Added `isPureColor()` helper function
  - Updated `process()` to handle new modes
  - Updated version to 1.1.0
  - Updated description

- ✅ `AseVoxel-Viewer.aseprite-extension` (rebuilt)
  - Version 1.3
  - Includes updated faceshade.lua

---

## Summary

All three shaders now have complete feature parity with the original monolithic system:

✅ **Basic Light** - Dot product camera-facing lighting (unchanged)
✅ **FaceShade** - 6-direction shading with material mode & tint (UPDATED)
✅ **Isometric** - 3-direction isometric with material mode & tint (unchanged)

The modular shader system now supports all the rendering modes from the old system while being more flexible and extensible.

**Extension Status:** Ready for testing with full feature support! 🎉
