-- vertex_cache.lua
-- Precompute rotated cube vertices once per frame instead of per voxel!
-- Key insight: For a voxel grid, all voxels use the SAME rotated unit cube vertices

local vertexCache = {}

-- Unit cube vertices (8 corners)
local UNIT_CUBE_VERTICES = {
  {0, 0, 0}, {1, 0, 0}, {1, 1, 0}, {0, 1, 0}, -- Front face
  {0, 0, 1}, {1, 0, 1}, {1, 1, 1}, {0, 1, 1}  -- Back face
}

-- Cached data
local cachedRotation = { xRot = nil, yRot = nil, zRot = nil }
local rotatedUnitVertices = nil

--------------------------------------------------------------------------------
-- Rotate a point by Euler angles (X, Y, Z order)
--------------------------------------------------------------------------------
local function rotatePoint(x, y, z, cx, sx, cy, sy, cz, sz)
  -- X rotation
  local y2 = y * cx - z * sx
  local z2 = y * sx + z * cx
  -- Y rotation
  local x3 = x * cy + z2 * sy
  local z3 = -x * sy + z2 * cy
  -- Z rotation
  local x4 = x3 * cz - y2 * sz
  local y4 = x3 * sz + y2 * cz
  
  return x4, y4, z3
end

--------------------------------------------------------------------------------
-- Precompute rotated unit cube vertices (called once per rotation change)
--------------------------------------------------------------------------------
function vertexCache.updateRotation(xRot, yRot, zRot)
  -- Check if rotation changed
  if cachedRotation.xRot == xRot 
     and cachedRotation.yRot == yRot 
     and cachedRotation.zRot == zRot then
    return -- Already cached
  end
  
  -- Update cache
  cachedRotation.xRot = xRot
  cachedRotation.yRot = yRot
  cachedRotation.zRot = zRot
  
  -- Try native accelerated path first
  local nativeBridge = AseVoxel and AseVoxel.nativeBridge
  if nativeBridge and nativeBridge.isAvailable and nativeBridge.isAvailable() then
    local mod = nativeBridge._mod
    if mod and mod.precompute_unit_cube_vertices then
      local ok, vertices = pcall(mod.precompute_unit_cube_vertices, xRot, yRot, zRot)
      if ok and vertices then
        rotatedUnitVertices = vertices
        return
      end
    end
  end
  
  -- Fallback: Lua implementation
  -- Precompute trig functions
  local xRad = math.rad(xRot)
  local yRad = math.rad(yRot)
  local zRad = math.rad(zRot)
  local cx, sx = math.cos(xRad), math.sin(xRad)
  local cy, sy = math.cos(yRad), math.sin(yRad)
  local cz, sz = math.cos(zRad), math.sin(zRad)
  
  -- Rotate all 8 unit cube vertices
  rotatedUnitVertices = {}
  for i, v in ipairs(UNIT_CUBE_VERTICES) do
    local rx, ry, rz = rotatePoint(v[1], v[2], v[3], cx, sx, cy, sy, cz, sz)
    rotatedUnitVertices[i] = { x = rx, y = ry, z = rz }
  end
end

--------------------------------------------------------------------------------
-- Get rotated vertices for a specific voxel (just scale and translate!)
--------------------------------------------------------------------------------
function vertexCache.getVoxelVertices(voxelX, voxelY, voxelZ, voxelSize, middlePoint)
  if not rotatedUnitVertices then
    return nil
  end
  
  local vertices = {}
  local offsetX = (voxelX - middlePoint.x) * voxelSize
  local offsetY = (voxelY - middlePoint.y) * voxelSize
  local offsetZ = (voxelZ - middlePoint.z) * voxelSize
  
  for i, rv in ipairs(rotatedUnitVertices) do
    vertices[i] = {
      x = rv.x * voxelSize + offsetX,
      y = rv.y * voxelSize + offsetY,
      z = rv.z * voxelSize + offsetZ
    }
  end
  
  return vertices
end

--------------------------------------------------------------------------------
-- Get rotated unit vertices (for custom processing)
--------------------------------------------------------------------------------
function vertexCache.getRotatedUnitVertices()
  return rotatedUnitVertices
end

return vertexCache
