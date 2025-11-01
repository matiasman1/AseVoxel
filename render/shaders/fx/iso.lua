-- Isometric shading with Alpha/Literal modes and Material/Full options
-- Extracted from fx_stack.lua

local iso = {}

iso.info = {
  id = "iso",
  name = "Isometric Shade",
  version = "1.0.0",
  author = "AseVoxel",
  category = "fx",
  complexity = "O(n)",
  description = "Classic isometric look with Alpha/Literal modes, Material filtering, optional Tint",
  supportsNative = false,  -- TODO: Implement native version
  requiresNormals = true,
  inputs = {"previous_shader"},
  outputs = {"color"}
}

iso.paramSchema = {
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
    name = "topBrightness",
    type = "slider",
    min = 0,
    max = 255,
    default = 255,
    label = "Top/Bottom",
    tooltip = "Brightness for top and bottom faces (0-255)"
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

-- Helper: Determine isometric face role (top, left, or right)
local function getIsoRole(normal, viewDir)
  -- Project normal onto camera view space
  -- Top = most upward facing (Y dominant)
  -- Left/Right = based on X projection in camera space
  
  local absY = math.abs(normal.y)
  local absX = math.abs(normal.x)
  local absZ = math.abs(normal.z)
  
  -- If Y is dominant, it's top or bottom
  if absY > absX and absY > absZ then
    return "top"
  end
  
  -- Otherwise, determine left or right based on X
  -- Negative X = left, Positive X = right
  if normal.x < 0 then
    return "left"
  else
    return "right"
  end
end

function iso.process(shaderData, params)
  -- Extract parameters
  local shadingMode = params.shadingMode or "alpha"
  local materialMode = params.materialMode or false
  local enableTint = params.enableTint or false
  local alphaTint = params.alphaTint or {r=255, g=255, b=255}
  
  local brightness = {
    top = params.topBrightness or 255,
    left = params.leftBrightness or 180,
    right = params.rightBrightness or 220
  }
  
  -- Get camera view direction
  local viewDir = shaderData.camera.direction
  if not viewDir then
    viewDir = {x = 0, y = 0, z = 1}
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
      
      -- Determine isometric role
      local role = getIsoRole(face.normal, viewDir)
      local b = brightness[role] or 255
      
      if shadingMode == "alpha" then
        -- Alpha mode: multiply RGB by brightness factor
        local factor = b / 255
        
        if enableTint then
          -- Apply tint as well
          local tintR = (alphaTint.r or 255) / 255
          local tintG = (alphaTint.g or 255) / 255
          local tintB = (alphaTint.b or 255) / 255
          
          face.color.r = math.floor(face.color.r * factor * tintR + 0.5)
          face.color.g = math.floor(face.color.g * factor * tintG + 0.5)
          face.color.b = math.floor(face.color.b * factor * tintB + 0.5)
        else
          face.color.r = math.floor(face.color.r * factor + 0.5)
          face.color.g = math.floor(face.color.g * factor + 0.5)
          face.color.b = math.floor(face.color.b * factor + 0.5)
        end
      elseif shadingMode == "literal" then
        -- Literal mode: replace RGB with brightness level
        face.color.r = b
        face.color.g = b
        face.color.b = b
      end
      
      -- Alpha unchanged
      
      ::continue::
    end
  end
  
  return shaderData
end

return iso
