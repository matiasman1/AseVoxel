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
