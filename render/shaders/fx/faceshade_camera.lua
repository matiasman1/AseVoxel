-- Camera-relative face shading (no back faces)
-- NEW shader implementing camera-based face shading

local faceshadeCamera = {}

faceshadeCamera.info = {
  id = "faceshadeCamera",
  name = "FaceShade (Camera)",
  version = "1.0.0",
  author = "AseVoxel",
  category = "fx",
  complexity = "O(n)",
  description = "Shade faces based on camera projection (Alpha Full only)",
  supportsNative = false,  -- TODO: Implement native version
  requiresNormals = true,
  inputs = {"previous_shader"},
  outputs = {"color"}
}

faceshadeCamera.paramSchema = {
  {
    name = "frontBrightness",
    type = "slider",
    min = 0,
    max = 255,
    default = 255,
    label = "Front",
    tooltip = "Brightness for faces toward camera (0-255)"
  },
  {
    name = "topBrightness",
    type = "slider",
    min = 0,
    max = 255,
    default = 220,
    label = "Top",
    tooltip = "Brightness for upward-facing faces (0-255)"
  },
  {
    name = "leftBrightness",
    type = "slider",
    min = 0,
    max = 255,
    default = 180,
    label = "Left",
    tooltip = "Brightness for left-facing faces (0-255)"
  },
  {
    name = "rightBrightness",
    type = "slider",
    min = 0,
    max = 255,
    default = 200,
    label = "Right",
    tooltip = "Brightness for right-facing faces (0-255)"
  },
  {
    name = "bottomBrightness",
    type = "slider",
    min = 0,
    max = 255,
    default = 128,
    label = "Bottom",
    tooltip = "Brightness for downward-facing faces (0-255)"
  }
}

-- Helper: Normalize vector
local function normalize(v)
  local len = math.sqrt(v.x * v.x + v.y * v.y + v.z * v.z)
  if len > 1e-6 then
    return {x = v.x / len, y = v.y / len, z = v.z / len}
  end
  return {x = 0, y = 0, z = 0}
end

-- Helper: Determine camera-relative face direction
local function getCameraDirection(normal, viewDir, cameraUp)
  -- Project normal to camera view space
  -- Determine dominant direction: front/top/left/right/bottom
  
  -- Camera right vector (perpendicular to view and up)
  local right = {
    x = viewDir.y * cameraUp.z - viewDir.z * cameraUp.y,
    y = viewDir.z * cameraUp.x - viewDir.x * cameraUp.z,
    z = viewDir.x * cameraUp.y - viewDir.y * cameraUp.x
  }
  right = normalize(right)
  
  -- Dot products with camera basis vectors
  local dotView = normal.x * viewDir.x + normal.y * viewDir.y + normal.z * viewDir.z
  local dotUp = normal.x * cameraUp.x + normal.y * cameraUp.y + normal.z * cameraUp.z
  local dotRight = normal.x * right.x + normal.y * right.y + normal.z * right.z
  
  -- Find dominant direction
  local absView = math.abs(dotView)
  local absUp = math.abs(dotUp)
  local absRight = math.abs(dotRight)
  
  if absView > absUp and absView > absRight then
    -- Front/back dominant (but back faces are culled, so this is front)
    return dotView > 0 and "front" or "front"  -- Back faces shouldn't be visible
  elseif absUp > absRight then
    -- Top/bottom dominant
    return dotUp > 0 and "top" or "bottom"
  else
    -- Left/right dominant
    return dotRight > 0 and "right" or "left"
  end
end

function faceshadeCamera.process(shaderData, params)
  -- Extract brightness parameters
  local brightness = {
    front = params.frontBrightness or 255,
    top = params.topBrightness or 220,
    left = params.leftBrightness or 180,
    right = params.rightBrightness or 200,
    bottom = params.bottomBrightness or 128
  }
  
  -- Get camera vectors
  local viewDir = shaderData.camera.direction
  if not viewDir then
    -- Fallback: compute from camera position to model center
    local camPos = shaderData.camera.position or {x=0, y=0, z=1}
    local midPoint = shaderData.middlePoint or {x=0, y=0, z=0}
    viewDir = normalize({
      x = midPoint.x - camPos.x,
      y = midPoint.y - camPos.y,
      z = midPoint.z - camPos.z
    })
  end
  
  -- Camera up vector (assume Y-up for now)
  local cameraUp = {x = 0, y = 1, z = 0}
  
  -- Process each face
  for i, face in ipairs(shaderData.faces or {}) do
    if face.normal and face.color then
      -- Determine camera-relative direction
      local direction = getCameraDirection(face.normal, viewDir, cameraUp)
      
      -- Get brightness for this direction
      local b = brightness[direction] or 255
      local factor = b / 255
      
      -- Apply brightness multiplier to RGB
      face.color.r = math.floor(face.color.r * factor + 0.5)
      face.color.g = math.floor(face.color.g * factor + 0.5)
      face.color.b = math.floor(face.color.b * factor + 0.5)
      -- Alpha unchanged
    end
  end
  
  return shaderData
end

return faceshadeCamera
