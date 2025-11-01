# Migration Guide: Integrating Shader Stack into AseVoxel

This guide explains how to integrate the new shader stack system into the existing AseVoxel codebase.

## Overview

The shader stack system is currently **standalone** - it has been implemented but not yet integrated into the main rendering pipeline. This guide provides step-by-step instructions for integration.

## Phase 1: Completed (Standalone Infrastructure)

✅ Core infrastructure created  
✅ 5 shaders extracted and working  
✅ Test harness validates system  

## Phase 2: Integration Steps

### Step 1: Update preview_renderer.lua

Add the migration layer to convert old `shadingMode` to shader stack:

```lua
-- Add near top of file with other module requires
local shaderStack = nil
local function getShaderStack()
  if not shaderStack then
    shaderStack = dofile(app.fs.joinPath(
      app.fs.userConfigPath, "extensions", "asevoxel-viewer",
      "render", "shader_stack.lua"
    ))
  end
  return shaderStack
end

-- Add new migration function
function previewRenderer.migrateLegacyMode(shadingMode, params)
  local stack = { lighting = {}, fx = {} }
  
  if shadingMode == "Basic" or shadingMode == "Simple" then
    table.insert(stack.lighting, {
      id = "basicLight",
      enabled = true,
      params = {
        lightIntensity = params.basicLightIntensity or 50,
        shadeIntensity = params.basicShadeIntensity or 50
      },
      inputFrom = "base_color"
    })
  
  elseif shadingMode == "Dynamic" or shadingMode == "Complete" then
    local lighting = params.lighting or {}
    table.insert(stack.lighting, {
      id = "dynamicLight",
      enabled = true,
      params = {
        pitch = lighting.pitch or 25,
        yaw = lighting.yaw or 25,
        diffuse = lighting.diffuse or 60,
        ambient = lighting.ambient or 30,
        diameter = lighting.diameter or 100,
        rimEnabled = lighting.rimEnabled or false,
        lightColor = lighting.lightColor or {r=255, g=255, b=255}
      },
      inputFrom = "base_color"
    })
  
  elseif shadingMode == "Stack" then
    -- Convert fxStack to shader stack
    if params.fxStack and params.fxStack.modules then
      for _, module in ipairs(params.fxStack.modules) do
        if module.shape == "FaceShade" then
          local colors = module.colors or {}
          table.insert(stack.fx, {
            id = "faceshade",
            enabled = true,
            params = {
              topBrightness = (colors[1] and colors[1].a) or 255,
              bottomBrightness = (colors[2] and colors[2].a) or 180,
              frontBrightness = (colors[3] and colors[3].a) or 255,
              backBrightness = (colors[4] and colors[4].a) or 220,
              leftBrightness = (colors[5] and colors[5].a) or 210,
              rightBrightness = (colors[6] and colors[6].a) or 230
            },
            inputFrom = "previous"
          })
        elseif module.shape == "Iso" then
          local colors = module.colors or {}
          table.insert(stack.fx, {
            id = "iso",
            enabled = true,
            params = {
              shadingMode = module.type or "alpha",
              materialMode = (module.scope == "material"),
              enableTint = module.tintAlpha or false,
              alphaTint = {r=255, g=255, b=255},
              topBrightness = (colors[1] and colors[1].a) or 255,
              leftBrightness = (colors[2] and colors[2].a) or 235,
              rightBrightness = (colors[3] and colors[3].a) or 210
            },
            inputFrom = "previous"
          })
        end
      end
    end
  end
  
  return stack
end

-- Add new shader stack renderer
function previewRenderer.renderWithShaderStack(model, params)
  local ss = getShaderStack()
  
  -- Build shaderData structure from model
  local shaderData = {
    faces = {},
    voxels = {},
    camera = {
      position = params.cameraPosition or {x=0, y=0, z=10},
      rotation = {x=params.xRotation or 0, y=params.yRotation or 0, z=params.zRotation or 0},
      direction = params.viewDirection or {x=0, y=0, z=-1}
    },
    modelBounds = params.modelBounds or {minX=0, maxX=0, minY=0, maxY=0, minZ=0, maxZ=0},
    middlePoint = params.middlePoint or {x=0, y=0, z=0},
    width = params.width or 400,
    height = params.height or 400,
    voxelSize = params.scale or 2.0
  }
  
  -- TODO: Populate faces and voxels from model
  -- This requires extracting visible faces from the voxel model
  -- For now, use existing rendering path and apply shaders to result
  
  -- Execute shader stack
  local result = ss.execute(shaderData, params.shaderStack)
  
  -- TODO: Rasterize final image from result.faces
  -- For now, return existing render
  
  return previewRenderer.renderPreview(model, params)
end

-- Modify main render function
function previewRenderer.renderVoxelModel(model, params)
  _initModules()
  params = params or {}
  
  -- AUTO-MIGRATE LEGACY PARAMS
  if params.shadingMode and not params.shaderStack then
    params.shaderStack = previewRenderer.migrateLegacyMode(params.shadingMode, params)
    print("[AseVoxel] Auto-migrated legacy shadingMode to shader stack")
  end
  
  -- NEW: Use shader stack if present
  if params.shaderStack then
    return previewRenderer.renderWithShaderStack(model, params)
  end
  
  -- FALLBACK: Old path (for backward compatibility)
  return previewRenderer.renderPreview(model, params)
end
```

### Step 2: Test Migration

Create a test scene with legacy parameters:

```lua
-- Test migration
local testParams = {
  shadingMode = "Basic",
  basicLightIntensity = 80,
  basicShadeIntensity = 40,
  width = 400,
  height = 400
}

local migrated = previewRenderer.migrateLegacyMode(testParams.shadingMode, testParams)
print("Migrated stack:", migrated)
-- Expected: { lighting = { {id="basicLight", enabled=true, params={...}} }, fx = {} }
```

