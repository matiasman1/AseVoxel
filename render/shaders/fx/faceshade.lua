-- Fixed face brightness based on model-center normals (Alpha Full only)
-- Extracted from fx_stack.lua

local faceshade = {}

faceshade.info = {
  id = "faceshade",
  name = "FaceShade",
  version = "1.0.0",
  author = "AseVoxel",
  category = "fx",
  complexity = "O(n)",
  description = "Shade faces based on model-center axis (brightness multiplier only)",
  supportsNative = false,  -- TODO: Implement native version
  requiresNormals = true,
  inputs = {"previous_shader"},
  outputs = {"color"}
}

faceshade.paramSchema = {
  {
    name = "topBrightness",
    type = "slider",
    min = 0,
    max = 255,
    default = 255,
    label = "Top",
    tooltip = "Brightness for top-facing faces (0-255)"
  },
  {
    name = "bottomBrightness",
    type = "slider",
    min = 0,
    max = 255,
    default = 128,
    label = "Bottom",
    tooltip = "Brightness for bottom-facing faces (0-255)"
  },
  {
    name = "frontBrightness",
    type = "slider",
    min = 0,
    max = 255,
    default = 200,
    label = "Front",
    tooltip = "Brightness for front-facing faces (0-255)"
  },
  {
    name = "backBrightness",
    type = "slider",
    min = 0,
    max = 255,
    default = 150,
    label = "Back",
    tooltip = "Brightness for back-facing faces (0-255)"
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
    default = 220,
    label = "Right",
    tooltip = "Brightness for right-facing faces (0-255)"
  }
}

-- Local normals for each face (model-space, not rotated)
local FACE_NORMALS = {
  top    = {x = 0,  y = 1,  z = 0},
  bottom = {x = 0,  y = -1, z = 0},
  front  = {x = 0,  y = 0,  z = 1},
  back   = {x = 0,  y = 0,  z = -1},
  left   = {x = -1, y = 0,  z = 0},
  right  = {x = 1,  y = 0,  z = 0}
}

-- Helper: Determine face direction from normal
local function getFaceDirection(normal)
  -- Find which axis has the largest absolute component
  local absX = math.abs(normal.x)
  local absY = math.abs(normal.y)
  local absZ = math.abs(normal.z)
  
  if absY > absX and absY > absZ then
    -- Y is dominant
    return normal.y > 0 and "top" or "bottom"
  elseif absX > absZ then
    -- X is dominant
    return normal.x > 0 and "right" or "left"
  else
    -- Z is dominant
    return normal.z > 0 and "front" or "back"
  end
end

function faceshade.process(shaderData, params)
  -- Extract brightness parameters
  local brightness = {
    top = params.topBrightness or 255,
    bottom = params.bottomBrightness or 128,
    front = params.frontBrightness or 200,
    back = params.backBrightness or 150,
    left = params.leftBrightness or 180,
    right = params.rightBrightness or 220
  }
  
  -- Process each face
  for i, face in ipairs(shaderData.faces or {}) do
    if face.normal and face.color then
      -- Determine face direction from normal
      local direction = face.face or getFaceDirection(face.normal)
      
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

return faceshade
