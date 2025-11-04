-- Minimal native module bridge (optional acceleration)

local nativeBridge = {
  _mod = nil,
  _attempted = false,
  _loadedPath = nil,
  _forceDisabled = false,
  _logOnce = {
    transform_ok = true,
    transform_fail = true,
    vis_ok = true,
    vis_fail = true,
    render_basic_ok = true,
    render_basic_fail = true,
    render_stack_ok = true,
    render_stack_fail = true,
    render_dynamic_ok = true,
    render_dynamic_fail = true
  }
}

-- Simplified require/load logic: try plain require once, then a small
-- set of platform-normalized candidate paths (base, bin, lib, cwd).
local function tryRequire()
  if nativeBridge._attempted then return end
  nativeBridge._attempted = true

  -- Try the canonical module name only
  local ok, mod = pcall(require, "asevoxel_native")
  if ok and type(mod) == "table" then
    nativeBridge._mod = mod
    nativeBridge._loadedPath = "(require:asevoxel_native)"
    return
  end

  -- Manual load fallback (platform-normalized, minimal candidates)
  local sep = package.config:sub(1,1)
  local isWin = (sep == "\\")
  local libname = isWin and "asevoxel_native.dll" or "asevoxel_native.so"

  local srcInfo = debug.getinfo(1, "S")
  local baseDir = "."
  if srcInfo and srcInfo.source then
    local s = srcInfo.source
    if s:sub(1,1) == "@" then s = s:sub(2) end
    baseDir = s:match("^(.*[/\\])") or "."
    baseDir = baseDir:gsub("[/\\]$", "")
  end

  local candidates = {
    baseDir .. sep .. libname,
    baseDir .. sep .. "bin" .. sep .. libname,
    baseDir .. sep .. "lib" .. sep .. libname,
    "." .. sep .. libname,      -- current working dir
    libname                     -- bare filename (let platform search handle)
  }

  local openFn = "luaopen_asevoxel_native"
  for _, path in ipairs(candidates) do
    local loader = package.loadlib(path, openFn)
    if loader then
      local ok2, res = pcall(loader)
      if ok2 and type(res) == "table" then
        nativeBridge._mod = res
        nativeBridge._loadedPath = path
        package.loaded["asevoxel_native"] = res
        return
      end
    end
  end
  -- no hardcoded user-specific fallbacks
end

local function mod()
  if not nativeBridge._mod then tryRequire() end
  return nativeBridge._mod
end

