-- Basic front-facing lighting (normal to camera)
-- Extracted from shading.lua::basicModeBrightness()

local basicLight = {}

basicLight.info = {
  id = "basic",
  name = "Basic Light",
  version = "1.0.0",
  author = "AseVoxel",
  category = "lighting",
  complexity = "O(n)",
  description = "Simple camera-facing lighting - faces toward camera are lit, faces away are shaded",
  supportsNative = true,
  requiresNormals = true,
  inputs = {"base_color", "normals"},
  outputs = {"color"}
}

basicLight.paramSchema = {
  {
    name = "lightIntensity",
    type = "slider",
    min = 0,
    max = 100,
    default = 50,
    label = "Light Intensity",
    tooltip = "Brightness for faces toward camera"
  },
  {
    name = "shadeIntensity",
    type = "slider",
    min = 0,
    max = 100,
    default = 50,
    label = "Shade Intensity",
    tooltip = "Brightness for faces away from camera"
  }
}

-- Helper: Normalize vector
local function normalize(v)
  local len = math.sqrt(v.x * v.x + v.y * v.y + v.z * v.z)
  if len > 0 then
    return {x = v.x / len, y = v.y / len, z = v.z / len}
  end
  return {x = 0, y = 0, z = 0}
end

-- Helper: Dot product
local function dot(a, b)
  return a.x * b.x + a.y * b.y + a.z * b.z
end

function basicLight.process(shaderData, params)
  -- Algorithm:
  -- 1. For each face, compute dot(faceNormal, cameraDirection)
  -- 2. Map dot from [-1, 1] to [shadeIntensity, lightIntensity]
  -- 3. brightness = shadeIntensity + (lightIntensity - shadeIntensity) * ((dot + 1) / 2)
  -- 4. Multiply face RGB by (brightness / 100)
  
  local lightIntensity = params.lightIntensity or 50
  local shadeIntensity = params.shadeIntensity or 50
  
  -- Get camera direction (normalized)
  local cameraDir = shaderData.camera.direction
  if not cameraDir then
    -- Fallback: compute from camera position to model center
    local camPos = shaderData.camera.position or {x=0, y=0, z=1}
    local midPoint = shaderData.middlePoint or {x=0, y=0, z=0}
    cameraDir = normalize({
      x = midPoint.x - camPos.x,
      y = midPoint.y - camPos.y,
      z = midPoint.z - camPos.z
    })
  end
  
  -- Process each face
  for i, face in ipairs(shaderData.faces or {}) do
    if face.normal and face.color then
      -- Compute dot product between face normal and camera direction
      local normalDot = dot(face.normal, cameraDir)
      
      -- Map from [-1, 1] to [shadeIntensity, lightIntensity]
      -- normalDot = -1 (facing away) → shadeIntensity
      -- normalDot = +1 (facing toward) → lightIntensity
      local t = (normalDot + 1.0) / 2.0  -- Map to [0, 1]
      local brightness = shadeIntensity + (lightIntensity - shadeIntensity) * t
      local factor = brightness / 100.0
      
      -- Apply brightness to color
      face.color.r = math.floor(face.color.r * factor + 0.5)
      face.color.g = math.floor(face.color.g * factor + 0.5)
      face.color.b = math.floor(face.color.b * factor + 0.5)
      -- Alpha unchanged
    end
  end
  
  return shaderData
end

return basicLight
