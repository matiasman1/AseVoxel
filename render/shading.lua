-- shading.lua
-- Lighting calculations and face shading

local shading = {}

-- Lazy loaders
local function getMathUtils()
  return AseVoxel.mathUtils
end

local function getFxStack()
  return AseVoxel.fxStack
end

local function getFaceVisibility()
  return AseVoxel.render.face_visibility
end

--------------------------------------------------------------------------------
-- Basic Mode Brightness (Formula B implementation)
--------------------------------------------------------------------------------
local function basicModeBrightness(faceName, rotationMatrix, viewDir, params, FACE_NORMALS)
  local n = FACE_NORMALS[faceName]
  if not n then return 1 end
  local nn = {
    rotationMatrix[1][1]*n[1] + rotationMatrix[1][2]*n[2] + rotationMatrix[1][3]*n[3],
    rotationMatrix[2][1]*n[1] + rotationMatrix[2][2]*n[2] + rotationMatrix[2][3]*n[3],
    rotationMatrix[3][1]*n[1] + rotationMatrix[3][2]*n[2] + rotationMatrix[3][3]*n[3],
  }
  local mag = math.sqrt(nn[1]*nn[1]+nn[2]*nn[2]+nn[3]*nn[3])
  if mag > 1e-6 then nn[1],nn[2],nn[3] = nn[1]/mag, nn[2]/mag, nn[3]/mag end
  local dot = nn[1]*viewDir[1] + nn[2]*viewDir[2] + nn[3]*viewDir[3]
  if dot <= 0 then dot = 0 end

  -- Basic shading formula B:
  -- si = basicShadeIntensity/100; li = basicLightIntensity/100;
  -- minB = 0.05 + 0.9*li
  -- curve = (1 - si)^2
  -- exponent = 1 + 6*curve
  -- brightness = minB + (1 - minB) * (dot^exponent)
  local si = (params.basicShadeIntensity or 50) / 100
  local li = (params.basicLightIntensity or 50) / 100
  
  local minB = 0.05 + 0.9 * li
  local curve = (1 - si) * (1 - si)
  local exponent = 1 + 6 * curve
  local brightness = minB + (1 - minB) * (dot ^ exponent)

  return brightness
end

--------------------------------------------------------------------------------
-- Dynamic Lighting System
--------------------------------------------------------------------------------
-- Compute light direction from yaw/pitch angles
function shading.computeLightDirection(yaw, pitch)
  local yawRad = math.rad(yaw)
  local pitchRad = math.rad(pitch)
  
  -- Light direction: yaw around Y-axis, pitch around X-axis
  local cosYaw = math.cos(yawRad)
  local sinYaw = math.sin(yawRad)
  local cosPitch = math.cos(pitchRad)
  local sinPitch = math.sin(pitchRad)
  
  return {
    x = cosYaw * cosPitch,
    y = sinPitch,
    z = sinYaw * cosPitch
  }
end

-- Smooth step function for falloffs
function shading.smoothstep(edge0, edge1, x)
  if x <= edge0 then return 0 end
  if x >= edge1 then return 1 end
  local t = (x - edge0) / (edge1 - edge0)
  return t * t * (3 - 2 * t)
end

-- Linear interpolation
function shading.lerp(a, b, t)
  return a + (b - a) * t
end

-- Legacy function retained for compatibility (returns 1, passthrough)
function shading.computeAngularFalloff(lightDir, normal, directionality, diffuse)
  return 1, lightDir.x * normal.x + lightDir.y * normal.y + lightDir.z * normal.z
end

-- Cache rotated normals once per frame
function shading.cacheRotatedNormals(rotationMatrix)
  local faceVis = getFaceVisibility()
  local FACE_NORMALS = faceVis.FACE_NORMALS
  
  local rotatedNormals = {}
  for name, n in pairs(FACE_NORMALS) do
    rotatedNormals[name] = {
      x = rotationMatrix[1][1]*n[1] + rotationMatrix[1][2]*n[2] + rotationMatrix[1][3]*n[3],
      y = rotationMatrix[2][1]*n[1] + rotationMatrix[2][2]*n[2] + rotationMatrix[2][3]*n[3],
      z = rotationMatrix[3][1]*n[1] + rotationMatrix[3][2]*n[2] + rotationMatrix[3][3]*n[3]
    }
    -- Normalize
    local mag = math.sqrt(rotatedNormals[name].x^2 + rotatedNormals[name].y^2 + rotatedNormals[name].z^2)
    if mag > 1e-6 then
      rotatedNormals[name].x = rotatedNormals[name].x / mag
      rotatedNormals[name].y = rotatedNormals[name].y / mag
      rotatedNormals[name].z = rotatedNormals[name].z / mag
    end
  end
  return rotatedNormals
end

