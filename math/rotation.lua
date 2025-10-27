-- rotation.lua
-- Handles all rotation operations for 3D model visualization
-- Dependencies: Loaded via AseVoxel.mathUtils namespace

local rotation = {}

-- Access mathUtils through global namespace (loaded by loader.lua)
local function getMathUtils()
  return AseVoxel.mathUtils
end

-- Try to load native bridge (optional)
local function getNativeBridge()
  if AseVoxel and AseVoxel.render and AseVoxel.render.native_bridge then
    return AseVoxel.render.native_bridge
  end
  return nil
end

-- Helper function to wrap an angle into [-180, +180] degree range
-- Used to find the smallest rotation path between two angles
function rotation.wrapAngle(angle)
  local wrapped = angle % 360
  if wrapped > 180 then 
    wrapped = wrapped - 360
  end
  return wrapped
end

-- Apply an absolute (model-space) rotation
-- This properly rotates around the model's own axes (X, Y, Z)
-- Parameters:
--   currentMatrix: The current rotation matrix
--   deltaX, deltaY, deltaZ: The delta rotations in degrees
-- Returns:
--   newMatrix: The updated rotation matrix
function rotation.applyAbsoluteRotation(currentMatrix, deltaX, deltaY, deltaZ)
  local mathUtils = getMathUtils()
  
  -- Create delta rotation matrix (model-space rotation)
  local deltaMatrix = mathUtils.createRotationMatrix(deltaX, deltaY, deltaZ)
  
  -- POST-multiply for model-space rotation (matrix * delta)
  -- This applies the rotation in the model's local coordinate system
  local newMatrix = mathUtils.multiplyMatrices(currentMatrix, deltaMatrix)
  
  -- Return the new matrix (Euler angles are extracted in the calling code)
  return newMatrix
end

-- Apply a relative (camera-space) rotation
-- This rotates relative to the current view (pitch/yaw/roll)
-- Parameters:
--   currentMatrix: The current rotation matrix
--   pitchDelta, yawDelta, rollDelta: The delta rotations in degrees
-- Returns:
--   newMatrix: The updated rotation matrix
function rotation.applyRelativeRotation(currentMatrix, pitchDelta, yawDelta, rollDelta)
  local mathUtils = getMathUtils()
  
  -- Create camera-space rotation matrices for each axis
  local pitchRad = math.rad(pitchDelta)
  local yawRad = math.rad(yawDelta)
  local rollRad = math.rad(rollDelta)
  
  -- Pitch: rotation around camera's right axis (X in view space)
  local pitchMatrix = {
    {1, 0, 0},
    {0, math.cos(pitchRad), -math.sin(pitchRad)},
    {0, math.sin(pitchRad), math.cos(pitchRad)}
  }
  
  -- Yaw: rotation around camera's up axis (Y in view space)
  local yawMatrix = {
    {math.cos(yawRad), 0, math.sin(yawRad)},
    {0, 1, 0},
    {-math.sin(yawRad), 0, math.cos(yawRad)}
  }
  
  -- Roll: rotation around camera's forward axis (Z in view space)
  local rollMatrix = {
    {math.cos(rollRad), -math.sin(rollRad), 0},
    {math.sin(rollRad), math.cos(rollRad), 0},
    {0, 0, 1}
  }
  
  -- Combine in "Yaw → Pitch → Roll" order, which is most intuitive
  local temp = mathUtils.multiplyMatrices(pitchMatrix, yawMatrix)
  local cameraMatrix = mathUtils.multiplyMatrices(rollMatrix, temp)
  
  -- Apply camera rotation: C * Mcurrent
  local newMatrix = mathUtils.multiplyMatrices(cameraMatrix, currentMatrix)
  
  -- Return the new matrix (Euler angles are extracted in the calling code)
  return newMatrix
end

