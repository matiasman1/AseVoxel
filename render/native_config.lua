-- Native Shader Configuration
-- Controls whether to use native C++ shaders or Lua shaders
-- FREE VERSION: forceNative = false (Lua only)
-- PAID VERSION: forceNative = true (Native with Lua fallback)

local nativeBridge -- lazy-loaded
local function getNativeBridge()
  if nativeBridge == nil then
    local ok, mod = pcall(require, 'render.native_bridge')
    if not ok then
      ok, mod = pcall(require, 'native_bridge')
    end
    if ok and type(mod) == 'table' then
      nativeBridge = mod
    else
      nativeBridge = false
    end
  end
  return nativeBridge ~= false and nativeBridge or nil
end

local fallbackNativeShaders = {
  lighting = {
    basic = true,
    dynamic = true
  },
  fx = {
    faceshade = true,
    iso = true
  }
}

local nativeConfig = {
  -- Set to true for PAID version (use native shaders when available)
  -- Set to false for FREE version (always use Lua shaders)
  forceNative = false,
  _catalog = nil
}

local function lookupCatalogEntry(self, shaderType, shaderId)
  if self._catalog == nil then
    local bridge = getNativeBridge()
    if bridge and bridge.getNativeShaderCatalog then
      local catalog = bridge.getNativeShaderCatalog()
      if type(catalog) == 'table' then
        self._catalog = catalog
      else
        self._catalog = false
      end
    else
      self._catalog = false
    end
  end

  local catalog = self._catalog
  if catalog == false then
    catalog = nil
  end
  if not catalog then
    return nil
  end

  local list = catalog[shaderType]
  if type(list) ~= 'table' then
    return nil
  end

  for _, entry in ipairs(list) do
    if entry.id == shaderId then
      return entry
    end
  end

  return nil
end

function nativeConfig:refreshCatalog()
  local bridge = getNativeBridge()
  if bridge and bridge.getNativeShaderCatalog then
    local catalog = bridge.getNativeShaderCatalog(true)
    if type(catalog) == 'table' then
      self._catalog = catalog
      return catalog
    end
  end
  self._catalog = false
  return nil
end

function nativeConfig:hasNativeSupport(shaderType, shaderId)
  if not shaderId then
    return false
  end

  local entry = lookupCatalogEntry(self, shaderType, shaderId)
  if entry then
    return entry.supportsNative ~= false
  end

  local fallbackGroup = fallbackNativeShaders[shaderType]
  if fallbackGroup then
    return fallbackGroup[shaderId] == true
  end
  return false
end

function nativeConfig:canUseNativeStack(stackConfig)
  if not self.forceNative then
    return false
  end

  stackConfig = stackConfig or {}

  if stackConfig.lighting then
    for _, shader in ipairs(stackConfig.lighting) do
      if shader.enabled ~= false and shader.id then
        if not self:hasNativeSupport('lighting', shader.id) then
          return false
        end
      end
    end
  end

  if stackConfig.fx then
    for _, shader in ipairs(stackConfig.fx) do
      if shader.enabled ~= false and shader.id then
        if not self:hasNativeSupport('fx', shader.id) then
          return false
        end
      end
    end
  end

  return true
end

function nativeConfig:getVersion()
  return self.forceNative and 'PAID (Native C++)' or 'FREE (Lua)'
end

return nativeConfig