--------------------------------------------------------------------------------
-- Explicit loader: nativeBridge.loadnative(plugin_path)
-- (keeps attempts minimal and platform-normalized)
--------------------------------------------------------------------------------
function nativeBridge.loadnative(plugin_path)
  if (not plugin_path) or plugin_path == "" then
    local src = debug.getinfo(1, "S")
    if src and src.source then
      local s = src.source
      if s:sub(1,1) == "@" then s = s:sub(2) end
      plugin_path = s:match("^(.*[/\\])") or "."
      plugin_path = plugin_path:gsub("[/\\]$", "")
    else
      plugin_path = "."
    end
  end

  if nativeBridge._forceDisabled then
    return false, "forced disabled"
  end
  if nativeBridge._mod then
    return true, nativeBridge._loadedPath or "(already loaded)"
  end

  nativeBridge._attempted = true
  plugin_path = plugin_path:gsub("[/\\]+$", "")
  local sep = package.config:sub(1,1)
  local isWin = (sep == "\\")

  local libname = isWin and "asevoxel_native.dll" or "asevoxel_native.so"
  local candidates = {
    plugin_path .. sep .. libname,
    plugin_path .. sep .. "bin" .. sep .. libname,
    plugin_path .. sep .. "lib" .. sep .. libname,
    "." .. sep .. libname,
    libname
  }

  -- De-duplicate
  local seen = {}
  local filtered = {}
  for _, p in ipairs(candidates) do
    if not seen[p] then seen[p] = true; filtered[#filtered+1] = p end
  end
  candidates = filtered

  -- Add only a small, platform-normalized set of patterns to package.cpath
  local patterns = {}
  if isWin then
    patterns = {
      plugin_path .. sep .. "?.dll",
      plugin_path .. sep .. "bin" .. sep .. "?.dll"
    }
  else
    patterns = {
      plugin_path .. sep .. "?.so",
      plugin_path .. sep .. "bin" .. sep .. "?.so"
    }
  end

  for i = #patterns, 1, -1 do
    local pat = patterns[i]
    if not package.cpath:find(pat, 1, true) then
      package.cpath = pat .. ";" .. package.cpath
    end
  end

  local openFn = "luaopen_asevoxel_native"
  for _, path in ipairs(candidates) do
    local loader = package.loadlib(path, openFn)
    if loader then
      local ok, res = pcall(loader)
      if ok and type(res) == "table" then
        nativeBridge._mod = res
        nativeBridge._loadedPath = path
        package.loaded["asevoxel_native"] = res
        return true, path
      end
    end
  end

  -- final fallback to tryRequire's plain require
  tryRequire()
  if nativeBridge._mod then
    return true, nativeBridge._loadedPath or "(require fallback)"
  end
  return false, "not found"
end

function nativeBridge.isAvailable()
  if nativeBridge._forceDisabled then return false end
  return mod() ~= nil
end

function nativeBridge.setForceDisabled(v)
  nativeBridge._forceDisabled = not not v
end

function nativeBridge.getStatus()
  return {
    available = (not nativeBridge._forceDisabled) and (nativeBridge._mod ~= nil),
    forcedDisabled = nativeBridge._forceDisabled,
    loadedPath = nativeBridge._loadedPath,
    attempted = nativeBridge._attempted,
    platform = (package.config:sub(1,1) == "\\") and "windows" or "unix"
  }
end

function nativeBridge.transformVoxel(voxel, params)
  local m = mod()
  if not m or not m.transform_voxel then return nil, "native missing" end
  local ok, transformed = pcall(m.transform_voxel,
    { x = voxel.x, y = voxel.y, z = voxel.z, color = voxel.color },
    {
      middlePoint = params.middlePoint and {
        x = params.middlePoint.x,
        y = params.middlePoint.y,
        z = params.middlePoint.z
      } or nil,
      xRotation = params.xRotation,
      yRotation = params.yRotation,
      zRotation = params.zRotation
    }
  )
  if not ok then
    if not nativeBridge._logOnce.transform_fail then
      nativeBridge._logOnce.transform_fail = true
      print("[asevoxel-native] transform_voxel FAILED, falling back to Lua: " .. tostring(transformed))
    end
    return nil, transformed
  end
  if not nativeBridge._logOnce.transform_ok then
    nativeBridge._logOnce.transform_ok = true
    print("[asevoxel-native] transform_voxel (native)")
  end
  return transformed
end

function nativeBridge.calculateFaceVisibility(voxel, cameraPos, orthogonal, rotationParams)
  local m = mod()
  if not m or not m.calculate_face_visibility then return nil, "native missing" end
  local ok, vis = pcall(m.calculate_face_visibility,
    { x = voxel.x, y = voxel.y, z = voxel.z },
    { x = cameraPos.x, y = cameraPos.y, z = cameraPos.z },
    orthogonal and true or false,
    {
      xRotation = rotationParams.xRotation,
      yRotation = rotationParams.yRotation,
      zRotation = rotationParams.zRotation,
      voxelSize = rotationParams.voxelSize
    }
  )
  if not ok then
    if not nativeBridge._logOnce.vis_fail then
      nativeBridge._logOnce.vis_fail = true
      print("[asevoxel-native] calculate_face_visibility FAILED, falling back to Lua: " .. tostring(vis))
    end
    return nil, vis
  end
  if not nativeBridge._logOnce.vis_ok then
    nativeBridge._logOnce.vis_ok = true
    print("[asevoxel-native] calculate_face_visibility (native)")
  end
  return vis
end

function nativeBridge.renderBasic(voxels, params)
  local m = mod()
  if not (m and m.render_basic) then
    if not nativeBridge._logOnce.render_basic_fail then
      nativeBridge._logOnce.render_basic_fail = true
      print("[asevoxel-native] render_basic not available (falling back)")
    end
    return nil, "native missing"
  end
  local ok, res = pcall(m.render_basic, voxels, params)
  if not ok or type(res) ~= "table" or type(res.pixels) ~= "string" then
    if not nativeBridge._logOnce.render_basic_fail then
      nativeBridge._logOnce.render_basic_fail = true
      print("[asevoxel-native] render_basic FAILED, falling back: " .. tostring(res))
    end
    return nil, res
  end
  if not nativeBridge._logOnce.render_basic_ok then
    nativeBridge._logOnce.render_basic_ok = true
    print("[asevoxel-native] render_basic (native)")
  end
  return res
end

function nativeBridge.renderStack(voxels, params)
  local m = mod()
  if not (m and m.render_stack) then
    if not nativeBridge._logOnce.render_stack_fail then
      nativeBridge._logOnce.render_stack_fail = true
      print("[asevoxel-native] render_stack not available (falling back)")
    end
    return nil, "native missing"
  end
  local ok, res = pcall(m.render_stack, voxels, params)
  if not ok or type(res) ~= "table" or type(res.pixels) ~= "string" then
    if not nativeBridge._logOnce.render_stack_fail then
      nativeBridge._logOnce.render_stack_fail = true
      print("[asevoxel-native] render_stack FAILED, falling back: " .. tostring(res))
    end
    return nil, res
  end
  if not nativeBridge._logOnce.render_stack_ok then
    nativeBridge._logOnce.render_stack_ok = true
    print("[asevoxel-native] render_stack (native)")
  end
  return res
end

function nativeBridge.renderDynamic(voxels, params)
  local m = mod()
  if not (m and m.render_dynamic) then
    if not nativeBridge._logOnce.render_dynamic_fail then
      nativeBridge._logOnce.render_dynamic_fail = true
      print("[asevoxel-native] render_dynamic not available (falling back)")
    end
    return nil, "native missing"
  end
  local ok, res = pcall(m.render_dynamic, voxels, params)
  if not ok or type(res) ~= "table" or type(res.pixels) ~= "string" then
    if not nativeBridge._logOnce.render_dynamic_fail then
      nativeBridge._logOnce.render_dynamic_fail = true
      print("[asevoxel-native] render_dynamic FAILED, falling back: " .. tostring(res))
    end
    return nil, res
  end
  if not nativeBridge._logOnce.render_dynamic_ok then
    nativeBridge._logOnce.render_dynamic_ok = true
    print("[asevoxel-native] render_dynamic (native)")
  end
  return res
end

-- New hybrid renderer: Native geometry generation + Lua shader processing + Native rasterization
-- This is the main entry point for shader-based rendering
function nativeBridge.renderWithShaders(voxels, params)
  local m = mod()
  
  -- Lazy load native config
  local nativeConfig
  local ok, result = pcall(function()
    return require("render.native_config")
  end)
  if ok then
    nativeConfig = result
  else
    -- Try alternative path
    ok, result = pcall(function()
      return require("native_config")
    end)
    if ok then
      nativeConfig = result
    end
  end
  
  -- Lazy load shader_stack module
  local shaderStack
  ok, result = pcall(function()
    return require("render.shader_stack")
  end)
  if ok then
    shaderStack = result
  else
    -- Try alternative path
    ok, result = pcall(function()
      return require("shader_stack")
    end)
    if ok then
      shaderStack = result
    else
      return nil, "shader_stack module not available: " .. tostring(result)
    end
  end
  
  -- Load shaders if not already loaded
  if shaderStack and not shaderStack._loaded then
    shaderStack.loadShaders()
    shaderStack._loaded = true
  end
  
  -- Step 1: Generate face geometry with normals (native)
  if not (m and m.precompute_visible_faces and m.precompute_rotated_normals) then
    return nil, "native precompute functions not available"
  end
  
  -- Calculate model bounds and middle point
  local minX, maxX = voxels[1].x, voxels[1].x
  local minY, maxY = voxels[1].y, voxels[1].y
  local minZ, maxZ = voxels[1].z, voxels[1].z
  
  for _, v in ipairs(voxels) do
    if v.x < minX then minX = v.x end
    if v.x > maxX then maxX = v.x end
    if v.y < minY then minY = v.y end
    if v.y > maxY then maxY = v.y end
    if v.z < minZ then minZ = v.z end
    if v.z > maxZ then maxZ = v.z end
  end
  
  local midX = (minX + maxX) / 2
  local midY = (minY + maxY) / 2
  local midZ = (minZ + maxZ) / 2
  
  -- Build face data structure for shader processing
  local shaderData = {
    faces = {},
    voxels = voxels,
    camera = {
      position = {x=midX, y=midY, z=midZ + 100},
      direction = {x=0, y=0, z=-1}
    },
    middlePoint = {x=midX, y=midY, z=midZ},
    modelBounds = {minX=minX, maxX=maxX, minY=minY, maxY=maxY, minZ=minZ, maxZ=maxZ},
    width = params.width or 200,
    height = params.height or 200,
    voxelSize = params.voxelSize or params.scale or 10
  }
  
  -- Step 2: Precompute visible faces and rotated normals (native optimization)
  local visResult = m.precompute_visible_faces(
    params.xRotation or 0, 
    params.yRotation or 0, 
    params.zRotation or 0, 
    params.orthogonal or false
  )
  
  local normalResult = m.precompute_rotated_normals(
    params.xRotation or 0, 
    params.yRotation or 0, 
    params.zRotation or 0
  )
  
  if not visResult or not normalResult then
    return nil, "precompute failed"
  end
  
  -- Step 3: Build face list from voxels (only visible faces)
  local faceNames = {"front", "back", "right", "left", "top", "bottom"}
  for i, voxel in ipairs(voxels) do
    for _, faceName in ipairs(faceNames) do
      -- Check visibility
      if visResult.visibleFaces[faceName] then
        local normal = normalResult[faceName]
        if normal then
          table.insert(shaderData.faces, {
            voxel = {x = voxel.x, y = voxel.y, z = voxel.z},
            face = faceName,
            normal = {x = normal.x, y = normal.y, z = normal.z},
            color = {
              r = voxel.color and voxel.color.r or 255,
              g = voxel.color and voxel.color.g or 255,
              b = voxel.color and voxel.color.b or 255,
              a = voxel.color and voxel.color.a or 255
            }
          })
        end
      end
    end
  end
  
  -- Step 4: Prepare shader stack configuration
  local stackConfig = shaderStack.prepareStackConfig(params)
  
  -- Step 5: Process shaders (Hybrid: Native C++ with Lua fallback)
  -- PERFORMANCE OPTIMIZATION: For fully native shader stacks, bypass Lua overhead
  -- and use the old fast path (render_stack/render_basic) which does everything in C++
  local useNative = false
  local useFastPath = false
  
  if nativeConfig and m then
    useNative = nativeConfig:canUseNativeStack(stackConfig)
    
    -- Check if we can use the ultra-fast old render path (render_stack/render_basic)
    -- This avoids all Lua table operations and does geometry+shading+rasterization in one C++ call
    if useNative and (m.render_stack or m.render_basic) then
      -- Check if shader stack matches what render_stack/render_basic can handle
      local canUseFastPath = false
      
      -- render_basic: handles basic lighting only
      if m.render_basic and stackConfig.lighting and #stackConfig.lighting == 1 and not stackConfig.fx then
        local shader = stackConfig.lighting[1]
        if shader.enabled and shader.id == "basic" then
          canUseFastPath = true
          useFastPath = "basic"
        end
      end
      
      -- render_stack: handles dynamic lighting + faceshade/iso FX
      if not canUseFastPath and m.render_stack then
        local hasValidLighting = false
        local hasValidFX = false
        
        if stackConfig.lighting and #stackConfig.lighting == 1 then
          local shader = stackConfig.lighting[1]
          if shader.enabled and shader.id == "dynamic" then
            hasValidLighting = true
          end
        end
        
        if stackConfig.fx and #stackConfig.fx == 1 then
          local shader = stackConfig.fx[1]
          if shader.enabled and (shader.id == "faceshade" or shader.id == "iso") then
            hasValidFX = true
          end
        end
        
        if hasValidLighting and hasValidFX then
          canUseFastPath = true
          useFastPath = "stack"
        end
      end
    end
  end
  
  -- FAST PATH: Use old optimized render functions (40ms performance)
  if useFastPath then
    if not nativeBridge._logOnce.fast_path then
      nativeBridge._logOnce.fast_path = true
      print("[asevoxel-native] Using optimized fast path (" .. useFastPath .. ") - bypassing Lua overhead")
    end
    
    -- Call the old fast renderer directly - skip all the Lua table manipulation
    -- This is what gave us 40ms performance in the old version
    local renderFunc = (useFastPath == "basic") and m.render_basic or m.render_stack
    local ok, result = pcall(renderFunc, voxels, params)
    
    if ok and result and result.pixels then
      -- Success - return immediately, skipping all the slow Lua processing below
      return result
    else
      -- Fast path failed, fall through to slow path
      if not nativeBridge._logOnce.fast_path_fail then
        nativeBridge._logOnce.fast_path_fail = true
        print("[asevoxel-native] Fast path failed: " .. tostring(result) .. ", using slow path")
      end
    end
  end
  
  -- SLOW PATH: Full flexibility but with Lua overhead (110ms performance)  
  if useNative and m.render_native_shaders then
    -- Convert shaderData to native format
    local nativeData = {
      faces = {},
      cameraX = shaderData.camera.position.x,
      cameraY = shaderData.camera.position.y,
      cameraZ = shaderData.camera.position.z,
      cameraDirX = shaderData.camera.direction.x,
      cameraDirY = shaderData.camera.direction.y,
      cameraDirZ = shaderData.camera.direction.z,
      middleX = shaderData.middlePoint.x,
      middleY = shaderData.middlePoint.y,
      middleZ = shaderData.middlePoint.z,
      width = shaderData.width,
      height = shaderData.height,
      voxelSize = shaderData.voxelSize
    }
    
    for _, face in ipairs(shaderData.faces) do
      table.insert(nativeData.faces, {
        voxelX = face.voxel.x,
        voxelY = face.voxel.y,
        voxelZ = face.voxel.z,
        faceName = face.face,
        normalX = face.normal.x,
        normalY = face.normal.y,
        normalZ = face.normal.z,
        r = face.color.r,
        g = face.color.g,
        b = face.color.b,
        a = face.color.a
      })
    end
    
    -- Execute native shaders
    local ok, result = pcall(m.render_native_shaders, nativeData, stackConfig)
    if ok and result and result.faces then
      -- Convert back to shaderData format
      shaderData.faces = {}
      for _, face in ipairs(result.faces) do
        table.insert(shaderData.faces, {
          voxel = {x = face.voxelX, y = face.voxelY, z = face.voxelZ},
          face = face.faceName,
          normal = {x = face.normalX, y = face.normalY, z = face.normalZ},
          color = {r = face.r, g = face.g, b = face.b, a = face.a}
        })
      end
      
      if not nativeBridge._logOnce.native_shaders_slow then
        nativeBridge._logOnce.native_shaders_slow = true
        print("[asevoxel-native] Using native C++ shaders (slow path with Lua overhead)")
      end
    else
      -- Fall back to Lua if native fails
      if not nativeBridge._logOnce.native_shader_fallback then
        nativeBridge._logOnce.native_shader_fallback = true
        print("[asevoxel-native] Native shaders failed, using Lua: " .. tostring(result))
      end
      shaderData = shaderStack.execute(shaderData, stackConfig)
    end
  else
    -- Use Lua shaders (for custom shaders or free version)
    if not nativeBridge._logOnce.lua_shaders then
      nativeBridge._logOnce.lua_shaders = true
      print("[asevoxel-native] Using Lua shaders (custom or unsupported shaders detected)")
    end
    shaderData = shaderStack.execute(shaderData, stackConfig)
  end
  
  -- Step 6: Build voxel list with averaged face colors for rasterization
  -- Group faces by voxel position and average their colors
  local voxelColorMap = {}
  
  for _, face in ipairs(shaderData.faces or {}) do
    if face.voxel and face.color then
      local key = string.format("%d_%d_%d", face.voxel.x, face.voxel.y, face.voxel.z)
      if not voxelColorMap[key] then
        voxelColorMap[key] = {
          x = face.voxel.x,
          y = face.voxel.y,
          z = face.voxel.z,
          r = 0, g = 0, b = 0, a = 0,
          count = 0
        }
      end
      local vc = voxelColorMap[key]
      vc.r = vc.r + (face.color.r or 255)
      vc.g = vc.g + (face.color.g or 255)
      vc.b = vc.b + (face.color.b or 255)
      vc.a = vc.a + (face.color.a or 255)
      vc.count = vc.count + 1
    end
  end
  
  -- Convert to voxel list with averaged colors
  local litVoxels = {}
  for key, vc in pairs(voxelColorMap) do
    table.insert(litVoxels, {
      x = vc.x,
      y = vc.y,
      z = vc.z,
      color = {
        r = math.floor(vc.r / vc.count + 0.5),
        g = math.floor(vc.g / vc.count + 0.5),
        b = math.floor(vc.b / vc.count + 0.5),
        a = math.floor(vc.a / vc.count + 0.5)
      }
    })
  end
  
  -- Step 7: Rasterize using render_basic with pre-lit colors (native)
  if m.render_basic then
    local rasterParams = {
      width = params.width or 200,
      height = params.height or 200,
      scale = params.voxelSize or params.scale or 10,
      xRotation = params.xRotation or 0,
      yRotation = params.yRotation or 0,
      zRotation = params.zRotation or 0,
      orthogonal = params.orthogonal or false,
      fovDegrees = params.fovDegrees or 0,
      perspectiveScaleRef = params.perspectiveScaleRef or "middle",
      backgroundColor = params.backgroundColor or {r=0, g=0, b=0, a=0},
      basicShadeIntensity = 100,  -- Full brightness (already lit by shaders)
      basicLightIntensity = 100
    }
    
    return m.render_basic(litVoxels, rasterParams)
  end
  
  return nil, "native render_basic not available"
end

--------------------------------------------------------------------------------
-- Unload helpers: best-effort attempts to release loaded native DLLs so the
-- extension folder can be removed on Windows/Unix. Unloading shared libs from
-- Lua is platform/implementation dependent; these are best-effort routines.
--------------------------------------------------------------------------------

-- Returns true if we attempted any unload action
function nativeBridge.unloadAll()
  -- drop Lua references so GC can run
  local loadedPath = nativeBridge._loadedPath
  nativeBridge._mod = nil
  nativeBridge._loadedPath = nil
  nativeBridge._attempted = false
  package.loaded["asevoxel_native"] = nil
  package.loaded["lua54"] = nil
  package.loaded["ffi"] = nil

  -- try to use ffi (LuaJIT / LuaJIT-FFI compatible) to dlclose / FreeLibrary
  local ok, ffi = pcall(require, "ffi")
  if ok and ffi then
    local sep = package.config:sub(1,1)
    local isWin = (sep == "\\")
    if isWin then
      -- Windows: use kernel32 LoadLibraryA / FreeLibrary
      pcall(function()
        ffi.cdef[[
          void* LoadLibraryA(const char* name);
          int FreeLibrary(void* hModule);
        ]]
        local kernel = ffi.load("kernel32")
        local function tryFree(name)
          if not name or name == "" then return end
          -- try to open and immediately free the library handle
          local h = kernel.LoadLibraryA(name)
          if h ~= nil then kernel.FreeLibrary(h) end
        end
        tryFree(loadedPath)
        tryFree("lua54.dll")
        tryFree("asevoxel_native.dll")
      end)
    else
      -- POSIX: use dlopen/dlclose
      pcall(function()
        ffi.cdef[[
          void* dlopen(const char* filename, int flags);
          int dlclose(void* handle);
        ]]
        local RTLD_NOW = 2
        local function tryClose(name)
          if not name or name == "" then return end
          local h = ffi.C.dlopen(name, RTLD_NOW)
          if h ~= nil then ffi.C.dlclose(h) end
        end
        tryClose(loadedPath)
        tryClose("liblua54.so")
        tryClose("asevoxel_native.so")
      end)
    end
  end

  -- final attempt: run GC to drop any remaining references
  collectgarbage()
  return true
end

-- also provide a small explicit alias
function nativeBridge.unloadNative()
  return nativeBridge.unloadAll()
end

-- Alias for compatibility with preview_renderer.lua
function nativeBridge.renderShaderStack(voxels, params)
  return nativeBridge.renderWithShaders(voxels, params)
end

-- Auto-attempt native load on require (if not already loaded / forced off)
do
  if not nativeBridge._mod and not nativeBridge._forceDisabled then
    local ok, msg = nativeBridge.loadnative()
    if not ok and msg ~= "forced disabled" then
      -- Only print one concise line (further detail available via debug tab)
      if not nativeBridge._logOnce.autoload_fail then
        nativeBridge._logOnce.autoload_fail = true
        print("[asevoxel-native] autoload attempt: " .. tostring(msg))
      end
    end
  end
end

return nativeBridge
