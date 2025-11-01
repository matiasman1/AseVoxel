# Shader Safety Features

## Overview

AseVoxel's shader stack includes comprehensive safety features to prevent crashes and freezes from malformed or malicious user-created shaders.

---

## Safety Mechanisms

### 1. **Error Isolation (pcall Protection)**
Each shader executes in a protected context using `pcall`:
```lua
local success, result = pcall(function()
  return shader.process(inputData, params)
end)
```

**Benefits:**
- Shader crashes don't crash the entire application
- Original data returned on failure (graceful degradation)
- Error messages logged to console for debugging

---

### 2. **Face Count Limits**
```lua
MAX_FACE_COUNT = 1,000,000
```

**Protection Against:**
- Infinite loop geometry generation
- Memory exhaustion attacks
- Accidental polygon explosion

**Behavior:**
- Checks input before shader execution
- Checks output after shader execution
- Returns original data if limit exceeded

---

### 3. **Performance Monitoring**
```lua
SHADER_TIMEOUT_MS = 5,000  -- 5 seconds
```

**Features:**
- Tracks execution time per shader
- Warns about slow shaders (> 5 seconds)
- Helps identify performance bottlenecks
- Does NOT kill shader (already completed)

**Console Output:**
```
[AseVoxel] Warning: Shader mySlowShader took 6234ms (slow performance)
```

---

### 4. **Shader Module Validation**

All shaders validated during loading:

#### Required Fields:
- ✅ `info` table must exist
- ✅ `info.id` must be a string
- ✅ `info.name` must be a string
- ✅ `info.category` must be "lighting" or "fx"

#### Optional Fields (validated if present):
- ✅ `process` must be a function (if provided)
- ✅ `paramSchema` must be a table array
- ✅ Each param must have valid `name` (string) and `type`
- ✅ Valid types: `slider`, `color`, `bool`, `choice`

#### Invalid Shaders:
- Logged to console with error message
- **Not registered** in shader stack
- Application continues normally

**Console Output:**
```
[AseVoxel] Invalid shader myBrokenShader: missing info.category
```

---

### 5. **Input/Output Validation**

#### Input Validation:
```lua
if not inputData or type(inputData) ~= "table" then
  print("[AseVoxel] Error: Shader received invalid input data")
  return inputData
end
```

#### Output Validation:
```lua
if not result or type(result) ~= "table" then
  print("[AseVoxel] Error: Shader returned invalid output")
  return inputData
end
```

**Protects Against:**
- Nil returns
- Non-table returns
- Corrupt data structures

---

## Error Messages

### Loading Errors
```
[AseVoxel] Error loading shader file: myshader.lua - [error details]
[AseVoxel] Invalid shader file: myshader.lua (missing info table or id)
[AseVoxel] Invalid shader myShader: missing or invalid info.name
[AseVoxel] Shader myShader has no implementation (Lua or Native), skipping
```

### Runtime Errors
```
[AseVoxel] Error: Shader myShader received invalid input data
[AseVoxel] Error: Shader myShader input exceeds face limit (2000000 > 1000000)
[AseVoxel] Error: Shader myShader crashed: [Lua error message]
[AseVoxel] Error: Shader myShader returned invalid output (expected table, got nil)
[AseVoxel] Error: Shader myShader output exceeds face limit (1500000 > 1000000)
[AseVoxel] Warning: Shader myShader took 6234ms (slow performance)
```

### Missing Shaders
```
[AseVoxel] Warning: Lighting shader not found or has no process function: unknownShader
[AseVoxel] Warning: FX shader not found or has no process function: missingShader
```

---

## Creating Safe User Shaders

### Minimal Valid Shader
```lua
local myShader = {}

myShader.info = {
  id = "myShader",
  name = "My Shader",
  version = "1.0.0",
  category = "fx",  -- or "lighting"
  description = "Does something cool"
}

myShader.paramSchema = {
  {
    name = "intensity",
    type = "slider",
    min = 0,
    max = 100,
    default = 50,
    label = "Intensity"
  }
}

function myShader.process(shaderData, params)
  -- MUST return shaderData (or modified copy)
  -- MUST NOT create infinite faces
  -- SHOULD complete within 5 seconds
  
  local intensity = params.intensity or 50
  
  for _, face in ipairs(shaderData.faces or {}) do
    -- Modify face.color.r, face.color.g, face.color.b, face.color.a
    -- Never modify face count in loop (causes undefined behavior)
  end
  
  return shaderData
end

return myShader
```

### Best Practices

#### ✅ DO:
- Always return `shaderData` (modified or original)
- Use `params` with sensible defaults: `params.myValue or defaultValue`
- Validate input: check if `shaderData.faces` exists
- Keep face count constant in FX shaders
- Complete execution quickly (< 1 second preferred)
- Handle edge cases (empty model, nil values)

#### ❌ DON'T:
- Return `nil` or non-table values
- Create thousands of new faces in a loop
- Use infinite loops or recursion
- Access undefined globals
- Assume data structure exists (always check)
- Modify shared state or globals

---

## Testing Your Shader

### 1. Load Test (Debug Tab)
Use "Test Shader Stack" button to verify:
- ✅ Shader loads without errors
- ✅ Shader appears in registry
- ✅ Parameters are valid

### 2. Execution Test
Add shader to stack and render:
- ✅ No crash or freeze
- ✅ Preview updates correctly
- ✅ Console shows no errors
- ✅ Performance acceptable

### 3. Edge Cases
Test with:
- Empty sprite (0 voxels)
- Single pixel
- Very large model (1000+ voxels)
- Extreme parameter values (min/max)

---

## Performance Guidelines

### Face Count Limits
| Model Size | Face Count | Status |
|------------|------------|--------|
| Small (< 100 voxels) | < 600 | ✅ Normal |
| Medium (< 1000 voxels) | < 6,000 | ✅ Good |
| Large (< 10,000 voxels) | < 60,000 | ⚠️ Acceptable |
| Huge (< 100,000 voxels) | < 600,000 | ⚠️ Slow |
| Maximum | 1,000,000 | 🛑 Hard Limit |

### Execution Time
| Duration | Status | Action |
|----------|--------|--------|
| < 100ms | ✅ Excellent | None |
| 100ms - 500ms | ✅ Good | None |
| 500ms - 1000ms | ⚠️ Noticeable | Consider optimization |
| 1s - 5s | ⚠️ Slow | Warning logged |
| > 5s | 🛑 Very Slow | Warning logged, investigate |

---

## Recovery Options

### If Shader Crashes
1. **Automatic:** Original data returned, preview shows previous state
2. **Manual:** Use Debug tab → "Reset to Default Shader" button
3. **Remove:** Delete shader from stack using "Configure Shaders" dialog

### If Shader Is Slow
1. **Check Console:** Look for timing warnings
2. **Profile Code:** Add timing prints in shader
3. **Optimize:** Reduce loops, cache calculations
4. **Remove:** Use simpler shader or disable

### If Preview Freezes
1. **Wait:** Shader may still be executing (< 5s)
2. **Console:** Check for error messages
3. **Restart:** Close and reopen AseVoxel dialog
4. **Remove:** Delete problematic shader file from extensions folder

---

## Summary

✅ **Shaders are isolated** - Crashes don't affect application
✅ **Memory protected** - Face count limits prevent exhaustion
✅ **Performance monitored** - Slow shaders are logged
✅ **Input validated** - Structure checked before and after
✅ **Graceful degradation** - Errors return original data

**User shaders are safe to experiment with!** The worst case is a console error and unchanged preview. 🎉
