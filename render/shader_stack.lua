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
  local extensionPath = app.fs.joinPath(app.fs.userConfigPath, "extensions", "asevoxel-viewer")
  
  local shaderDirs = {
    lighting = fs.joinPath(extensionPath, "render", "shaders", "lighting"),
    fx = fs.joinPath(extensionPath, "render", "shaders", "fx")
  }
  
  for category, dir in pairs(shaderDirs) do
    if fs.isDirectory(dir) then
      for _, file in ipairs(fs.listFiles(dir)) do
        if file:match("%.lua$") then
          local shaderPath = fs.joinPath(dir, file)
          local success, shaderModule = pcall(dofile, shaderPath)
          
          if success and shaderModule and shaderModule.info and shaderModule.info.id then
            local shaderId = shaderModule.info.id
            
            -- Check for native implementation
            local hasNative = false
            -- TODO: Check native bridge when implemented
            -- if nativeBridge and nativeBridge.hasNativeShader then
            --   hasNative = nativeBridge.hasNativeShader(shaderId)
            -- end
            
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
            if not success then
              print("[AseVoxel] Error loading shader file: " .. file .. " - " .. tostring(shaderModule))
            else
              print("[AseVoxel] Invalid shader file: " .. file)
            end
          end
        end
      end
    end
  end
  
  -- Load user shaders from preferences folder (future)
  -- TODO: Implement user shader loading
end

-- Execute full shader stack
function shaderStack.execute(shaderData, stackConfig)
  -- stackConfig = {
  --   lighting = {
  --     { id="dynamicLight", enabled=true, params={...}, inputFrom="base_color" },
  --     { id="ambientOcclusion", enabled=true, params={...}, inputFrom="previous" }
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
      local shader = shaderStack.registry.lighting[shaderEntry.id]
      if shader and shader.process then
        -- Route input based on inputFrom parameter
        local inputData = shaderStack.routeInput(result, shaderEntry.inputFrom, shaderData)
        result = shader.process(inputData, shaderEntry.params or {})
      else
        print("[AseVoxel] Warning: Shader not found or has no process function: " .. shaderEntry.id)
      end
    end
  end
  
  -- Phase 2: FX shaders (top to bottom)
  for _, shaderEntry in ipairs(stackConfig.fx or {}) do
    if shaderEntry.enabled then
      local shader = shaderStack.registry.fx[shaderEntry.id]
      if shader and shader.process then
        -- Route input based on inputFrom parameter
        local inputData = shaderStack.routeInput(result, shaderEntry.inputFrom, shaderData)
        result = shader.process(inputData, shaderEntry.params or {})
      else
        print("[AseVoxel] Warning: Shader not found or has no process function: " .. shaderEntry.id)
      end
    end
  end
  
  return result
end

-- Route input data based on inputFrom parameter
function shaderStack.routeInput(currentData, inputFrom, originalData)
  if inputFrom == "base_color" then
    -- Return original voxel colors
    return originalData
  elseif inputFrom == "previous" or not inputFrom then
    -- Return current (modified) data
    return currentData
  elseif inputFrom == "geometry" then
    -- Return geometry data only
    return {
      voxels = originalData.voxels,
      modelBounds = originalData.modelBounds,
      middlePoint = originalData.middlePoint,
      camera = originalData.camera,
      width = originalData.width,
      height = originalData.height,
      voxelSize = originalData.voxelSize
    }
  else
    -- Assume it's a named shader output (future feature)
    return currentData
  end
end

-- Validate shader stack (check dependencies, circular refs, etc.)
function shaderStack.validate(stackConfig)
  -- TODO: Implement validation logic
  -- - Check for circular dependencies
  -- - Verify all referenced shaders exist
  -- - Warn about missing inputs
  return true
end

-- Get shader by ID
function shaderStack.getShader(shaderId, category)
  if category then
    return shaderStack.registry[category][shaderId]
  else
    -- Search both categories
    return shaderStack.registry.lighting[shaderId] or shaderStack.registry.fx[shaderId]
  end
end

-- List all available shaders
function shaderStack.listShaders(category)
  if category then
    local list = {}
    for id, shader in pairs(shaderStack.registry[category]) do
      table.insert(list, {id = id, info = shader.info})
    end
    return list
  else
    -- Return all shaders
    return {
      lighting = shaderStack.listShaders("lighting"),
      fx = shaderStack.listShaders("fx")
    }
  end
end

return shaderStack
