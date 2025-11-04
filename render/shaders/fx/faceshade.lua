-- Fixed face brightness based on model-center normals (Alpha Full only)
-- Extracted from fx_stack.lua

local faceshade = {}

faceshade.info = {
  id = "faceshade",
  name = "FaceShade",
  version = "1.1.0",
  author = "AseVoxel",
  category = "fx",
  complexity = "O(n)",
  description = "Shade faces based on model-center axis with Alpha/Literal modes, Material filtering, optional Tint (6 directions)",
  supportsNative = true,
  requiresNormals = true,
  inputs = {"previous_shader"},
  outputs = {"color"}
}

faceshade.paramSchema = {
  {
    name = "shadingMode",
    type = "choice",
    options = {"alpha", "literal"},
    default = "alpha",
    label = "Mode",
    tooltip = "Alpha = brightness multiplier, Literal = replace with shade color"
  },
  {
    name = "materialMode",
    type = "bool",
    default = false,
    label = "Material Mode",
    tooltip = "Skip pure colors (preserve pure R/G/B/C/M/Y/K/W)"
  },
  {
    name = "enableTint",
    type = "bool",
    default = false,
    label = "Enable Tint",
    tooltip = "Apply color tint in Alpha mode"
  },
  {
    name = "alphaTint",
    type = "color",
    default = {r=255, g=255, b=255},
    label = "Tint Color",
    tooltip = "Color to tint with in Alpha mode (when enabled)"
  },
  {
    name = "topColor",
    type = "color",
    default = {r=255, g=255, b=255},
    label = "Top",
    tooltip = "Color for top-facing faces"
  },
  {
    name = "bottomColor",
    type = "color",
    default = {r=255, g=255, b=255},
    label = "Bottom",
    tooltip = "Color for bottom-facing faces"
  },
  {
    name = "frontColor",
    type = "color",
    default = {r=255, g=255, b=255},
    label = "Front",
    tooltip = "Color for front-facing faces"
  },
  {
    name = "backColor",
    type = "color",
    default = {r=255, g=255, b=255},
    label = "Back",
    tooltip = "Color for back-facing faces"
  },
  {
    name = "leftColor",
    type = "color",
    default = {r=255, g=255, b=255},
    label = "Left",
    tooltip = "Color for left-facing faces"
  },
  {
    name = "rightColor",
    type = "color",
    default = {r=255, g=255, b=255},
    label = "Right",
    tooltip = "Color for right-facing faces"
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

-- Helper: Check if color is pure (one channel 255, others near 0)
local function isPureColor(r, g, b)
  local threshold = 10  -- Tolerance for "near zero"
  
  local isPureR = (r >= 245) and (g <= threshold) and (b <= threshold)
  local isPureG = (g >= 245) and (r <= threshold) and (b <= threshold)
  local isPureB = (b >= 245) and (r <= threshold) and (g <= threshold)
  local isPureC = (g >= 245) and (b >= 245) and (r <= threshold)  -- Cyan
  local isPureM = (r >= 245) and (b >= 245) and (g <= threshold)  -- Magenta
  local isPureY = (r >= 245) and (g >= 245) and (b <= threshold)  -- Yellow
  local isPureK = (r <= threshold) and (g <= threshold) and (b <= threshold)  -- Black
  local isPureW = (r >= 245) and (g >= 245) and (b >= 245)  -- White
  
  return isPureR or isPureG or isPureB or isPureC or isPureM or isPureY or isPureK or isPureW
end

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
  -- Extract parameters
  local shadingMode = params.shadingMode or "alpha"
  local materialMode = params.materialMode or false
  local enableTint = params.enableTint or false
  local alphaTint = params.alphaTint or {r=255, g=255, b=255}
  
  -- Face colors (matching VoxelMaker behavior)
  local faceColors = {
    top = params.topColor or {r=255, g=255, b=255},
    bottom = params.bottomColor or {r=255, g=255, b=255},
    front = params.frontColor or {r=255, g=255, b=255},
    back = params.backColor or {r=255, g=255, b=255},
    left = params.leftColor or {r=255, g=255, b=255},
    right = params.rightColor or {r=255, g=255, b=255}
  }
  
  -- Legacy compatibility: convert brightness values to colors if provided
  if params.topBrightness then
    local b = params.topBrightness
    faceColors.top = {r=b, g=b, b=b}
  end
  if params.bottomBrightness then
    local b = params.bottomBrightness
    faceColors.bottom = {r=b, g=b, b=b}
  end
  if params.frontBrightness then
    local b = params.frontBrightness
    faceColors.front = {r=b, g=b, b=b}
  end
  if params.backBrightness then
    local b = params.backBrightness
    faceColors.back = {r=b, g=b, b=b}
  end
  if params.leftBrightness then
    local b = params.leftBrightness
    faceColors.left = {r=b, g=b, b=b}
  end
  if params.rightBrightness then
    local b = params.rightBrightness
    faceColors.right = {r=b, g=b, b=b}
  end
  
  -- Process each face
  for i, face in ipairs(shaderData.faces or {}) do
    if face.normal and face.color then
      -- Material mode check: skip pure colors
      if materialMode then
        if isPureColor(face.color.r, face.color.g, face.color.b) then
          goto continue  -- Skip this face
        end
      end
      
      -- Determine face direction from face name or normal
      local direction = face.face or getFaceDirection(face.normal)
      
      -- Get color for this direction
      local faceColor = faceColors[direction] or {r=255, g=255, b=255}
      
      if shadingMode == "alpha" then
        -- Alpha mode: use color alpha channel as brightness, RGB for optional tint
        local brightness = (faceColor.a or 255) / 255
        
        if enableTint then
          -- Apply color as tint
          local tintR = (faceColor.r or 255) / 255
          local tintG = (faceColor.g or 255) / 255
          local tintB = (faceColor.b or 255) / 255
          
          face.color.r = math.floor(face.color.r * brightness * tintR + 0.5)
          face.color.g = math.floor(face.color.g * brightness * tintG + 0.5)
          face.color.b = math.floor(face.color.b * brightness * tintB + 0.5)
        else
          -- Just apply brightness
          face.color.r = math.floor(face.color.r * brightness + 0.5)
          face.color.g = math.floor(face.color.g * brightness + 0.5)
          face.color.b = math.floor(face.color.b * brightness + 0.5)
        end
      elseif shadingMode == "literal" then
        -- Literal mode: replace RGB with face color
        face.color.r = faceColor.r or 255
        face.color.g = faceColor.g or 255
        face.color.b = faceColor.b or 255
      end
      
      -- Alpha unchanged
      
      ::continue::
    end
  end
  
  return shaderData
end

return faceshade
