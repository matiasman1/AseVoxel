-- Executes shader pipeline (lighting → FX) with input routing

local shaderStack = {}

-- Shader registry (auto-populated on load)
shaderStack.registry = {
  lighting = {},  -- { shader_id = shaderModule, ... }
  fx = {}
}

-- Validate shader module structure
function shaderStack.validateShaderModule(shaderModule, shaderId)
  -- Check required fields
  if not shaderModule.info then
    return "missing info table"
  end
  
  if not shaderModule.info.id or type(shaderModule.info.id) ~= "string" then
    return "missing or invalid info.id"
  end
  
  if not shaderModule.info.name or type(shaderModule.info.name) ~= "string" then
    return "missing or invalid info.name"
  end
  
  if not shaderModule.info.category or (shaderModule.info.category ~= "lighting" and shaderModule.info.category ~= "fx") then
    return "missing or invalid info.category (must be 'lighting' or 'fx')"
  end
  
  -- Check process function
  if shaderModule.process and type(shaderModule.process) ~= "function" then
    return "process must be a function"
  end
  
  -- Check paramSchema if present
  if shaderModule.paramSchema then
    if type(shaderModule.paramSchema) ~= "table" then
      return "paramSchema must be a table"
    end
    
    for i, param in ipairs(shaderModule.paramSchema) do
      if type(param) ~= "table" then
        return "paramSchema[" .. i .. "] must be a table"
      end
      if not param.name or type(param.name) ~= "string" then
        return "paramSchema[" .. i .. "].name missing or invalid"
      end
      if not param.type or type(param.type) ~= "string" then
        return "paramSchema[" .. i .. "].type missing or invalid"
      end
      -- Validate known types
      local validTypes = {slider=true, color=true, bool=true, choice=true}
      if not validTypes[param.type] then
        return "paramSchema[" .. i .. "].type '" .. param.type .. "' is not valid (use: slider, color, bool, choice)"
      end
    end
  end
  
  return nil  -- No errors
end

-- Auto-register shaders from folders
function shaderStack.loadShaders()
  local fs = app.fs
  
  -- Try multiple possible extension folder names
  local possibleNames = {"asevoxel-viewer-refactor", "asevoxel-viewer", "AseVoxel-Viewer"}
  local extensionPath = nil
  
  for _, name in ipairs(possibleNames) do
    local testPath = app.fs.joinPath(app.fs.userConfigPath, "extensions", name)
    if fs.isDirectory(testPath) then
      extensionPath = testPath
      break
    end
  end
  
  if not extensionPath then
    print("[AseVoxel] ERROR: Could not find extension directory!")
    return
  end
  
  local shaderDirs = {
    lighting = fs.joinPath(extensionPath, "render", "shaders", "lighting"),
    fx = fs.joinPath(extensionPath, "render", "shaders", "fx")
  }
  
  for category, dir in pairs(shaderDirs) do
    if fs.isDirectory(dir) then
      local files = fs.listFiles(dir)
      
      for _, file in ipairs(files) do
        if file:match("%.lua$") then
          local shaderPath = fs.joinPath(dir, file)
          local success, shaderModule = pcall(dofile, shaderPath)
          
          if success and shaderModule and shaderModule.info and shaderModule.info.id then
            local shaderId = shaderModule.info.id
            
            -- Validate shader structure
            local validationError = shaderStack.validateShaderModule(shaderModule, shaderId)
            if not validationError then
              -- Check for native implementation
              local hasNative = false
              -- TODO: Check native bridge when implemented
              
              -- Check for Lua implementation
              local hasLua = (type(shaderModule.process) == "function")
              
              if hasNative or hasLua then
                shaderStack.registry[category][shaderId] = shaderModule
                print("[AseVoxel] Shader: " .. shaderId .. 
                      (hasNative and " [Native]" or "") .. 
                      (hasLua and " [Lua]" or ""))
              end
            end
          end
        end
      end
    end
  end
  
  -- Print summary
  local lightingCount = 0
  for _ in pairs(shaderStack.registry.lighting) do lightingCount = lightingCount + 1 end
  local fxCount = 0
  for _ in pairs(shaderStack.registry.fx) do fxCount = fxCount + 1 end
  
  print("[AseVoxel] Loaded " .. lightingCount .. " lighting, " .. fxCount .. " fx shaders")
end

-- Safety limits for shader execution
local MAX_FACE_COUNT = 1000000  -- Prevent memory explosion
local SHADER_TIMEOUT_MS = 5000  -- 5 second timeout per shader

-- Error message throttling to prevent console spam
local errorThrottle = {}
local ERROR_THROTTLE_INTERVAL = 2.0  -- Only print same error once per 2 seconds

local function throttledPrint(key, message)
  local now = os.clock()
  local lastPrint = errorThrottle[key]
  
  if not lastPrint or (now - lastPrint) >= ERROR_THROTTLE_INTERVAL then
    print(message)
    errorThrottle[key] = now
  end
end

