-- mesh_pipeline.lua
-- Flat-shaded mesh rendering pipeline (no per-pixel lighting)
-- Ported from AseVoxel mesh-model branch

local meshPipeline = {}

--------------------------------------------------------------------------------
-- Constants
--------------------------------------------------------------------------------
-- Unit cube vertices centered at voxel
local MESH_CUBE_VERTS = {
  {-0.5,-0.5,-0.5}, { 0.5,-0.5,-0.5}, { 0.5, 0.5,-0.5}, {-0.5, 0.5,-0.5}, -- back
  {-0.5,-0.5, 0.5}, { 0.5,-0.5, 0.5}, { 0.5, 0.5, 0.5}, {-0.5, 0.5, 0.5}, -- front
}

-- Face quads (indices into cube verts)
local MESH_FACES = {
  back   = {4,3,2,1}, -- z = -0.5
  front  = {5,6,7,8}, -- z = +0.5
  right  = {2,3,7,6}, -- +X
  left   = {1,5,8,4}, -- -X
  top    = {4,8,7,3}, -- +Y
  bottom = {1,2,6,5}, -- -Y
}

-- Neighbor offsets used to cull interior faces
local MESH_NEIGHBORS = {
  front  = {dx= 0, dy= 0, dz= 1},
  back   = {dx= 0, dy= 0, dz=-1},
  right  = {dx= 1, dy= 0, dz= 0},
  left   = {dx=-1, dy= 0, dz= 0},
  top    = {dx= 0, dy= 1, dz= 0},
  bottom = {dx= 0, dy=-1, dz= 0},
}

--------------------------------------------------------------------------------
-- Mesh Building
--------------------------------------------------------------------------------
local function occKey(x,y,z)
  return tostring(x) .. "," .. tostring(y) .. "," .. tostring(z)
end