--------------------------------------------------------------------------------
-- Transform a voxel using rotation parameters
-- @param voxel The voxel to transform
-- @param params Transformation parameters
-- @return Transformed voxel
--------------------------------------------------------------------------------
function rotation.transformVoxel(voxel, params)
  local nativeBridge = getNativeBridge()
  
  -- Native fast-path (if available)
  if nativeBridge and nativeBridge.isAvailable
     and nativeBridge.isAvailable()
     and nativeBridge.transformVoxel then
    local transformed, err = nativeBridge.transformVoxel(voxel, params)
    if transformed and transformed.x then
      return transformed
    end
    -- fall through if native failed
  end
  
  -- Apply rotations to voxel coordinates
  local transformed = {
    x = voxel.x - params.middlePoint.x,
    y = voxel.y - params.middlePoint.y,
    z = voxel.z - params.middlePoint.z,
    color = voxel.color
  }
  
  -- Apply rotation using XYZ rotation order
  local xRad = math.rad(params.xRotation)
  local yRad = math.rad(params.yRotation)
  local zRad = math.rad(params.zRotation)
  
  -- Calculate rotation matrix components
  local cx, sx = math.cos(xRad), math.sin(xRad)
  local cy, sy = math.cos(yRad), math.sin(yRad)
  local cz, sz = math.cos(zRad), math.sin(zRad)
  
  -- Apply rotations (X, Y, Z order)
  local x, y, z = transformed.x, transformed.y, transformed.z
  
  -- Rotate around X axis
  local y2 = y * cx - z * sx
  local z2 = y * sx + z * cx
  y, z = y2, z2
  
  -- Rotate around Y axis
  local x2 = x * cy + z * sy
  local z3 = -x * sy + z * cy
  x, z = x2, z3
  
  -- Rotate around Z axis
  local x3 = x * cz - y * sz
  local y3 = x * sz + y * cz
  x, y = x3, y3
  
  -- IMPROVED: Set the transformed coordinates with proper rounding
  -- This prevents fractional offsets that can lead to rendering issues
  transformed.x = x + params.middlePoint.x
  transformed.y = y + params.middlePoint.y
  transformed.z = z + params.middlePoint.z
  
  -- Add normal vector information for improved face visibility calculation
  transformed.normal = {
    x = 0, y = 0, z = 0  -- Will be set by calculateFaceVisibility if needed
  }
  
  return transformed
end

--------------------------------------------------------------------------------
-- Optimize voxel model by identifying hidden faces for culling
-- @param voxels Array of voxels to optimize
-- @return Optimized voxel model with hidden face information
--------------------------------------------------------------------------------
function rotation.optimizeVoxelModel(voxels)
  -- Create a map of voxel positions for quick lookup
  local voxelMap = {}
  for _, voxel in ipairs(voxels) do
    local key = voxel.x .. "," .. voxel.y .. "," .. voxel.z
    voxelMap[key] = true
  end
  
  -- Create optimized model with hidden face information
  local optimized = {}
  
  for _, voxel in ipairs(voxels) do
    -- Check all six neighbors to determine which faces are hidden
    -- A face is hidden if there's a neighboring voxel on that face
    local hiddenFaces = {
      front = voxelMap[(voxel.x) .. "," .. (voxel.y) .. "," .. (voxel.z + 1)] or false,
      back = voxelMap[(voxel.x) .. "," .. (voxel.y) .. "," .. (voxel.z - 1)] or false,
      right = voxelMap[(voxel.x + 1) .. "," .. (voxel.y) .. "," .. (voxel.z)] or false,
      left = voxelMap[(voxel.x - 1) .. "," .. (voxel.y) .. "," .. (voxel.z)] or false,
      top = voxelMap[(voxel.x) .. "," .. (voxel.y + 1) .. "," .. (voxel.z)] or false,
      bottom = voxelMap[(voxel.x) .. "," .. (voxel.y - 1) .. "," .. (voxel.z)] or false
    }
    
    -- Add to optimized model
    table.insert(optimized, {
      voxel = voxel,
      hiddenFaces = hiddenFaces
    })
  end
  
  return optimized
end

return rotation