-- Safe shader execution wrapper
local function executeSafely(shader, inputData, params, shaderId)
  -- Validate input data structure
  if not inputData or type(inputData) ~= "table" then
    throttledPrint("invalid_input_" .. shaderId, "[AseVoxel] Error: Shader " .. shaderId .. " received invalid input data")
    return inputData
  end
  
  -- Check face count before execution
  if inputData.faces and #inputData.faces > MAX_FACE_COUNT then
    throttledPrint("face_limit_in_" .. shaderId, "[AseVoxel] Error: Shader " .. shaderId .. " input exceeds face limit (" .. #inputData.faces .. " > " .. MAX_FACE_COUNT .. ")")
    return inputData
  end
  
  -- Execute shader with error protection
  local startTime = os.clock()
  local success, result = pcall(function()
    return shader.process(inputData, params or {})
  end)
  
  local elapsedMs = (os.clock() - startTime) * 1000
  
  if not success then
    throttledPrint("crash_" .. shaderId, "[AseVoxel] Error: Shader " .. shaderId .. " crashed: " .. tostring(result))
    return inputData  -- Return original data on failure
  end
  
  -- Validate output
  if not result or type(result) ~= "table" then
    throttledPrint("invalid_output_" .. shaderId, "[AseVoxel] Error: Shader " .. shaderId .. " returned invalid output (expected table, got " .. type(result) .. ")")
    return inputData
  end
  
  -- Check for face count explosion
  if result.faces and #result.faces > MAX_FACE_COUNT then
    throttledPrint("face_limit_out_" .. shaderId, "[AseVoxel] Error: Shader " .. shaderId .. " output exceeds face limit (" .. #result.faces .. " > " .. MAX_FACE_COUNT .. ")")
    return inputData
  end
  
  -- Check for timeout (warning only, already completed)
  if elapsedMs > SHADER_TIMEOUT_MS then
    throttledPrint("timeout_" .. shaderId, "[AseVoxel] Warning: Shader " .. shaderId .. " took " .. math.floor(elapsedMs) .. "ms (slow performance)")
  end
  
  return result
end

-- Execute full shader stack
function shaderStack.execute(shaderData, stackConfig)
  -- stackConfig = {
  --   lighting = {
  --     { id="dynamic", enabled=true, params={...}, inputFrom="base_color" },
  --     { id="ambientOcclusion", enabled=true, params={...}, inputFrom="previous" }
  --   },
  --   fx = {
  --     { id="faceshade", enabled=true, params={...}, inputFrom="previous" },
  --     { id="outline", enabled=false, params={...}, inputFrom="geometry" }
  --   }
  -- }
  
  if not stackConfig then
    print("[AseVoxel] ERROR: shader_stack.execute called with nil stackConfig!")
    return shaderData
  end
  
  local result = shaderData
  
  -- Phase 1: Lighting shaders (top to bottom)
  for i, shaderEntry in ipairs(stackConfig.lighting or {}) do
    if shaderEntry.enabled then
      local shader = shaderStack.registry.lighting[shaderEntry.id]
      if shader and shader.process then
        -- Route input based on inputFrom parameter
        local inputData = shaderStack.routeInput(result, shaderEntry.inputFrom, shaderData)
        result = executeSafely(shader, inputData, shaderEntry.params, shaderEntry.id)
      else
        throttledPrint("missing_lighting_" .. (shaderEntry.id or "unknown"), 
                      "[AseVoxel] Warning: Lighting shader not found or has no process function: " .. (shaderEntry.id or "unknown"))
      end
    end
  end
  
  -- Phase 2: FX shaders (top to bottom)
  for i, shaderEntry in ipairs(stackConfig.fx or {}) do
    if shaderEntry.enabled then
      local shader = shaderStack.registry.fx[shaderEntry.id]
      if shader and shader.process then
        -- Route input based on inputFrom parameter
        local inputData = shaderStack.routeInput(result, shaderEntry.inputFrom, shaderData)
        result = executeSafely(shader, inputData, shaderEntry.params, shaderEntry.id)
      else
        throttledPrint("missing_fx_" .. (shaderEntry.id or "unknown"), 
                      "[AseVoxel] Warning: FX shader not found or has no process function: " .. (shaderEntry.id or "unknown"))
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

-- Convert shader stack config from params format to execution format
function shaderStack.prepareStackConfig(params)
  -- Extract shader configuration from various param formats
  local config = {lighting = {}, fx = {}}
  
  -- Check for direct shaderStack parameter
  if params.shaderStack then
    return params.shaderStack
  end
  
  -- Check for fxStack (legacy format)
  if params.fxStack then
    for _, module in ipairs(params.fxStack) do
      local entry = {
        id = module.type or "unknown",
        enabled = module.enabled ~= false,
        params = module.params or {},
        inputFrom = module.inputFrom or "previous"
      }
      
      -- Determine if it's a lighting or fx shader based on ID
      if shaderStack.registry.lighting[entry.id] then
        table.insert(config.lighting, entry)
      elseif shaderStack.registry.fx[entry.id] then
        table.insert(config.fx, entry)
      end
    end
  end
  
  -- Check for specific lighting parameters (dynamic, basic, etc.)
  if params.lighting then
    -- Dynamic lighting configuration
    table.insert(config.lighting, {
      id = "dynamic",
      enabled = true,
      params = params.lighting,
      inputFrom = "base_color"
    })
  elseif params.basicShadeIntensity or params.basicLightIntensity then
    -- Basic lighting configuration
    table.insert(config.lighting, {
      id = "basic",
      enabled = true,
      params = {
        shadeIntensity = params.basicShadeIntensity or 50,
        lightIntensity = params.basicLightIntensity or 50
      },
      inputFrom = "base_color"
    })
  end
  
  return config
end

return shaderStack