-- Build unshared-vertex triangle mesh with interior faces culled
-- Returns: { vertices = { {x,y,z}, ... }, triangles = { {i1,i2,i3, color={r,g,b,a}}, ... }, bounds={...} }
function meshPipeline.build(voxels)
  local mesh = { vertices = {}, triangles = {}, bounds = nil }
  if not voxels or #voxels == 0 then return mesh end
  
  -- Build occupancy map and compute bounds
  local occ = {}
  local minX, maxX = math.huge, -math.huge
  local minY, maxY = math.huge, -math.huge
  local minZ, maxZ = math.huge, -math.huge
  
  for _, v in ipairs(voxels) do
    occ[occKey(v.x, v.y, v.z)] = true
    if v.x < minX then minX = v.x end
    if v.x > maxX then maxX = v.x end
    if v.y < minY then minY = v.y end
    if v.y > maxY then maxY = v.y end
    if v.z < minZ then minZ = v.z end
    if v.z > maxZ then maxZ = v.z end
  end
  
  mesh.bounds = { minX=minX, maxX=maxX, minY=minY, maxY=maxY, minZ=minZ, maxZ=maxZ }

  local verts = mesh.vertices
  local tris  = mesh.triangles
  local vcount = 0

  local function emitFace(vx, vy, vz, faceName, color)
    local q = MESH_FACES[faceName]
    if not q then return end
    
    local baseIndex = vcount
    -- Add all 8 vertices of the cube (even though we only use 4 for this face)
    for i=1,8 do
      local cv = MESH_CUBE_VERTS[i]
      verts[#verts+1] = { vx + cv[1], vy + cv[2], vz + cv[3] }
    end
    vcount = vcount + 8
    
    -- Create two triangles for the quad face
    local a = baseIndex + q[1]
    local b = baseIndex + q[2]
    local c = baseIndex + q[3]
    local d = baseIndex + q[4]
    local col = { 
      r=color.r or color.red or 255, 
      g=color.g or color.green or 255, 
      b=color.b or color.blue or 255, 
      a=color.a or color.alpha or 255 
    }
    tris[#tris+1] = { a, b, c, color = col }
    tris[#tris+1] = { a, c, d, color = col }
  end

  -- Emit only exterior faces
  for _, v in ipairs(voxels) do
    for fname, off in pairs(MESH_NEIGHBORS) do
      local nx, ny, nz = v.x + off.dx, v.y + off.dy, v.z + off.dz
      if not occ[occKey(nx, ny, nz)] then
        emitFace(v.x, v.y, v.z, fname, v.color or {r=255,g=255,b=255,a=255})
      end
    end
  end
  
  return mesh
end

--------------------------------------------------------------------------------
-- Triangle Rasterization
--------------------------------------------------------------------------------
-- Minimal flat triangle rasterizer (scanline fill using half-open rule on Y)
local function drawTriangle(image, p0, p1, p2, color)
  -- Sort vertices by Y
  if p1.y < p0.y then p0, p1 = p1, p0 end
  if p2.y < p0.y then p0, p2 = p2, p0 end
  if p2.y < p1.y then p1, p2 = p2, p1 end
  
  local function edgeX(y, a, b)
    if a.y == b.y then return nil end
    if y < a.y or y >= b.y then return nil end
    local t = (y - a.y) / (b.y - a.y)
    return a.x + (b.x - a.x) * t
  end
  
  local y0 = math.max(0, math.floor(p0.y))
  local y2 = math.min(image.height-1, math.ceil(p2.y))
  
  for y = y0, y2 do
    local scan = y + 0.5
    local xs = {}
    local x01 = edgeX(scan, p0, p1); if x01 then xs[#xs+1] = x01 end
    local x12 = edgeX(scan, p1, p2); if x12 then xs[#xs+1] = x12 end
    local x02 = edgeX(scan, p0, p2); if x02 then xs[#xs+1] = x02 end
    
    if #xs >= 2 then
      table.sort(xs)
      for k = 1, #xs, 2 do
        local xa = xs[k]
        local xb = xs[k+1] or xa
        if xb < xa then xa,xb = xb,xa end
        local ix0 = math.max(0, math.floor(xa + 0.5))
        local ix1 = math.min(image.width-1, math.floor(xb - 0.5))
        if ix1 < ix0 and (math.abs(xb - xa) < 1.0) then ix1 = ix0 end
        for x = ix0, ix1 do 
          image:putPixel(x, y, color) 
        end
      end
    end
  end
end

--------------------------------------------------------------------------------
-- Camera & Projection Helpers
--------------------------------------------------------------------------------
local function rotationComponents(xDeg, yDeg, zDeg)
  local xr, yr, zr = math.rad(xDeg or 0), math.rad(yDeg or 0), math.rad(zDeg or 0)
  local cx, sx = math.cos(xr), math.sin(xr)
  local cy, sy = math.cos(yr), math.sin(yr)
  local cz, sz = math.cos(zr), math.sin(zr)
  return cx,sx, cy,sy, cz,sz
end

local function computeBounds(verts)
  local minX, maxX = math.huge, -math.huge
  local minY, maxY = math.huge, -math.huge
  local minZ, maxZ = math.huge, -math.huge
  for _, v in ipairs(verts) do
    if v[1] < minX then minX = v[1] end
    if v[1] > maxX then maxX = v[1] end
    if v[2] < minY then minY = v[2] end
    if v[2] > maxY then maxY = v[2] end
    if v[3] < minZ then minZ = v[3] end
    if v[3] > maxZ then maxZ = v[3] end
  end
  return {minX=minX,maxX=maxX,minY=minY,maxY=maxY,minZ=minZ,maxZ=maxZ}
end

local function midAndSize(verts)
  local b = computeBounds(verts)
  return {
    x = (b.minX + b.maxX)/2,
    y = (b.minY + b.maxY)/2,
    z = (b.minZ + b.maxZ)/2,
    sizeX = b.maxX - b.minX + 1,
    sizeY = b.maxY - b.minY + 1,
    sizeZ = b.maxZ - b.minZ + 1,
    _bounds = b
  }
end

--------------------------------------------------------------------------------
-- Main Mesh Renderer
--------------------------------------------------------------------------------
-- Flat mesh renderer (no lighting), matches previewRenderer camera semantics
function meshPipeline.render(mesh, params)
  local width  = params.width or 200
  local height = params.height or 200
  local img = Image(width, height, ColorMode.RGB)
  
  if params.backgroundColor then 
    img:clear(params.backgroundColor) 
  else 
    img:clear(Color(0,0,0,0)) 
  end
  
  if not mesh or not mesh.vertices or not mesh.triangles or #mesh.triangles == 0 then
    return img
  end
  
  local centerX, centerY = width/2, height/2
  local xRot = params.xRotation or 0
  local yRot = params.yRotation or 0
  local zRot = params.zRotation or 0
  local cx,sx, cy,sy, cz,sz = rotationComponents(xRot, yRot, zRot)
  local mp = midAndSize(mesh.vertices)
  local maxDimension = math.max(mp.sizeX, mp.sizeY, mp.sizeZ)

  local orthogonal = params.orthogonal and true or false
  local fovDeg = params.fovDegrees
  local cameraDistance, focalLength, cameraPos, voxelSize
  local maxAllowed = math.min(width, height) * 0.9
  local baseTargetPix = params.scale or params.scaleLevel or 1.0
  if baseTargetPix <= 0 then baseTargetPix = 1 end
  
  if (not orthogonal) and fovDeg then
    fovDeg = math.max(5, math.min(75, fovDeg))
    local warpT = (fovDeg - 5) / (75 - 5)
    local amplified = warpT ^ (1/3)
    local BASE_NEAR  = 1.2
    local FAR_EXTRA  = 45.0
    cameraDistance = maxDimension * (BASE_NEAR + (1 - amplified)^2 * FAR_EXTRA)
    cameraPos = { x = mp.x, y = mp.y, z = mp.z + cameraDistance }
    focalLength = (height/2) / math.tan(math.rad(fovDeg)/2)
    
    local b = mp._bounds
    local corners = {
      {b.minX,b.minY,b.minZ},{b.maxX,b.minY,b.minZ},{b.minX,b.maxY,b.minZ},{b.maxX,b.maxY,b.minZ},
      {b.minX,b.minY,b.maxZ},{b.maxX,b.minY,b.maxZ},{b.minX,b.maxY,b.maxZ},{b.maxX,b.maxY,b.maxZ}
    }
    
    local function rz(x,y,z)
      local rx,ry,rz = x-mp.x, y-mp.y, z-mp.z
      local y2 = ry*cx - rz*sx; local z2 = ry*sx + rz*cx; ry,rz = y2,z2
      local x2 = rx*cy + rz*sy; local z3 = -rx*sy + rz*cy; rx,rz = x2,z3
      return mp.z + rz
    end
    
    local zMin, zMax = math.huge, -math.huge
    for _,c in ipairs(corners) do
      local zW = rz(c[1],c[2],c[3])
      if zW < zMin then zMin = zW end
      if zW > zMax then zMax = zW end
    end
    
    local depthBack  = math.max(0.001, cameraPos.z - zMin)
    local depthFront = math.max(0.001, cameraPos.z - zMax)
    local depthMiddle= math.max(0.001, cameraDistance)
    local ref = params.perspectiveScaleRef or "middle"
    local depthRef = (ref=="front" or ref=="Front") and depthFront 
                     or ((ref=="back" or ref=="Back") and depthBack or depthMiddle)
    voxelSize = baseTargetPix * (depthRef / focalLength)
    if voxelSize * maxDimension > maxAllowed then 
      voxelSize = maxAllowed / maxDimension 
    end
  else
    cameraDistance = maxDimension * 5
    cameraPos = { x = mp.x, y = mp.y, z = mp.z + cameraDistance }
    voxelSize = math.max(1, baseTargetPix)
    if voxelSize * maxDimension > maxAllowed then 
      voxelSize = maxAllowed / maxDimension 
    end
  end
  
  -- Project vertices once
  local proj = {}
  for i, v in ipairs(mesh.vertices) do
    local x = v[1] - mp.x
    local y = v[2] - mp.y
    local z = v[3] - mp.z
    
    -- Apply rotation (X, then Y, then Z)
    local y2 = y*cx - z*sx; local z2 = y*sx + z*cx; y,z = y2,z2
    local x2 = x*cy + z*sy; local z3 = -x*sy + z*cy; x,z = x2,z3
    local x3 = x*cz - y*sz; local y3 = x*sz + y*cz; x,y = x3,y3
    
    local worldZ = mp.z + z
    local depth = cameraPos.z - worldZ
    local sxp,syp
    
    if (not orthogonal) and focalLength then
      local scale = focalLength / math.max(0.001, depth)
      sxp = centerX + (x * voxelSize) * scale
      syp = centerY + (y * voxelSize) * scale
    else
      sxp = centerX + x * voxelSize
      syp = centerY + y * voxelSize
    end
    
    proj[i] = { x = sxp, y = syp, depth = depth }
  end
  
  -- Build draw list with painter's sort (back to front)
  local drawList = {}
  for _, t in ipairs(mesh.triangles) do
    local p1 = proj[t[1]]
    local p2 = proj[t[2]]
    local p3 = proj[t[3]]
    if p1 and p2 and p3 then
      local avg = (p1.depth + p2.depth + p3.depth) / 3
      drawList[#drawList+1] = { p1=p1, p2=p2, p3=p3, depth=avg, color=t.color }
    end
  end
  
  table.sort(drawList, function(a,b) return a.depth > b.depth end)
  
  -- Rasterize triangles
  for _, it in ipairs(drawList) do
    local c = it.color or {r=255,g=255,b=255,a=255}
    drawTriangle(img, it.p1, it.p2, it.p3, Color(c.r or 255, c.g or 255, c.b or 255, c.a or 255))
  end
  
  return img
end

return meshPipeline
