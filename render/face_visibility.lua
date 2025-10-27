-- face_visibility.lua
-- Face culling logic for voxel rendering

local faceVisibility = {}

-- Face normal vectors
local FACE_NORMALS = {
  front  = {0,0, 1},
  back   = {0,0,-1},
  right  = {1,0, 0},
  left   = {-1,0,0},
  top    = {0,1, 0},
  bottom = {0,-1,0}
}

-- Lazy loader for native bridge
local function getNativeBridge()
  return AseVoxel.nativeBridge
end

-- Export face normals for use by other modules
faceVisibility.FACE_NORMALS = FACE_NORMALS

--------------------------------------------------------------------------------
-- Calculate which faces of a voxel are visible from camera
--------------------------------------------------------------------------------
function faceVisibility.calculateFaceVisibility(voxel, cameraPos, orthogonal, rotationParams)
  -- Native accelerated path if available
  local nativeBridge = getNativeBridge()
  local nativeBridge_ok = (nativeBridge ~= nil)
  
  if nativeBridge_ok and nativeBridge.isAvailable
     and nativeBridge.isAvailable()
     and nativeBridge.calculateFaceVisibility then
    local vis, err = nativeBridge.calculateFaceVisibility(voxel, cameraPos, orthogonal, rotationParams)
    if type(vis) == "table" and vis.front ~= nil then
      return vis
    end
    -- silent fallback on failure
  end

  local vis = {front=false,back=false,right=false,left=false,top=false,bottom=false}

  local xRad = math.rad(rotationParams.xRotation or 0)
  local yRad = math.rad(rotationParams.yRotation or 0)
  local zRad = math.rad(rotationParams.zRotation or 0)
  local cx, sx = math.cos(xRad), math.sin(xRad)
  local cy, sy = math.cos(yRad), math.sin(yRad)
  local cz, sz = math.cos(zRad), math.sin(zRad)

  local vcx = math.floor(voxel.x + 0.5)
  local vcy = math.floor(voxel.y + 0.5)
  local vcz = math.floor(voxel.z + 0.5)
  local viewVec = {
    x = cameraPos.x - vcx,
    y = cameraPos.y - vcy,
    z = cameraPos.z - vcz
  }
  local mag = math.sqrt(viewVec.x*viewVec.x + viewVec.y*viewVec.y + viewVec.z*viewVec.z)
  if mag > 0.0001 then
    viewVec.x, viewVec.y, viewVec.z = viewVec.x/mag, viewVec.y/mag, viewVec.z/mag
  end

  for name, n in pairs(FACE_NORMALS) do
    local x,y,z = n[1], n[2], n[3]
    -- X rotation
    local y2 = y*cx - z*sx
    local z2 = y*sx + z*cx
    y,z = y2,z2
    -- Y rotation
    local x2 = x*cy + z*sy
    local z3 = -x*sy + z*cy
    x,z = x2,z3
    -- Z rotation
    local x3 = x*cz - y*sz
    local y3 = x*sz + y*cz
    local dot = x3*viewVec.x + y3*viewVec.y + z3*viewVec.z
    local threshold = 0.01
    if rotationParams.voxelSize and rotationParams.voxelSize > 1 then
      threshold = 0.01 / math.min(3, rotationParams.voxelSize)
    end
    vis[name] = (dot > threshold)
  end
  return vis
end

return faceVisibility
