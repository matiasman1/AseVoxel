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
      iso = true
    }
  },
  
  -- Check if a shader has native support
  hasNativeSupport = function(self, shaderType, shaderId)
    if not self.forceNative then
      return false
    end
    if not shaderId then return false end
    if shaderType == "lighting" then
      return self.nativeShaders.lighting[shaderId] == true
    elseif shaderType == "fx" then
      return self.nativeShaders.fx[shaderId] == true
    end
    return false
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

return nativeConfig