--------------------------------------------------------------------------------
-- Core Shaded Face Drawing (updated for Basic/Dynamic/Stack modes)
--------------------------------------------------------------------------------
-- Unified shading implementation (supports legacy aliases + cache)
function shading.shadeFaceColor(faceName, baseColor, params)
  local mathUtils = getMathUtils()
  local fxStackModule = getFxStack()
  local faceVis = getFaceVisibility()
  local FACE_NORMALS = faceVis.FACE_NORMALS
  
  local shadingMode = params.shadingMode or "Stack"
  -- Normalize legacy aliases
  if shadingMode == "Complete" then shadingMode = "Dynamic" end
  if shadingMode == "Simple" then shadingMode = "Basic" end

  -- Dynamic lighting mode (standalone)
  if shadingMode == "Dynamic" then
    -- Accept legacy AND newer field names to avoid silent fallback
    local lighting = params.lighting
    -- dynamicLighting (older) vs dyn (newer)
    local dyn = params.dynamicLighting or params.dyn
    -- rotatedFaceNormals (older) vs rotatedNormals (alternate path in drawVoxel)
    local rotatedNormals = params.rotatedFaceNormals or params.rotatedNormals
    -- Per‑voxel vector name harmonization: lightVector (apex) else fallback to directional dyn.lightDir
    local L = params.lightVector or (dyn and dyn.lightDir)

    if not lighting then return baseColor end

    -- Primary cache: lighting._cache (choice 1:A). Accept legacy fallbacks.
    local cache = lighting._cache
                 or params._dynLightCache
                 or params.dyn
                 or params.dynamicLighting
    if not cache or not cache.rotatedNormals or not cache.lightDir then
      return baseColor
    end

    local normal = cache.rotatedNormals[faceName]
                   or (cache.rotatedFaceNormals and cache.rotatedFaceNormals[faceName])
    if not normal then return baseColor end

    -- Lambert term
    local ndotl = normal.x * cache.lightDir.x + normal.y * cache.lightDir.y + normal.z * cache.lightDir.z
    if ndotl < 0 then ndotl = 0 end

    local exponent = cache.exponent or 1
    local diffuse = ndotl ^ exponent

    -- Radial attenuation (per-voxel factor set by render loop)
    local radial = params._radialFactor or 1
    diffuse = diffuse * radial

    -- Shadow factor (simple placeholder / binary shadow can be added later)
    local shadow = params.shadowFactor
    if shadow == nil then shadow = 1 end
    diffuse = diffuse * shadow

    local baseR = baseColor.red or baseColor.r or 255
    local baseG = baseColor.green or baseColor.g or 255
    local baseB = baseColor.blue or baseColor.b or 255

    local lc = cache.lightColor or {r=1,g=1,b=1}
    local lr, lg, lb = (lc.r or 1), (lc.g or 1), (lc.b or 1)
    local ambient = cache.ambient or 0

    local r = baseR * (ambient + diffuse * lr)
    local g = baseG * (ambient + diffuse * lg)
    local b = baseB * (ambient + diffuse * lb)

    -- Rim: silhouette smoothstep (choice 4:A)
    if lighting.rimEnabled and cache.viewDir then
      local V = cache.viewDir
      local ndotv = normal.x * V.x + normal.y * V.y + normal.z * V.z
      if ndotv > 0 then
        local edge = 1 - ndotv
        local rimStart, rimEnd = 0.55, 0.95
        local t = 0
        if edge <= rimStart then
          t = 0
        elseif edge >= rimEnd then
          t = 1
        else
          local tt = (edge - rimStart) / (rimEnd - rimStart)
          t = tt*tt*(3 - 2*tt)
        end
        if t > 0 then
          local rimStrength = 0.6 -- Patch 1: rimStrength fixed (deprecated control)
          local rim = rimStrength * t
          r = r + lr * rim * 255
          g = g + lg * rim * 255
          b = b + rimStrength * rim * 255
        end
      end
    end

    r = (r < 0 and 0) or (r > 255 and 255 or math.floor(r + 0.5))
    g = (g < 0 and 0) or (g > 255 and 255 or math.floor(g + 0.5))
    b = (b < 0 and 0) or (b > 255 and 255 or math.floor(b + 0.5))
    return Color(r, g, b, baseColor.alpha or baseColor.a or 255)
  end

  -- Basic mode (renamed)
  if shadingMode == "Basic" then
    local M = params._rotationMatrixForFX
    if not M then
      M = mathUtils.createRotationMatrix(params.xRotation or 0, params.yRotation or 0, params.zRotation or 0)
      params._rotationMatrixForFX = M
    end
    params.viewDir = params.viewDir or {x=0,y=0,z=1}
    local vd = params.viewDir
    local mag = math.sqrt(vd.x*vd.x+vd.y*vd.y+vd.z*vd.z)
    if mag > 1e-6 then vd.x,vd.y,vd.z = vd.x/mag, vd.y/mag, vd.z/mag end
    local b = basicModeBrightness(faceName, M, {vd.x,vd.y,vd.z}, params, FACE_NORMALS)
    local r = math.floor((baseColor.red or baseColor.r) * b + 0.5)
    local g = math.floor((baseColor.green or baseColor.g) * b + 0.5)
    local bl = math.floor((baseColor.blue or baseColor.b) * b + 0.5)
    return Color(r,g,bl, baseColor.alpha or baseColor.a or 255)
  end

  -- Stack mode (FX)
  if shadingMode == "Stack" and params.fxStack and params.fxStack.modules and #params.fxStack.modules > 0 then
    if not params._rotationMatrixForFX then
      params._rotationMatrixForFX =
        mathUtils.createRotationMatrix(params.xRotation or 0, params.yRotation or 0, params.zRotation or 0)
    end
    params.viewDir = params.viewDir or {x=0,y=0,z=1}
    local shaded = fxStackModule.shadeFace({
        rotationMatrix = params._rotationMatrixForFX,
        viewDir = params.viewDir,
        fxStack = params.fxStack
      },
      faceName,
      {
        r = baseColor.red or baseColor.r,
        g = baseColor.green or baseColor.g,
        b = baseColor.blue or baseColor.b,
        a = baseColor.alpha or baseColor.a or 255
      }
    )
    return Color(shaded.r, shaded.g, shaded.b, shaded.a)
  end

  return baseColor
end

return shading