### Step 3: Add UI Tab (Optional for Phase 2)

Add a new tab to the main dialog for shader stack management:

```lua
-- In dialog/main_dialog.lua or equivalent

function createShaderStackTab(dlg, viewParams)
  local ss = require("render.shader_stack")
  local shaderUI = require("render.shader_ui")
  
  dlg:separator{ text = "Shader Stack" }
  
  -- List current shaders
  dlg:label{ text = "🔦 Lighting Shaders" }
  
  if viewParams.shaderStack and viewParams.shaderStack.lighting then
    for i, shaderEntry in ipairs(viewParams.shaderStack.lighting) do
      local shader = ss.getShader(shaderEntry.id, "lighting")
      if shader then
        -- Create collapsible shader entry
        shaderUI.createShaderEntry(dlg, shader, shaderEntry.params, {
          onChange = function(paramName, newValue)
            shaderEntry.params[paramName] = newValue
            -- Trigger preview update
          end,
          onMoveUp = function()
            -- Move shader up in stack
          end,
          onMoveDown = function()
            -- Move shader down in stack
          end,
          onRemove = function()
            table.remove(viewParams.shaderStack.lighting, i)
            -- Refresh UI
          end
        })
      end
    end
  end
  
  -- Add shader button
  dlg:button{
    text = "+ Add Lighting Shader",
    onclick = function()
      -- Show dropdown menu of available shaders
    end
  }
  
  -- FX Shaders section (similar to above)
  dlg:label{ text = "🎨 FX Shaders" }
  -- ... similar implementation
end
```

### Step 4: Update Scene Save/Load

Modify scene file format to include shader stack:

```lua
-- When saving scene
function saveScene(filename, viewParams)
  local scene = {
    version = "1.0",
    camera = {
      xRotation = viewParams.xRotation,
      yRotation = viewParams.yRotation,
      -- ... other camera params
    },
    shaderStack = viewParams.shaderStack,  -- NEW
    -- ... other scene data
  }
  
  local json = JSON.encode(scene)
  -- Write to file
end

-- When loading scene
function loadScene(filename)
  -- Read from file
  local json = -- ... read file
  local scene = JSON.decode(json)
  
  local viewParams = {
    xRotation = scene.camera.xRotation,
    yRotation = scene.camera.yRotation,
    -- ... other camera params
    shaderStack = scene.shaderStack,  -- NEW
  }
  
  return viewParams
end
```

## Phase 3: Native Integration (Future)

### Step 1: Update native_bridge.lua

```lua
function nativeBridge.renderUnified(voxels, params, shaderStack)
  -- Check if all shaders have native implementations
  local allNative = true
  for _, entry in ipairs(shaderStack.lighting or {}) do
    if not nativeBridge.hasNativeShader(entry.id) then
      allNative = false
      break
    end
  end
  
  if allNative then
    -- Pure native path
    return asevoxel_native.render_unified(voxels, params, shaderStack)
  else
    -- Hybrid path (mix Lua + native)
    return nativeBridge.renderHybrid(voxels, params, shaderStack)
  end
end
```

### Step 2: Update asevoxel_native.cpp

```cpp
// Add unified renderer
static int l_render_unified(lua_State* L) {
  // Parse voxels, params, shaderStack from Lua
  // Execute shader pipeline in C++
  // Return rendered image
}

// Register function
static const luaL_Reg FUNCS[] = {
  {"render_unified", l_render_unified},  // NEW
  // ... existing functions
  {nullptr, nullptr}
};
```

## Testing Checklist

After integration:

- [ ] Test Basic mode migration
- [ ] Test Dynamic mode migration
- [ ] Test Stack mode migration
- [ ] Verify visual output matches old renderer (pixel-perfect)
- [ ] Test shader parameter changes trigger update
- [ ] Test adding/removing shaders from UI
- [ ] Test reordering shaders
- [ ] Test scene save/load with shader stack
- [ ] Performance benchmark vs old renderer
- [ ] Test with native bridge (when available)

## Rollback Plan

If integration causes issues:

1. Comment out shader stack path in `renderVoxelModel()`
2. Keep using old `renderPreview()` path
3. Shader stack infrastructure remains available for testing
4. Fix issues in isolation before re-enabling

## Deprecation Timeline

### Phase 2 (Current)
- ✅ Shader stack available
- ✅ Auto-migration enabled
- ⚠️ Old shadingMode still works (with migration)

### Phase 3 (Future)
- 🔔 Deprecation warnings for old shadingMode
- ✅ Shader stack is primary method
- ⚠️ Old methods still work but discouraged

### Phase 4 (Future)
- ❌ Remove old shadingMode entirely
- ✅ Shader stack is only method
- 🎉 Clean codebase

## Common Issues

### Issue: Shaders not loading
**Solution:** Check extension path in `shader_stack.lua::loadShaders()`

### Issue: Migration produces wrong output
**Solution:** Verify parameter mapping in `migrateLegacyMode()`

### Issue: UI not updating
**Solution:** Ensure onChange callbacks trigger preview refresh

### Issue: Performance degradation
**Solution:** Profile shaders, consider native acceleration

## Support

For issues or questions:
1. Check `render/SHADER_SYSTEM.md` documentation
2. Run `test_shader_stack.lua` to verify installation
3. Enable debug logging in shader_stack.lua
4. Check console for error messages

---

**Migration Status:** Ready for Phase 2 Integration  
**Last Updated:** October 31, 2025
