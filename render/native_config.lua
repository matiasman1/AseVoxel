-- Native Shader Configuration
-- Controls whether to use native C++ shaders or Lua shaders
-- FREE VERSION: forceNative = false (Lua only)
-- PAID VERSION: forceNative = true (Native with Lua fallback)

local nativeConfig = {
  -- Set to true for PAID version (use native shaders when available)
  -- Set to false for FREE version (always use Lua shaders)
  forceNative = false,
  
  -- Native shader support map (which shaders have C++ implementations)
  nativeShaders = {
    lighting = {
      basic = true,
      dynamic = true
    },
    fx = {
      faceshade = true,
      faceshadeCamera = true,
      iso = true
    }
  },
  
  -- Check if a shader has native support
  hasNativeSupport = function(self, shaderType, shaderId)
    if not self.forceNative then
      return false
    end
    if not shaderId then return false end
    local group
    if shaderType == "lighting" then
      group = self.nativeShaders.lighting
    elseif shaderType == "fx" then
      group = self.nativeShaders.fx
    end
    return group and group[shaderId] == true
  end,
  
  -- Check if entire stack can be executed natively
  canUseNativeStack = function(self, stackConfig)
    if not self.forceNative then
      return false
    end
    
    -- Check all lighting shaders
    if stackConfig.lighting then
      for _, shader in ipairs(stackConfig.lighting) do
        if shader.enabled and shader.id then
          if not self:hasNativeSupport("lighting", shader.id) then
            return false
          end
        end
      end
    end
    
    -- Check all FX shaders
    if stackConfig.fx then
      for _, shader in ipairs(stackConfig.fx) do
        if shader.enabled and shader.id then
          if not self:hasNativeSupport("fx", shader.id) then
            return false
          end
        end
      end
    end
    
    return true
  end,
  
  -- Get version string
  getVersion = function(self)
    return self.forceNative and "PAID (Native C++)" or "FREE (Lua)"
  end
}

function nativeConfig:refreshNativeShaders()
  local info
  if package.loaded then
    local mod = package.loaded["asevoxel_native"]
    if type(mod) == "table" and type(mod.get_native_shaders) == "function" then
      local ok, res = pcall(mod.get_native_shaders)
      if ok and type(res) == "table" then info = res end
    end
  end
  if not info then
    local okBridge, bridge = pcall(function()
      return AseVoxel and AseVoxel.render and AseVoxel.render.native_bridge
    end)
    if okBridge and bridge and type(bridge.getNativeShaders) == "function" then
      local okRes, res = pcall(bridge.getNativeShaders)
      if okRes and type(res) == "table" then info = res end
    end
  end
  if info then
    if type(info.lighting) ~= "table" then info.lighting = {} end
    if type(info.fx) ~= "table" then info.fx = {} end
    self.nativeShaders = info
  end
  return self.nativeShaders
end

nativeConfig:refreshNativeShaders()

return nativeConfig
