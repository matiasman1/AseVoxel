-- Minimal native module bridge (optional acceleration)

local nativeBridge = {
  _mod = nil,
  _attempted = false,
  _loadedPath = nil,          -- added: where module loaded from
  _forceDisabled = false,     -- added: debug flag to simulate absence
  _logOnce = {
    transform_ok = false,
    transform_fail = false,
    vis_ok = false,
    vis_fail = false,
    render_basic_ok = false,
    render_basic_fail = false,
    render_stack_ok = false,
    render_stack_fail = false
  }
}

local function _log(_) end -- silent (enable for debug)

local function tryRequire()
  if nativeBridge._attempted then return end
  nativeBridge._attempted = true

  -- Try several require variants (search bin and lib too)
  local tryNames = {
    "asevoxel_native",
    "bin.asevoxel_native",
    "lib.asevoxel_native"
  }
  for _, name in ipairs(tryNames) do
    local ok, mod = pcall(require, name)
    if ok and type(mod) == "table" then
      nativeBridge._mod = mod
      nativeBridge._loadedPath = "(require:" .. name .. ")"
      return
    end
  end

  -- Fallback manual load
  local sep = package.config:sub(1,1)
  local isWin = (sep == "\\" or (os.getenv("OS") or ""):match("Windows"))
  local names = isWin and {"asevoxel_native.dll"} or {"asevoxel_native.so"}

  local srcInfo = debug.getinfo(1, "S")
  local baseDir = "."
  if srcInfo and srcInfo.source then
    local s = srcInfo.source
    if s:sub(1,1) == "@" then s = s:sub(2) end
    baseDir = s:match("^(.*[/\\])") or "."
    baseDir = baseDir:gsub("[/\\]$", "")
  end

  local candidates = {}
  for _, n in ipairs(names) do
    candidates[#candidates+1] = baseDir .. "/" .. n
    candidates[#candidates+1] = baseDir .. "/bin/" .. n
    candidates[#candidates+1] = baseDir .. "/lib/" .. n
  end

  local openFn = "luaopen_asevoxel_native"
  for _, path in ipairs(candidates) do
    local loader = package.loadlib(path, openFn)
    if loader then
      local ok2, res = pcall(loader)
      if ok2 and type(res) == "table" then
        nativeBridge._mod = res
        nativeBridge._loadedPath = path
        return
      end
    end
  end

  if isWin then
    ok, nativeBridge._mod = pcall(package.loadlib("C:/Users/matia/AppData/Roaming/Aseprite/extensions/asevoxel-viewer/asevoxel_native.dll","luaopen_asevoxel_native"))
    nativeBridge._loadedPath = "C:/Users/matia/AppData/Roaming/Aseprite/extensions/asevoxel-viewer/asevoxel_native.dll"
  end
end

local function mod()
  if not nativeBridge._mod then tryRequire() end
  return nativeBridge._mod
end

--------------------------------------------------------------------------------
-- Explicit loader: nativeBridge.loadnative(plugin_path)
--------------------------------------------------------------------------------
function nativeBridge.loadnative(plugin_path)
  -- Normalize / discover path automatically if none provided
  if (not plugin_path) or plugin_path == "" then
    -- Derive directory of this file
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

  -- After first explicit attempt, mark as attempted (prevents tryRequire double run)
  nativeBridge._attempted = true
  plugin_path = plugin_path:gsub("[/\\]+$", "")
  local sep = package.config:sub(1,1)
  local isWin = (sep == "\\")

  local function addVariants(tbl, path)
    tbl[#tbl+1] = path
    if path:find("\\") then
      tbl[#tbl+1] = path:gsub("\\", "/")
    elseif path:find("/") then
      tbl[#tbl+1] = path:gsub("/", "\\")
    end
  end

  if isWin then
    local luaDll = plugin_path .. sep .. "lua54.dll"
    local altLuaDll = luaDll:gsub("\\","/")
    for _, cand in ipairs({luaDll, altLuaDll}) do
      pcall(function() package.loadlib(cand, "") end)
    end
  end

  local libname = isWin and "asevoxel_native.dll" or "asevoxel_native.so"
  local candidates = {}
  -- Root level (relative & absolute)
  addVariants(candidates, libname)                           -- ./asevoxel_native.dll (current working dir)
  addVariants(candidates, "./" .. libname)
  addVariants(candidates, "." .. sep .. libname)
  addVariants(candidates, plugin_path .. sep .. libname)
  addVariants(candidates, plugin_path .. sep .. "bin" .. sep .. libname)
  addVariants(candidates, plugin_path .. sep .. "lib" .. sep .. libname)

  -- De-duplicate candidate list
  local seen = {}
  local filtered = {}
  for _, p in ipairs(candidates) do
    if not seen[p] then
      seen[p] = true
      filtered[#filtered+1] = p
    end
  end
  candidates = filtered

  local patterns = {
    plugin_path .. sep .. "?.dll",
    plugin_path .. sep .. "?\\init.dll",
    plugin_path .. sep .. "?.so",
    plugin_path .. sep .. "?/init.so",
    plugin_path .. sep .. "bin" .. sep .. "?.dll",
    plugin_path .. sep .. "bin" .. sep .. "?.so"
  }
  local extra = {}
  for _, p in ipairs(patterns) do
    if p:find("\\") then extra[#extra+1] = p:gsub("\\","/")
    elseif p:find("/") then extra[#extra+1] = p:gsub("/","\\") end
  end
  for _, e in ipairs(extra) do patterns[#patterns+1] = e end
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

  -- Fallback to existing logic
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

-- Force-disable native acceleration (debug)
function nativeBridge.setForceDisabled(v)
  nativeBridge._forceDisabled = not not v
end

-- Runtime status for debug panel
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

-- Phase 4: native stack renderer bridge
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
