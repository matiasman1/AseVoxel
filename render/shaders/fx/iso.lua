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
  supportsNative = true,
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
    name = "topColor",
    type = "color",
    default = {r=255, g=255, b=255},
    label = "Top",
    tooltip = "Color for top/bottom isometric faces"
  },
  {
    name = "leftColor",
    type = "color",
    default = {r=235, g=235, b=235},
    label = "Left",
    tooltip = "Color for left isometric faces"
  },
  {
    name = "rightColor",
    type = "color",
    default = {r=210, g=210, b=210},
    label = "Right",
    tooltip = "Color for right isometric faces"
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

-- Isometric face selection algorithm (matching VoxelMaker fxStack.lua)
local function selectIsoFaces(faces, threshold)
  threshold = threshold or 0.01
  
  -- Build lookup by face name
  local faceMap = {}
  for _, face in ipairs(faces) do
    if face.face and face.normal then
      faceMap[face.face] = {
        normal = face.normal,
        dot = face.normal.z  -- Dot with camera direction (0,0,1)
      }
    end
  end
  
  -- 1) Pick TOP from physical top/bottom based on which faces toward camera more
  local dTop = (faceMap.top and faceMap.top.dot) or -math.huge
  local dBottom = (faceMap.bottom and faceMap.bottom.dot) or -math.huge
  local isoTop = (dTop >= dBottom) and "top" or "bottom"
  
  -- 2) Collect side candidates (front/back/left/right)
  local sideNames = {"front", "back", "left", "right"}
  local sides = {}
  for _, name in ipairs(sideNames) do
    local info = faceMap[name]
    if info then
      table.insert(sides, {
        face = name,
        dot = info.dot or -math.huge,
        nx = info.normal.x or 0
      })
    end
  end
  
  -- Prefer visible faces (dot > threshold). If fewer than 2, fall back to best by dot
  local visibles = {}
  for _, s in ipairs(sides) do
    if s.dot > threshold then
      table.insert(visibles, s)
    end
  end
  
  local pool = (#visibles >= 2) and visibles or sides
  table.sort(pool, function(a, b) return a.dot > b.dot end)
  
  local s1 = pool[1]
  local s2 = pool[2]
  
  if not s1 or not s2 then
    return {top = isoTop, left = nil, right = nil}
  end
  
  -- 3) Assign LEFT/RIGHT by normal.x
  -- Larger +nx => RIGHT; smaller (or negative) => LEFT
  local isoLeft, isoRight
  if s1.nx > s2.nx then
    isoRight = s1.face
    isoLeft = s2.face
  else
    isoRight = s2.face
    isoLeft = s1.face
  end
  
  return {
    top = isoTop,
    left = isoLeft,
    right = isoRight
  }
end

function iso.process(shaderData, params)
  -- Extract parameters
  local shadingMode = params.shadingMode or "alpha"
  local materialMode = params.materialMode or false
  local enableTint = params.enableTint or false
  
  -- Isometric colors (matching VoxelMaker behavior)
  local isoColors = {
    top = params.topColor or {r=255, g=255, b=255},
    left = params.leftColor or {r=235, g=235, b=235},
    right = params.rightColor or {r=210, g=210, b=210}
  }
  
  -- Legacy compatibility: convert brightness values to colors if provided
  if params.topBrightness then
    local b = params.topBrightness
    isoColors.top = {r=b, g=b, b=b}
  end
  if params.leftBrightness then
    local b = params.leftBrightness
    isoColors.left = {r=b, g=b, b=b}
  end
  if params.rightBrightness then
    local b = params.rightBrightness
    isoColors.right = {r=b, g=b, b=b}
  end
  
  -- Select isometric faces based on rotation
  local isoMapping = selectIsoFaces(shaderData.faces or {}, 0.01)
  
  -- Build reverse mapping: physical face -> iso role
  local faceToRole = {}
  if isoMapping.top then
    faceToRole[isoMapping.top] = "top"
    -- In alpha mode, opposite face also uses top color
    local opposite = {top="bottom", bottom="top"}
    if opposite[isoMapping.top] then
      faceToRole[opposite[isoMapping.top]] = "top"
    end
  end
  if isoMapping.left then
    faceToRole[isoMapping.left] = "left"
  end
  if isoMapping.right then
    faceToRole[isoMapping.right] = "right"
  end
  
  -- Process each face
  for i, face in ipairs(shaderData.faces or {}) do
    if face.face and face.color then
      -- Material mode check: skip pure colors
      if materialMode then
        if isPureColor(face.color.r, face.color.g, face.color.b) then
          goto continue  -- Skip this face
        end
      end
      
      -- Determine isometric role for this face
      local role = faceToRole[face.face]
      if not role then
        goto continue  -- Face not part of isometric selection
      end
      
      local isoColor = isoColors[role] or {r=255, g=255, b=255}
      
      if shadingMode == "alpha" then
        -- Alpha mode: use color alpha channel as brightness
        local brightness = (isoColor.a or 255) / 255
        
        if enableTint then
          -- Apply color as tint
          local tintR = (isoColor.r or 255) / 255
          local tintG = (isoColor.g or 255) / 255
          local tintB = (isoColor.b or 255) / 255
          
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
        -- Literal mode: replace RGB with iso color
        face.color.r = isoColor.r or 255
        face.color.g = isoColor.g or 255
        face.color.b = isoColor.b or 255
      end
      
      -- Alpha unchanged
      
      ::continue::
    end
  end
  
  return shaderData
end

return iso
