-- fast_visibility.lua
-- Ultra-fast face visibility using precomputed camera-angle lookups
-- Key insight: At any camera angle, you can see AT MOST 3 faces of a cube!

local fastVisibility = {}

-- Face definitions
local FACES = {"front", "back", "left", "right", "top", "bottom"}

-- Face normal vectors in model space
local FACE_NORMALS = {
  front  = { x=0,  y=0,  z=1  },
  back   = { x=0,  y=0,  z=-1 },
  right  = { x=1,  y=0,  z=0  },
  left   = { x=-1, y=0,  z=0  },
  top    = { x=0,  y=1,  z=0  },
  bottom = { x=0,  y=-1, z=0  }
}

-- Cache for rotated normals (recalculated only when rotation changes)
local cachedRotation = { xRot = nil, yRot = nil, zRot = nil }
local cachedNormals = nil
local cachedVisibleFaces = nil
local cachedFaceOrder = nil -- depth order: back to front

--------------------------------------------------------------------------------
-- Rotate a normal vector by Euler angles (X, Y, Z order)
--------------------------------------------------------------------------------
local function rotateNormal(nx, ny, nz, cx, sx, cy, sy, cz, sz)
  -- X rotation
  local y2 = ny * cx - nz * sx
  local z2 = ny * sx + nz * cx
  -- Y rotation  
  local x3 = nx * cy + z2 * sy
  local z3 = -nx * sy + z2 * cy
  -- Z rotation
  local x4 = x3 * cz - y2 * sz
  local y4 = x3 * sz + y2 * cz
  
  return x4, y4, z3
end

--------------------------------------------------------------------------------
-- Precompute visible faces from camera angle (called once per rotation change)
--------------------------------------------------------------------------------
function fastVisibility.updateRotation(xRot, yRot, zRot, orthogonal)
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
    if mod and mod.precompute_visible_faces then
      local ok, result = pcall(mod.precompute_visible_faces, xRot, yRot, zRot, orthogonal)
      if ok and result then
        cachedVisibleFaces = result.visibleFaces
        cachedFaceOrder = result.faceOrder
        
        -- Also get rotated normals for lighting
        if mod.precompute_rotated_normals then
          local ok2, normals = pcall(mod.precompute_rotated_normals, xRot, yRot, zRot)
          if ok2 and normals then
            cachedNormals = normals
          end
        end
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
  
  -- Camera view direction (looking down -Z in camera space after rotation)
  local viewX, viewY, viewZ
  if orthogonal then
    -- Orthographic: view direction is always (0, 0, -1) in camera space
    viewX, viewY, viewZ = 0, 0, 1
  else
    -- Perspective: same for our purposes (camera at origin looking down -Z)
    viewX, viewY, viewZ = 0, 0, 1
  end
  
  -- Rotate all 6 face normals and check visibility
  cachedNormals = {}
  cachedVisibleFaces = {}
  local visibleList = {}
  local faceDepths = {}
  
  for faceName, n in pairs(FACE_NORMALS) do
    local nx, ny, nz = rotateNormal(n.x, n.y, n.z, cx, sx, cy, sy, cz, sz)
    cachedNormals[faceName] = { x = nx, y = ny, z = nz }
    
    -- Dot product with view direction
    local dot = nx * viewX + ny * viewY + nz * viewZ
    
    -- Face is visible if normal points toward camera (dot > 0)
    local isVisible = (dot > 0.01) -- Small threshold for numerical stability
    cachedVisibleFaces[faceName] = isVisible
    
    if isVisible then
      table.insert(visibleList, faceName)
      -- Depth for sorting: larger dot = more facing camera = should draw later
      faceDepths[faceName] = dot
    end
  end
  
  -- Sort visible faces by depth (back to front for painter's algorithm)
  table.sort(visibleList, function(a, b)
    return faceDepths[a] < faceDepths[b]
  end)
  
  cachedFaceOrder = visibleList
end

--------------------------------------------------------------------------------
-- Get precomputed visible faces (much faster than per-voxel calculation!)
--------------------------------------------------------------------------------
function fastVisibility.getVisibleFaces()
  if not cachedVisibleFaces then
    return {front=false, back=false, left=false, right=false, top=false, bottom=false}
  end
  
  -- Return a copy to avoid mutation
  return {
    front  = cachedVisibleFaces.front or false,
    back   = cachedVisibleFaces.back or false,
    left   = cachedVisibleFaces.left or false,
    right  = cachedVisibleFaces.right or false,
    top    = cachedVisibleFaces.top or false,
    bottom = cachedVisibleFaces.bottom or false
  }
end

--------------------------------------------------------------------------------
-- Get visible faces as a list (for iteration)
--------------------------------------------------------------------------------
function fastVisibility.getVisibleFaceList()
  return cachedFaceOrder or {}
end

--------------------------------------------------------------------------------
-- Get rotated normals for lighting calculations
--------------------------------------------------------------------------------
function fastVisibility.getRotatedNormals()
  return cachedNormals or {}
end

--------------------------------------------------------------------------------
-- Get face count (how many faces are visible)
--------------------------------------------------------------------------------
function fastVisibility.getVisibleFaceCount()
  return cachedFaceOrder and #cachedFaceOrder or 0
end

--------------------------------------------------------------------------------
-- Apply adjacency culling to visible faces (per voxel, but only for visible faces)
--------------------------------------------------------------------------------
function fastVisibility.applyAdjacencyCulling(visibleFaces, hiddenFaces)
  local result = {}
  for faceName, visible in pairs(visibleFaces) do
    result[faceName] = visible and not hiddenFaces[faceName]
  end
  return result
end

return fastVisibility
