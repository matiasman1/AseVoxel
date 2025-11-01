-- Physically-inspired lighting with pitch/yaw/diffuse/ambient/rim
-- Extracted from shading.lua + preview_renderer.lua dynamic lighting code

local dynamicLight = {}

dynamicLight.info = {
  id = "dynamic",
  name = "Dynamic Lighting",
  version = "1.0.0",
  author = "AseVoxel",
  category = "lighting",
  complexity = "O(n)",
  description = "Advanced lighting with directional light, falloff, and rim",
  supportsNative = false,  -- TODO: Implement native version
  requiresNormals = true,
  requiresGeometry = true,  -- For radial attenuation
  inputs = {"base_color", "normals", "geometry"},
  outputs = {"color"}
}

dynamicLight.paramSchema = {
  {
    name = "pitch",
    type = "slider",
    min = -90,
    max = 90,
    default = 25,
    label = "Pitch",
    tooltip = "Vertical angle of light direction"
  },
  {
    name = "yaw",
    type = "slider",
    min = 0,
    max = 360,
    default = 25,
    label = "Yaw",
    tooltip = "Horizontal angle of light direction"
  },
  {
    name = "diffuse",
    type = "slider",
    min = 0,
    max = 100,
    default = 60,
    label = "Diffuse",
    tooltip = "Diffuse lighting intensity"
  },
  {
    name = "ambient",
    type = "slider",
    min = 0,
    max = 100,
    default = 30,
    label = "Ambient",
    tooltip = "Ambient lighting intensity"
  },
  {
    name = "diameter",
    type = "slider",
    min = 0,
    max = 200,
    default = 100,
    label = "Diameter",
    tooltip = "Light cone diameter (0 = no radial attenuation)"
  },
  {
    name = "rimEnabled",
    type = "bool",
    default = false,
    label = "Rim Lighting",
    tooltip = "Enable rim/silhouette lighting"
  },
  {
    name = "lightColor",
    type = "color",
    default = {r=255, g=255, b=255},
    label = "Light Color",
    tooltip = "Color of the light"
  }
}

-- Helper: Compute light direction from yaw/pitch angles
local function computeLightDirection(yaw, pitch)
  local yawRad = math.rad(yaw)
  local pitchRad = math.rad(pitch)
  
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

-- Helper: Smooth step function
local function smoothstep(edge0, edge1, x)
  if x <= edge0 then return 0 end
  if x >= edge1 then return 1 end
  local t = (x - edge0) / (edge1 - edge0)
  return t * t * (3 - 2 * t)
end

-- Helper: Normalize vector
local function normalize(v)
  local len = math.sqrt(v.x * v.x + v.y * v.y + v.z * v.z)
  if len > 1e-6 then
    return {x = v.x / len, y = v.y / len, z = v.z / len}
  end
  return {x = 0, y = 0, z = 0}
end

-- Helper: Dot product
local function dot(a, b)
  return a.x * b.x + a.y * b.y + a.z * b.z
end

function dynamicLight.process(shaderData, params)
  -- Extract parameters
  local pitch = params.pitch or 25
  local yaw = params.yaw or 25
  local diffuseIntensity = (params.diffuse or 60) / 100
  local ambientIntensity = (params.ambient or 30) / 100
  local diameter = params.diameter or 100
  local rimEnabled = params.rimEnabled or false
  local lightColor = params.lightColor or {r=255, g=255, b=255}
  
  -- Normalize light color to [0, 1]
  local lr = (lightColor.r or 255) / 255
  local lg = (lightColor.g or 255) / 255
  local lb = (lightColor.b or 255) / 255
  
  -- Compute light direction
  local lightDir = computeLightDirection(yaw, pitch)
  
  -- Compute view direction (camera to model)
  local viewDir = shaderData.camera.direction
  if not viewDir then
    local camPos = shaderData.camera.position or {x=0, y=0, z=1}
    local midPoint = shaderData.middlePoint or {x=0, y=0, z=0}
    viewDir = normalize({
      x = midPoint.x - camPos.x,
      y = midPoint.y - camPos.y,
      z = midPoint.z - camPos.z
    })
  end
  
  -- Compute exponent for Lambert term (based on diffuse intensity)
  -- Higher diffuse = sharper falloff
  local exponent = 1 + (1 - diffuseIntensity) * 3
  
  -- Process each face
  for i, face in ipairs(shaderData.faces or {}) do
    if face.normal and face.color then
      local normal = face.normal
      
      -- Lambert diffuse term: ndotl = max(0, dot(normal, lightDir))
      local ndotl = dot(normal, lightDir)
      if ndotl < 0 then ndotl = 0 end
      
      -- Apply exponent to diffuse
      local diffuse = ndotl ^ exponent
      
      -- Radial attenuation (distance from light axis)
      -- If diameter > 0, attenuate based on perpendicular distance from axis
      if diameter > 0 and face.voxel then
        local voxelPos = face.voxel
        local midPoint = shaderData.middlePoint or {x=0, y=0, z=0}
        
        -- Vector from middle to voxel
        local toVoxel = {
          x = voxelPos.x - midPoint.x,
          y = voxelPos.y - midPoint.y,
          z = voxelPos.z - midPoint.z
        }
        
        -- Project onto light direction to get distance along axis
        local alongAxis = dot(toVoxel, lightDir)
        
        -- Perpendicular distance from axis
        local perpX = toVoxel.x - alongAxis * lightDir.x
        local perpY = toVoxel.y - alongAxis * lightDir.y
        local perpZ = toVoxel.z - alongAxis * lightDir.z
        local perpDist = math.sqrt(perpX * perpX + perpY * perpY + perpZ * perpZ)
        
        -- Attenuation based on diameter
        local radius = diameter / 2
        if radius > 0 then
          local radialFactor = 1 - (perpDist / radius)
          if radialFactor < 0 then radialFactor = 0 end
          diffuse = diffuse * radialFactor
        end
      end
      
      -- Multiply diffuse by intensity
      diffuse = diffuse * diffuseIntensity
      
      -- Get base color
      local baseR = face.color.r or 255
      local baseG = face.color.g or 255
      local baseB = face.color.b or 255
      
      -- Calculate lit color: ambient + diffuse
      local r = baseR * (ambientIntensity + diffuse * lr)
      local g = baseG * (ambientIntensity + diffuse * lg)
      local b = baseB * (ambientIntensity + diffuse * lb)
      
      -- Rim lighting (Fresnel effect)
      if rimEnabled then
        local ndotv = dot(normal, viewDir)
        if ndotv > 0 then
          local edge = 1 - ndotv
          local rimStart, rimEnd = 0.55, 0.95
          local t = smoothstep(rimStart, rimEnd, edge)
          
          if t > 0 then
            local rimStrength = 0.6
            local rim = rimStrength * t
            r = r + lr * rim * 255
            g = g + lg * rim * 255
            b = b + lb * rim * 255
          end
        end
      end
      
      -- Clamp to [0, 255]
      r = (r < 0 and 0) or (r > 255 and 255 or math.floor(r + 0.5))
      g = (g < 0 and 0) or (g > 255 and 255 or math.floor(g + 0.5))
      b = (b < 0 and 0) or (b > 255 and 255 or math.floor(b + 0.5))
      
      -- Update face color
      face.color.r = r
      face.color.g = g
      face.color.b = b
      -- Alpha unchanged
    end
  end
  
  return shaderData
end

return dynamicLight
