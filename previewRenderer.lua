-- previewRenderer.lua (Consolidated & Cleaned) 
-- NOTE:
--   - Remote renderer path currently ignores FX Stack (apply locally only).
--   - Callers should pass:
--       params.fxStack  (data stack: { modules = { ... } })
--       params.shadingMode = "Stack" | "Simple" | "Complete"
--   - We internally use fxStackModule (the module) to call shadeFace().
--   - If you add persistence for fxStack, just store params.fxStack.

local rotation       = require("rotation")
local mathUtils      = require("mathUtils")
local fxStackModule  = require("fxStack")
-- Optional native bridge (first feature: transform + face visibility)
nativeBridge_ok, nativeBridge = pcall(require, "nativeBridge")
-- REMOVE eager require to avoid automatic websocket prompt
-- local remoteRenderer = nil
-- local ok_remote, rr = pcall(require, "remoteRenderer")
-- if ok_remote then remoteRenderer = rr end
-- if remoteRenderer and remoteRenderer.enable then
--   pcall(function() remoteRenderer.enable(false) end)
-- end

-- Lazy remote renderer loader (only loads when actually used)
local remoteRenderer = nil
local function _getRemote()
  if remoteRenderer ~= nil then return remoteRenderer end
  local ok, rr = pcall(require, "remoteRenderer")
  if ok and rr then
    remoteRenderer = rr
    -- Do NOT auto-enable; user must toggle UI checkbox
  end
  return remoteRenderer
end

--------------------------------------------------------------------------------
-- Mesh pipeline (flat, unshaded) ported from AseVoxel mesh-model branch
-- Embedded here (no separate files) to avoid additional module plumbing.
--------------------------------------------------------------------------------
-- Unit cube vertices centered at voxel
local _MESH_CUBE_VERTS = {
  {-0.5,-0.5,-0.5}, { 0.5,-0.5,-0.5}, { 0.5, 0.5,-0.5}, {-0.5, 0.5,-0.5}, -- back
  {-0.5,-0.5, 0.5}, { 0.5,-0.5, 0.5}, { 0.5, 0.5, 0.5}, {-0.5, 0.5, 0.5}, -- front
}
-- Face quads (indices into cube verts)
local _MESH_FACES = {
  back   = {4,3,2,1}, -- z = -0.5
  front  = {5,6,7,8}, -- z = +0.5
  right  = {2,3,7,6}, -- +X
  left   = {1,5,8,4}, -- -X
  top    = {4,8,7,3}, -- +Y
  bottom = {1,2,6,5}, -- -Y
}
-- Neighbor offsets used to cull interior faces
local _MESH_NEIGHBORS = {
  front  = {dx= 0, dy= 0, dz= 1},
  back   = {dx= 0, dy= 0, dz=-1},
  right  = {dx= 1, dy= 0, dz= 0},
  left   = {dx=-1, dy= 0, dz= 0},
  top    = {dx= 0, dy= 1, dz= 0},
  bottom = {dx= 0, dy=-1, dz= 0},
}

local function _mesh_occ_key(x,y,z)
  return tostring(x) .. "," .. tostring(y) .. "," .. tostring(z)
end

-- Build unshared-vertex triangle mesh with interior faces culled
-- returns { vertices = { {x,y,z}, ... }, triangles = { {i1,i2,i3, color={r,g,b,a}}, ... }, bounds={...} }
local function _mesh_build(voxels)
  local mesh = { vertices = {}, triangles = {}, bounds = nil }
  if not voxels or #voxels == 0 then return mesh end
  -- occupancy
  local occ = {}
  local minX, maxX = math.huge, -math.huge
  local minY, maxY = math.huge, -math.huge
  local minZ, maxZ = math.huge, -math.huge
  for _, v in ipairs(voxels) do
    occ[_mesh_occ_key(v.x, v.y, v.z)] = true
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
    local q = _MESH_FACES[faceName]
    if not q then return end
    local baseIndex = vcount
    for i=1,8 do
      local cv = _MESH_CUBE_VERTS[i]
      verts[#verts+1] = { vx + cv[1], vy + cv[2], vz + cv[3] }
    end
    vcount = vcount + 8
    local a = baseIndex + q[1]
    local b = baseIndex + q[2]
    local c = baseIndex + q[3]
    local d = baseIndex + q[4]
    local col = { r=color.r or color.red or 255, g=color.g or color.green or 255, b=color.b or color.blue or 255, a=color.a or color.alpha or 255 }
    tris[#tris+1] = { a, b, c, color = col }
    tris[#tris+1] = { a, c, d, color = col }
  end

  for _, v in ipairs(voxels) do
    for fname, off in pairs(_MESH_NEIGHBORS) do
      local nx, ny, nz = v.x + off.dx, v.y + off.dy, v.z + off.dz
      if not occ[_mesh_occ_key(nx, ny, nz)] then
        emitFace(v.x, v.y, v.z, fname, v.color or {r=255,g=255,b=255,a=255})
      end
    end
  end
  return mesh
end

-- Minimal flat triangle rasterizer (scanline fill using half-open rule on Y)
local function _mesh_drawTriangle(image, p0, p1, p2, color)
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
        for x = ix0, ix1 do image:putPixel(x, y, color) end
      end
    end
  end
end

-- Flat mesh renderer (no lighting), matches previewRenderer camera semantics
local function _mesh_rotationComponents(xDeg, yDeg, zDeg)
  local xr, yr, zr = math.rad(xDeg or 0), math.rad(yDeg or 0), math.rad(zDeg or 0)
  local cx, sx = math.cos(xr), math.sin(xr)
  local cy, sy = math.cos(yr), math.sin(yr)
  local cz, sz = math.cos(zr), math.sin(zr)
  return cx,sx, cy,sy, cz,sz
end

local function _mesh_computeBounds(verts)
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

local function _mesh_midAndSize(verts)
  local b = _mesh_computeBounds(verts)
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

local function _mesh_render(mesh, params)
  local width  = params.width or 200
  local height = params.height or 200
  local img = Image(width, height, ColorMode.RGB)
  if params.backgroundColor then img:clear(params.backgroundColor) else img:clear(Color(0,0,0,0)) end
  if not mesh or not mesh.vertices or not mesh.triangles or #mesh.triangles == 0 then
    return img
  end
  local centerX, centerY = width/2, height/2
  local xRot = params.xRotation or 0
  local yRot = params.yRotation or 0
  local zRot = params.zRotation or 0
  local cx,sx, cy,sy, cz,sz = _mesh_rotationComponents(xRot, yRot, zRot)
  local mp = _mesh_midAndSize(mesh.vertices)
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
      -- zrot doesn't change depth magnitude
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
    local depthRef = (ref=="front" or ref=="Front") and depthFront or ((ref=="back" or ref=="Back") and depthBack or depthMiddle)
    voxelSize = baseTargetPix * (depthRef / focalLength)
    if voxelSize * maxDimension > maxAllowed then voxelSize = maxAllowed / maxDimension end
  else
    cameraDistance = maxDimension * 5
    cameraPos = { x = mp.x, y = mp.y, z = mp.z + cameraDistance }
    voxelSize = math.max(1, baseTargetPix)
    if voxelSize * maxDimension > maxAllowed then voxelSize = maxAllowed / maxDimension end
  end
  -- project vertices once
  local proj = {}
  for i, v in ipairs(mesh.vertices) do
    local x = v[1] - mp.x
    local y = v[2] - mp.y
    local z = v[3] - mp.z
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
  -- triangles (painter's sort)
  local drawList = {}
  for _, t in ipairs(mesh.triangles) do
    local p1 = proj[t[1]]; local p2 = proj[t[2]]; local p3 = proj[t[3]]
    if p1 and p2 and p3 then
      local avg = (p1.depth + p2.depth + p3.depth) / 3
      drawList[#drawList+1] = { p1=p1, p2=p2, p3=p3, depth=avg, color=t.color }
    end
  end
  table.sort(drawList, function(a,b) return a.depth > b.depth end)
  for _, it in ipairs(drawList) do
    local c = it.color or {r=255,g=255,b=255,a=255}
    _mesh_drawTriangle(img, it.p1, it.p2, it.p3, Color(c.r or 255, c.g or 255, c.b or 255, c.a or 255))
  end
  return img
end

--------------------------------------------------------------------------------
-- Utility: Quaternion helpers (for lighting normal rotation only)
--------------------------------------------------------------------------------
local function eulerToQuat(xDeg, yDeg, zDeg)
  local xr, yr, zr = math.rad(xDeg or 0), math.rad(yDeg or 0), math.rad(zDeg or 0)
  -- ZYX order (matches existing combination: Z * Y * X)
  local cz, sz = math.cos(zr*0.5), math.sin(zr*0.5)
  local cy, sy = math.cos(yr*0.5), math.sin(yr*0.5)
  local cx, sx = math.cos(xr*0.5), math.sin(xr*0.5)

  -- Quaternion multiplication q = qz * qy * qx
  local qw = cz*cy*cx + sz*sy*sx
  local qx = cz*cy*sx - sz*sy*cx
  local qy = cz*sy*cx + sz*cy*sx
  local qz = sz*cy*cx - cz*sy*sx
  return {w=qw,x=qx,y=qy,z=qz}
end

local function quatRotateVec(q, v)
  -- v' = q * (0,v) * q^-1
  local qw,qx,qy,qz = q.w, q.x, q.y, q.z
  local vx,vy,vz = v.x, v.y, v.z
  -- Compute cross products directly (optimized)
  local tx  = 2*(qy*vz - qz*vy)
  local ty  = 2*(qz*vx - qx*vz)
  local tz  = 2*(qx*vy - qy*vx)
  return {
    x = vx + qw*tx + (qy*tz - qz*ty),
    y = vy + qw*ty + (qz*tx - qx*tz),
    z = vz + qw*tz + (qx*ty - qy*tx)
  }
end

local function normalize(v)
  local l = math.sqrt(v.x*v.x + v.y*v.y + v.z*v.z)
  if l < 1e-6 then return {x=0,y=0,z=1} end
  return {x=v.x/l,y=v.y/l,z=v.z/l}
end

local previewRenderer = {}

-- Small helper to get milliseconds
local function _nowMs() return os.clock() * 1000 end

--------------------------------------------------------------------------------
-- Constants / Utility
--------------------------------------------------------------------------------
local UNIT_CUBE_VERTICES = {
  {-0.5,-0.5,-0.5}, { 0.5,-0.5,-0.5}, { 0.5, 0.5,-0.5}, {-0.5, 0.5,-0.5},
  {-0.5,-0.5, 0.5}, { 0.5,-0.5, 0.5}, { 0.5, 0.5, 0.5}, {-0.5, 0.5, 0.5},
}

local FACE_DEFS = {
  {indices = {5, 6, 7, 8}, name = "front"},
  {indices = {2, 1, 4, 3}, name = "back"},
  {indices = {6, 2, 3, 7}, name = "right"},
  {indices = {1, 5, 8, 4}, name = "left"},
  {indices = {8, 7, 3, 4}, name = "top"},
  {indices = {1, 2, 6, 5}, name = "bottom"}
}

local RAINBOW_COLORS = {
  front  = Color(255,255,255),
  back   = Color(255,255,0),
  right  = Color(255,0,0),
  left   = Color(255,100,0),
  top    = Color(0,255,0),
  bottom = Color(0,0,255),
}

--------------------------------------------------------------------------------
-- Layer Scroll Mode
--------------------------------------------------------------------------------
previewRenderer.layerScrollMode = {
  enabled = false,
  focusIndex = 1,
  behind = 0,
  front = 0,
  originalVisibility = nil,
  cache = {},
  layerList = {},
  spriteId = nil
}

local function _activeFrameNumber()
  return (app.activeFrame and app.activeFrame.frameNumber) or 1
end

local function _rebuildLayerList(sprite)
  local ls = {}
  for _, layer in ipairs(sprite.layers) do
    if not layer.isGroup then ls[#ls+1] = layer end
  end
  previewRenderer.layerScrollMode.layerList = ls
end

local function _cloneCelImage(cel)
  if not cel or not cel.image then return nil end
  local ok, clone = pcall(function() return cel.image:clone() end)
  return ok and clone or nil
end

local function _refreshCacheForRange(sprite, startIdx, endIdx, frame)
  local mode = previewRenderer.layerScrollMode
  for i = startIdx, endIdx do
    local layer = mode.layerList[i]
    local cel = layer and layer:cel(frame)
    local img = _cloneCelImage(cel)
    if img then
      mode.cache[i] = {
        image = img,
        pos = { x = cel.position.x, y = cel.position.y },
        layer = layer,
        frame = frame
      }
    end
  end
end

function previewRenderer.enableLayerScrollMode(enable, sprite, focusIndex)
  local mode = previewRenderer.layerScrollMode
  if enable == mode.enabled then return end
  if enable then
    if not sprite then return end
    _rebuildLayerList(sprite)
    if #mode.layerList == 0 then return end
    local idx = focusIndex
    if not idx and app.activeLayer then
      for i,l in ipairs(mode.layerList) do
        if l == app.activeLayer then idx = i break end
      end
    end
    idx = idx or 1
    idx = math.max(1, math.min(#mode.layerList, idx))
    mode.focusIndex = idx
    mode.originalVisibility = {}
    for _, l in ipairs(mode.layerList) do
      mode.originalVisibility[l] = l.isVisible
      l.isVisible = false
    end
    mode.layerList[idx].isVisible = true
    mode.spriteId = sprite
    mode.cache = {}
    mode.enabled = true
    _refreshCacheForRange(sprite, idx, idx, _activeFrameNumber())
  else
    if mode.originalVisibility then
      for layer, vis in pairs(mode.originalVisibility) do
        pcall(function() layer.isVisible = vis end)
      end
    end
    mode.enabled = false
    mode.originalVisibility = nil
    mode.cache = {}
    mode.layerList = {}
    mode.spriteId = nil
  end
end

function previewRenderer.setLayerScrollWindow(behind, front)
  local m = previewRenderer.layerScrollMode
  m.behind = math.max(0, tonumber(behind) or 0)
  m.front  = math.max(0, tonumber(front) or 0)
end

function previewRenderer.shiftLayerFocus(delta, sprite)
  local m = previewRenderer.layerScrollMode
  if not m.enabled then return end
  if sprite ~= m.spriteId then
    previewRenderer.enableLayerScrollMode(false)
    return
  end
  if #m.layerList == 0 then _rebuildLayerList(sprite) end
  local newIndex = m.focusIndex + delta
  if newIndex < 1 or newIndex > #m.layerList then return end
  local oldLayer = m.layerList[m.focusIndex]
  local newLayer = m.layerList[newIndex]
  if oldLayer then oldLayer.isVisible = false end
  if newLayer then newLayer.isVisible = true end
  m.focusIndex = newIndex
  _refreshCacheForRange(sprite, newIndex, newIndex, _activeFrameNumber())
end

function previewRenderer.getLayerScrollState()
  local m = previewRenderer.layerScrollMode
  return {
    enabled = m.enabled,
    focusIndex = m.focusIndex,
    behind = m.behind,
    front = m.front,
    total = #m.layerList
  }
end

--------------------------------------------------------------------------------
-- Voxel Model Generation
--------------------------------------------------------------------------------
function previewRenderer.generateVoxelModel(sprite)
  if not sprite then return {} end
  local mode = previewRenderer.layerScrollMode
  if mode.enabled and mode.spriteId ~= sprite then
    previewRenderer.enableLayerScrollMode(false)
  end

  -- Layer Scroll Mode path
  if mode.enabled then
    local flatCount = 0
    for _, layer in ipairs(sprite.layers) do
      if not layer.isGroup then flatCount = flatCount + 1 end
    end
    if flatCount ~= #mode.layerList then
      _rebuildLayerList(sprite)
      mode.focusIndex = math.min(mode.focusIndex, #mode.layerList)
    end
    if #mode.layerList == 0 then return {} end
    mode.focusIndex = math.min(math.max(1, mode.focusIndex), #mode.layerList)

    local startIdx = math.max(1, mode.focusIndex - mode.behind)
    local endIdx   = math.min(#mode.layerList, mode.focusIndex + mode.front)
    local frame = _activeFrameNumber()
    _refreshCacheForRange(sprite, startIdx, endIdx, frame)

    local model = {}
    local zCounter = 0
    for i = startIdx, endIdx do
      zCounter = zCounter + 1
      local entry = mode.cache[i]
      if entry and entry.image then
        local img = entry.image
        for y = 0, img.height - 1 do
          for x = 0, img.width - 1 do
            local px = img:getPixel(x, y)
            local a = app.pixelColor.rgbaA(px)
            if a > 0 then
              model[#model+1] = {
                x = x + entry.pos.x,
                y = y + entry.pos.y,
                z = zCounter,
                color = {
                  r = app.pixelColor.rgbaR(px),
                  g = app.pixelColor.rgbaG(px),
                  b = app.pixelColor.rgbaB(px),
                  a = a
                }
              }
            end
          end
        end
      end
    end
    return model
  end

  -- Standard path
  local model = {}
  local visibleLayers = {}
  for _, layer in ipairs(sprite.layers) do
    if not layer.isGroup and layer.isVisible then
      visibleLayers[#visibleLayers+1] = layer
    end
  end
  local frameIndex = _activeFrameNumber()
  for i, layer in ipairs(visibleLayers) do
    local z = i
    local cel = layer:cel(frameIndex)
    if cel and cel.image then
      local image = cel.image
      for y = 0, image.height - 1 do
        for x = 0, image.width - 1 do
          local px = image:getPixel(x, y)
            if app.pixelColor.rgbaA(px) > 0 then
            model[#model+1] = {
              x = x + cel.position.x,
              y = y + cel.position.y,
              z = z,
              color = {
                r = app.pixelColor.rgbaR(px),
                g = app.pixelColor.rgbaG(px),
                b = app.pixelColor.rgbaB(px),
                a = app.pixelColor.rgbaA(px)
              }
            }
          end
        end
      end
    end
  end
  return model
end

--------------------------------------------------------------------------------
-- Geometry Helpers
--------------------------------------------------------------------------------
function previewRenderer.calculateModelBounds(model)
  local b = { minX=math.huge, maxX=-math.huge,
              minY=math.huge, maxY=-math.huge,
              minZ=math.huge, maxZ=-math.huge }
  for _, v in ipairs(model) do
    if v.x < b.minX then b.minX = v.x end
    if v.x > b.maxX then b.maxX = v.x end
    if v.y < b.minY then b.minY = v.y end
    if v.y > b.maxY then b.maxY = v.y end
    if v.z < b.minZ then b.minZ = v.z end
    if v.z > b.maxZ then b.maxZ = v.z end
  end
  return b
end

function previewRenderer.calculateMiddlePoint(model)
  local b = previewRenderer.calculateModelBounds(model)
  return {
    x = (b.minX + b.maxX)/2,
    y = (b.minY + b.maxY)/2,
    z = (b.minZ + b.maxZ)/2,
    sizeX = b.maxX - b.minX + 1,
    sizeY = b.maxY - b.minY + 1,
    sizeZ = b.maxZ - b.minZ + 1
  }
end

--------------------------------------------------------------------------------
-- Visibility (face culling)
--------------------------------------------------------------------------------
local FACE_NORMALS = {
  front  = {0,0, 1},
  back   = {0,0,-1},
  right  = {1,0, 0},
  left   = {-1,0,0},
  top    = {0,1, 0},
  bottom = {0,-1,0}
}

function previewRenderer.calculateFaceVisibility(voxel, cameraPos, orthogonal, rotationParams)
  -- Native accelerated path if available
  if nativeBridge_ok and nativeBridge and nativeBridge.isAvailable
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
    -- X
    local y2 = y*cx - z*sx
    local z2 = y*sx + z*cx
    y,z = y2,z2
    -- Y
    local x2 = x*cy + z*sy
    local z3 = -x*sy + z*cy
    x,z = x2,z3
    -- Z
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

--------------------------------------------------------------------------------
-- Basic Mode Brightness (Formula B implementation)
--------------------------------------------------------------------------------
local function basicModeBrightness(faceName, rotationMatrix, viewDir, params)
  local n = FACE_NORMALS[faceName]
  if not n then return 1 end
  local nn = {
    rotationMatrix[1][1]*n[1] + rotationMatrix[1][2]*n[2] + rotationMatrix[1][3]*n[3],
    rotationMatrix[2][1]*n[1] + rotationMatrix[2][2]*n[2] + rotationMatrix[2][3]*n[3],
    rotationMatrix[3][1]*n[1] + rotationMatrix[3][2]*n[2] + rotationMatrix[3][3]*n[3],
  }
  local mag = math.sqrt(nn[1]*nn[1]+nn[2]*nn[2]+nn[3]*nn[3])
  if mag > 1e-6 then nn[1],nn[2],nn[3] = nn[1]/mag, nn[2]/mag, nn[3]/mag end
  local dot = nn[1]*viewDir[1] + nn[2]*viewDir[2] + nn[3]*viewDir[3]
  if dot <= 0 then dot = 0 end

  -- Basic shading formula B:
  -- si = basicShadeIntensity/100; li = basicLightIntensity/100;
  -- minB = 0.05 + 0.9*li
  -- curve = (1 - si)^2
  -- exponent = 1 + 6*curve
  -- brightness = minB + (1 - minB) * (dot^exponent)
  local si = (params.basicShadeIntensity or 50) / 100
  local li = (params.basicLightIntensity or 50) / 100
  
  local minB = 0.05 + 0.9 * li
  local curve = (1 - si) * (1 - si)
  local exponent = 1 + 6 * curve
  local brightness = minB + (1 - minB) * (dot ^ exponent)

  return brightness
end

--------------------------------------------------------------------------------
-- Dynamic Lighting System
--------------------------------------------------------------------------------
-- Compute light direction from yaw/pitch angles
local function computeLightDirection(yaw, pitch)
  local yawRad = math.rad(yaw)
  local pitchRad = math.rad(pitch)
  
  -- Light direction: yaw around Y-axis, pitch around X-axis
  local cosYaw = math.cos(yawRad)
  local sinYaw = math.sin(yawRad)
  local cosPitch = math.cos(pitchRad)
  local sinPitch = math.sin(pitchRad)
  
  return {
    x = cosYaw * cosPitch,
    y = sinPitch,
    z = sinYaw * cosPitch
  }
end

-- Smooth step function for falloffs
local function smoothstep(edge0, edge1, x)
  if x <= edge0 then return 0 end
  if x >= edge1 then return 1 end
  local t = (x - edge0) / (edge1 - edge0)
  return t * t * (3 - 2 * t)
end

-- Linear interpolation
local function lerp(a, b, t)
  return a + (b - a) * t
end

-- Legacy function retained for compatibility (returns 1, passthrough)
local function computeAngularFalloff(lightDir, normal, directionality, diffuse)
  return 1, lightDir.x * normal.x + lightDir.y * normal.y + lightDir.z * normal.z
end

-- Cache rotated normals once per frame
local function cacheRotatedNormals(rotationMatrix)
  local rotatedNormals = {}
  for name, n in pairs(FACE_NORMALS) do
    rotatedNormals[name] = {
      x = rotationMatrix[1][1]*n[1] + rotationMatrix[1][2]*n[2] + rotationMatrix[1][3]*n[3],
      y = rotationMatrix[2][1]*n[1] + rotationMatrix[2][2]*n[2] + rotationMatrix[2][3]*n[3],
      z = rotationMatrix[3][1]*n[1] + rotationMatrix[3][2]*n[2] + rotationMatrix[3][3]*n[3]
    }
    -- Normalize
    local mag = math.sqrt(rotatedNormals[name].x^2 + rotatedNormals[name].y^2 + rotatedNormals[name].z^2)
    if mag > 1e-6 then
      rotatedNormals[name].x = rotatedNormals[name].x / mag
      rotatedNormals[name].y = rotatedNormals[name].y / mag
      rotatedNormals[name].z = rotatedNormals[name].z / mag
    end
  end
  return rotatedNormals
end

--------------------------------------------------------------------------------
-- Polygon Fill Helpers
--------------------------------------------------------------------------------
function previewRenderer.isPointInPolygon(x, y, polygon)
  local inside = false
  local j = #polygon
  for i = 1, #polygon do
    local pi, pj = polygon[i], polygon[j]
    if ((pi.y > y) ~= (pj.y > y)) and
       (x < (pj.x - pi.x) * (y - pi.y) / (pj.y - pi.y) + pi.x) then
      inside = not inside
    end
    j = i
  end
  return inside
end

-- Replacement polygon rasterizer for voxel faces (Patch: fractional scale fix)
-- Issues addressed:
--  1. Previous implementation rounded vertex positions early -> gaps at fractional voxelSize.
--  2. Even/odd test with strict < caused right/top edge drop-out (missing pixel corners).
--  3. Rounding before fill produced "chipped" top-right corners.
-- New approach: scanline fill of convex quad using float vertices, half-open rule on Y, inclusive X.
local function drawConvexQuad(image, pts, color)
  if #pts ~= 4 then
    -- Fallback: simple edge plot (rare path)
    for i=1,#pts do
      local a = pts[i]
      local b = pts[(i % #pts)+1]
      local x0,y0,x1,y1 = a.x,a.y,b.x,b.y
      local dx = math.abs(x1-x0)
      local dy = math.abs(y1-y0)
      local steps = math.max(dx,dy)
      if steps < 1 then steps = 1 end
      for s=0,steps do
        local t = s/steps
        local px = x0 + (x1-x0)*t
        local py = y0 + (y1-y0)*t
        local ix = math.floor(px+0.5)
        local iy = math.floor(py+0.5)
        if ix>=0 and ix<image.width and iy>=0 and iy<image.height then
          image:putPixel(ix,iy,color)
        end
      end
    end
    return
  end

  local minY, maxY = math.huge, -math.huge
  for _,p in ipairs(pts) do
    if p.y < minY then minY = p.y end
    if p.y > maxY then maxY = p.y end
  end
  minY = math.max(0, math.floor(minY))
  maxY = math.min(image.height-1, math.ceil(maxY))

  local edges = {}
  for i=1,4 do
    local a = pts[i]
    local b = pts[(i % 4)+1]
    if a.y ~= b.y then
      if a.y < b.y then
        edges[#edges+1] = { y0=a.y, y1=b.y, x0=a.x, x1=b.x }
      else
        edges[#edges+1] = { y0=b.y, y1=a.y, x0=b.x, x1=a.x }
      end
    end
  end

  for y = minY, maxY do
    local scanY = y + 0.5
    local xInts = {}
    for _,e in ipairs(edges) do
      if scanY >= e.y0 and scanY < e.y1 then
        local t = (scanY - e.y0) / (e.y1 - e.y0)
        local x = e.x0 + (e.x1 - e.x0) * t
        xInts[#xInts+1] = x
      end
    end
    if #xInts >= 2 then
      table.sort(xInts)
      for k=1,#xInts,2 do
        local x0 = xInts[k]
        local x1 = xInts[k+1] or x0
        if x1 < x0 then x0,x1 = x1,x0 end
        local startX = math.max(0, math.floor(x0 + 0.5))
        local endX   = math.min(image.width-1, math.floor(x1 - 0.5))
        if endX < startX and (math.abs(x1 - x0) < 1.0) then endX = startX end
        for xPix = startX, endX do
          image:putPixel(xPix, y, color)
        end
      end
    end
  end
end

function previewRenderer.drawPolygon(image, points, color, method, size)
  drawConvexQuad(image, points, color)
end

--------------------------------------------------------------------------------
-- Core Shaded Face Drawing (updated for Basic/Dynamic/Stack modes)
--------------------------------------------------------------------------------
-- Replaced shadeFaceColor with unified implementation (supports legacy aliases + cache)
local function shadeFaceColor(faceName, baseColor, params)
  local shadingMode = params.shadingMode or "Stack"
  -- Normalize legacy aliases
  if shadingMode == "Complete" then shadingMode = "Dynamic" end
  if shadingMode == "Simple" then shadingMode = "Basic" end

  -- Dynamic lighting mode (standalone)
  if shadingMode == "Dynamic" then
    -- Accept legacy AND newer field names to avoid silent fallback
    local lighting = params.lighting
    -- dynamicLighting (older) vs dyn (newer)
    local dyn = params.dynamicLighting or params.dyn
    -- rotatedFaceNormals (older) vs rotatedNormals (alternate path in drawVoxel)
    local rotatedNormals = params.rotatedFaceNormals or params.rotatedNormals
    -- Per‑voxel vector name harmonization: lightVector (apex) else fallback to directional dyn.lightDir
    local L = params.lightVector or (dyn and dyn.lightDir)

    if not lighting then return baseColor end

    -- Primary cache: lighting._cache (choice 1:A). Accept legacy fallbacks.
    local cache = lighting._cache
                 or params._dynLightCache
                 or params.dyn
                 or params.dynamicLighting
    if not cache or not cache.rotatedNormals or not cache.lightDir then
      return baseColor
    end

    local normal = cache.rotatedNormals[faceName]
                   or (cache.rotatedFaceNormals and cache.rotatedFaceNormals[faceName])
    if not normal then return baseColor end

    -- Lambert term
    local ndotl = normal.x * cache.lightDir.x + normal.y * cache.lightDir.y + normal.z * cache.lightDir.z
    if ndotl < 0 then ndotl = 0 end

    local exponent = cache.exponent or 1
    local diffuse = ndotl ^ exponent

    -- Radial attenuation (per-voxel factor set by render loop)
    local radial = params._radialFactor or 1
    diffuse = diffuse * radial

    -- Shadow factor (simple placeholder / binary shadow can be added later)
    local shadow = params.shadowFactor
    if shadow == nil then shadow = 1 end
    diffuse = diffuse * shadow

    local baseR = baseColor.red or baseColor.r or 255
    local baseG = baseColor.green or baseColor.g or 255
    local baseB = baseColor.blue or baseColor.b or 255

    local lc = cache.lightColor or {r=1,g=1,b=1}
    local lr, lg, lb = (lc.r or 1), (lc.g or 1), (lc.b or 1)
    local ambient = cache.ambient or 0

    local r = baseR * (ambient + diffuse * lr)
    local g = baseG * (ambient + diffuse * lg)
    local b = baseB * (ambient + diffuse * lb)

    -- Rim: silhouette smoothstep (choice 4:A)
    if lighting.rimEnabled and cache.viewDir then
      local V = cache.viewDir
      local ndotv = normal.x * V.x + normal.y * V.y + normal.z * V.z
      if ndotv > 0 then
        local edge = 1 - ndotv
        local rimStart, rimEnd = 0.55, 0.95
        local t = 0
        if edge <= rimStart then
          t = 0
        elseif edge >= rimEnd then
          t = 1
        else
          local tt = (edge - rimStart) / (rimEnd - rimStart)
          t = tt*tt*(3 - 2*tt)
        end
        if t > 0 then
          local rimStrength = 0.6 -- Patch 1: rimStrength fixed (deprecated control)
          local rim = rimStrength * t
          r = r + lr * rim * 255
          g = g + lg * rim * 255
          b = b + rimStrength * rim * 255
        end
      end
    end

    r = (r < 0 and 0) or (r > 255 and 255 or math.floor(r + 0.5))
    g = (g < 0 and 0) or (g > 255 and 255 or math.floor(g + 0.5))
    b = (b < 0 and 0) or (b > 255 and 255 or math.floor(b + 0.5))
    return Color(r, g, b, baseColor.alpha or baseColor.a or 255)
  end

  -- Basic mode (renamed)
  if shadingMode == "Basic" then
    local M = params._rotationMatrixForFX
    if not M then
      M = mathUtils.createRotationMatrix(params.xRotation or 0, params.yRotation or 0, params.zRotation or 0)
      params._rotationMatrixForFX = M
    end
    params.viewDir = params.viewDir or {x=0,y=0,z=1}
    local vd = params.viewDir
    local mag = math.sqrt(vd.x*vd.x+vd.y*vd.y+vd.z*vd.z)
    if mag > 1e-6 then vd.x,vd.y,vd.z = vd.x/mag, vd.y/mag, vd.z/mag end
    local b = basicModeBrightness(faceName, M, {vd.x,vd.y,vd.z}, params)
    local r = math.floor((baseColor.red or baseColor.r) * b + 0.5)
    local g = math.floor((baseColor.green or baseColor.g) * b + 0.5)
    local bl = math.floor((baseColor.blue or baseColor.b) * b + 0.5)
    return Color(r,g,bl, baseColor.alpha or baseColor.a or 255)
  end

  -- Stack mode (FX)
  if shadingMode == "Stack" and params.fxStack and params.fxStack.modules and #params.fxStack.modules > 0 then
    if not params._rotationMatrixForFX then
      params._rotationMatrixForFX =
        mathUtils.createRotationMatrix(params.xRotation or 0, params.yRotation or 0, params.zRotation or 0)
    end
    params.viewDir = params.viewDir or {x=0,y=0,z=1}
    local shaded = fxStackModule.shadeFace({
        rotationMatrix = params._rotationMatrixForFX,
        viewDir = params.viewDir,
        fxStack = params.fxStack
      },
      faceName,
      {
        r = baseColor.red or baseColor.r,
        g = baseColor.green or baseColor.g,
        b = baseColor.blue or baseColor.b,
        a = baseColor.alpha or baseColor.a or 255
      }
    )
    return Color(shaded.r, shaded.g, shaded.b, shaded.a)
  end

  return baseColor
end

-- Updated drawVoxel to apply true perspective (FOV-based) projection.
function previewRenderer.drawVoxel(image, x, y, size, color, faceVisibility, params, tv, middlePoint, camera)
  local baseColor = Color(color.r, color.g, color.b, color.a or 255)

  -- Prepare per-face base colors (original color only)
  local faceBase = {}
  for faceName, _ in pairs(faceVisibility) do
    faceBase[faceName] = baseColor
  end

  local xRad = math.rad(params.xRotation or 0)
  local yRad = math.rad(params.yRotation or 0)
  local zRad = math.rad(params.zRotation or 0)

  local screenVertices = {}
  local cx, sx = math.cos(xRad), math.sin(xRad)
  local cy, sy = math.cos(yRad), math.sin(yRad)
  local cz, sz = math.cos(zRad), math.sin(zRad)

  local mp = middlePoint or params.middlePoint
  local centerOffX_px = (tv.x - mp.x) * size
  local centerOffY_px = (tv.y - mp.y) * size
  local centerOffZ_units = (tv.z - mp.z)
  local isPersp = (not params.orthogonal) and camera and camera.focalLength
  local cxScr = camera and camera.centerX or 0
  local cyScr = camera and camera.centerY or 0

  -- NOTE: keep full float precision until rasterization (fix fractional scale artifacts)
  for i, v in ipairs(UNIT_CUBE_VERTICES) do
    local vx_local = v[1] * size
    local vy_local = v[2] * size
    local vz_local = v[3] * size
    -- Combined rotation (X then Y then Z)
    local y2 = vy_local * cx - vz_local * sx
    local z2 = vy_local * sx + vz_local * cx
    vy_local, vz_local = y2, z2
    local x2 = vx_local * cy + vz_local * sy
    local z3 = -vx_local * sy + vz_local * cy
    vx_local, vz_local = x2, z3
    local x3 = vx_local * cz - vy_local * sz
    local y3 = vx_local * sz + vy_local * cz
    local rx, ry, rz = x3, y3, vz_local

    local perspective = 1
    if not params.orthogonal then
      perspective = 1 / (1 - rz * 0.001)
    end
    local relX_px = centerOffX_px + x3
    local relY_px = centerOffY_px + y3
    local relZ_units = centerOffZ_units + (vz_local / size)
    local sxp, syp, depthTag
    if isPersp then
      local worldZ = tv.z + (vz_local / size)
      local depth = camera.posZ - worldZ
      if depth < 0.001 then depth = 0.001 end
      local scale = camera.focalLength / depth
      sxp = cxScr + relX_px * scale
      syp = cyScr + relY_px * scale
      depthTag = depth
    else
      sxp = x + x3
      syp = y + y3
      depthTag = relZ_units
    end
    screenVertices[i] = { x = sxp, y = syp, z = depthTag }
  end

  -- Depth sort faces (farther first) by avg Z
  local sorted = {}
  for _, face in ipairs(FACE_DEFS) do
    local avgZ = 0
    for _, idx in ipairs(face.indices) do
      avgZ = avgZ + screenVertices[idx].z
    end
    avgZ = avgZ / 4
    sorted[#sorted+1] = { face=face, depth=avgZ }
  end
  table.sort(sorted, function(a,b) return a.depth < b.depth end)

  -- Prepare lighting (if enabled)
  local lighting = params.lighting or {}
  local lightMode = (lighting.enabled == false or lighting.mode == "off") and "off" or (lighting.mode or "dynamic")
  local lightDir = lighting.lightDir
  local rotatedNormals = {}
  
  if lightMode == "dynamic" then
    -- Prepare face normals in model space
    local faceNormalsLocal = {
      front  = {x=0,y=0,z=1},
      back   = {x=0,y=0,z=-1},
      right  = {x=1,y=0,z=0},
      left   = {x=-1,y=0,z=0},
      top    = {x=0,y=1,z=0},
      bottom = {x=0,y=-1,z=0}
    }
    
    -- Rotate normals with quaternion for accurate lighting
    local qRot = eulerToQuat(params.xRotation, params.yRotation, params.zRotation)
    for name, n in pairs(faceNormalsLocal) do
      rotatedNormals[name] = normalize(quatRotateVec(qRot, n))
    end
    
    params.rotatedNormals = rotatedNormals
    params.lightDir = normalize(lightDir or {x=0.55,y=0.75,z=0.35})
  end

  for _, item in ipairs(sorted) do
    local face = item.face
    if faceVisibility[face.name] then
      local pts = {}
      for _, idx in ipairs(face.indices) do
        pts[#pts+1] = screenVertices[idx]
      end
      local shadedColor = shadeFaceColor(face.name, faceBase[face.name], params)
      previewRenderer.drawPolygon(image, pts, shadedColor, params.interpolationMethod or "Nearest Neighbor", size)
    end
  end
end

--------------------------------------------------------------------------------
-- Main Preview Render
--------------------------------------------------------------------------------
function previewRenderer.renderPreview(model, params)
  params = params or {}
  local _t_start = _nowMs()
  local _metrics = params.metrics  -- optional metrics table injected by caller
  if _metrics then
    _metrics.backend = "local"
    _metrics.voxels = (model and #model or 0)
    _metrics.facesDrawn = 0
    _metrics.facesBackfaced = 0
    _metrics.facesCulledAdj = 0
    _metrics.polygonsFilled = 0
  end
  params.xRotation = params.xRotation or 0
  params.yRotation = params.yRotation or 0
  params.zRotation = params.zRotation or 0
  params.scale     = params.scale or 1
  params.width     = params.width or 200
  params.height    = params.height or 200
  params.orthogonal = params.orthogonal or false
  params.shadingMode = params.shadingMode or "Stack"

  local outW, outH = params.width, params.height
  local ss = 1
  if params.scale < 1 then
    ss = math.ceil(1 / params.scale)
  end
  local width  = outW * ss
  local height = outH * ss
  local image = Image(width, height, ColorMode.RGB)
  if params.backgroundColor then
    image:clear(params.backgroundColor)
  else
    image:clear(Color(0,0,0,0))
  end

  if not model or #model == 0 then return image end

  local bounds = previewRenderer.calculateModelBounds(model)
  local middlePoint = {
    x = (bounds.minX + bounds.maxX)/2,
    y = (bounds.minY + bounds.maxY)/2,
    z = (bounds.minZ + bounds.maxZ)/2
  }
  local modelWidth  = bounds.maxX - bounds.minX + 1
  local modelHeight = bounds.maxY - bounds.minY + 1
  local modelDepth  = bounds.maxZ - bounds.minZ + 1
  local maxDimension = math.max(modelWidth, modelHeight, modelDepth)
  local diagModel = math.sqrt(modelWidth*modelWidth + modelHeight*modelHeight + modelDepth*modelDepth)
  local modelRadiusApprox = 0.5 * diagModel

  local centerX, centerY = width/2, height/2

  local baseUnitSize = 1
  local voxelSize = math.max(1, baseUnitSize * (params.scale * ss))
  local maxAllowed = math.min(width, height) * 0.9
  if voxelSize * maxDimension > maxAllowed then
    voxelSize = voxelSize * (maxAllowed / (voxelSize * maxDimension))
  end

  ---------------------------------------------------------------------------
  -- Perspective Camera & Warping Control (enhanced)
  -- Keep head‑on scale consistent across perspective refs:
  -- We always calibrate voxelSize against the model "middle" depth so that
  -- a mid‑depth voxel is capped to params.scale pixels (at most), regardless
  -- of perspectiveScaleRef ("middle" | "back" | "front"). This fixes the
  -- report where "front" looked smaller head‑on.
  -- Note: The chosen perspectiveScaleRef is preserved in params for the
  -- next patch to pivot which group stays exactly at scale during rotation.
  ---------------------------------------------------------------------------
  local fovDeg = (params.fovDegrees or params.fov)
  local camera, cameraDistance
  local cameraPos
  if (not params.orthogonal) and fovDeg then
    fovDeg = math.max(5, math.min(75, fovDeg))
    local warpT = (fovDeg - 5) / (75 - 5)
    local amplified = warpT ^ (1/3) -- concave amplification
    local BASE_NEAR  = 1.2
    local FAR_EXTRA  = 45.0
    cameraDistance = maxDimension * (BASE_NEAR + (1 - amplified)^2 * FAR_EXTRA)
    cameraPos = { x = middlePoint.x, y = middlePoint.y, z = middlePoint.z + cameraDistance }
    local fovRad = math.rad(fovDeg)
    local focalLength = (height/2) / math.tan(fovRad/2)
    -- Perspective reference scaling:
    -- Choose which depth stays at "scale" pixels: middle (default), front (closest), or back (farthest).
    local refMode = (params.perspectiveScaleRef or "middle")
    -- Compute Z-extents (in world space after rotation) using AABB corners
    local minX, maxX = bounds.minX, bounds.maxX
    local minY, maxY = bounds.minY, bounds.maxY
    local minZ, maxZ = bounds.minZ, bounds.maxZ
    local function tpt(x,y,z)
      return rotation.transformVoxel({x=x,y=y,z=z,color={r=0,g=0,b=0,a=255}}, {
        middlePoint = middlePoint,
        xRotation = params.xRotation or 0,
        yRotation = params.yRotation or 0,
        zRotation = params.zRotation or 0
      })
    end
    local corners = {
      {minX,minY,minZ},{maxX,minY,minZ},{minX,maxY,minZ},{maxX,maxY,minZ},
      {minX,minY,maxZ},{maxX,minY,maxZ},{minX,maxY,maxZ},{maxX,maxY,maxZ}
    }
    local zMin, zMax = math.huge, -math.huge
    for _,c in ipairs(corners) do
      local tp = tpt(c[1],c[2],c[3])
      if tp.z < zMin then zMin = tp.z end
      if tp.z > zMax then zMax = tp.z end
    end
    -- Depths from camera for back (farthest) and front (closest) voxels
    local depthBack  = math.max(0.001, cameraPos.z - zMin) -- largest depth
    local depthFront = math.max(0.001, cameraPos.z - zMax) -- smallest depth
    local depthMiddle= math.max(0.001, cameraDistance)
    local depthRef = depthMiddle
    if refMode == "front" or refMode == "Front" then
      depthRef = depthFront
    elseif refMode == "back" or refMode == "Back" then
      depthRef = depthBack
    end
    -- Exact reference fit: set voxelSize so that a voxel at depthRef projects to target "scale" pixels.
    local targetPix = params.scale or 1
    if targetPix <= 0 then targetPix = 1 end
    voxelSize = targetPix * (depthRef / focalLength)
    -- Safety: avoid overflowing canvas; clamp to 90% of viewport if necessary
    if voxelSize * maxDimension > maxAllowed then
      voxelSize = maxAllowed / maxDimension
    end
    camera = { focalLength = focalLength, centerX = centerX, centerY = centerY, posZ = cameraPos.z }
    params._cameraFovDeg = fovDeg
    params._cameraDistance = cameraDistance
    -- Preserve the user's chosen reference for subsequent passes/features
    params._perspectiveScaleRef = params.perspectiveScaleRef or "middle"
    params._modelRadiusApprox = modelRadiusApprox
  else
    cameraDistance = maxDimension * 5
    cameraPos = { x = middlePoint.x, y = middlePoint.y, z = middlePoint.z + cameraDistance }
    params._cameraFovDeg = nil
    params._cameraDistance = cameraDistance
  end
  params.middlePoint = middlePoint
  params.voxelSize = voxelSize

  -- Optimize / hidden faces
  local _t_opt_start = _nowMs()
  local optimized = rotation.optimizeVoxelModel(model)
  if _metrics then _metrics.t_optimize_ms = _nowMs() - _t_opt_start end

  -- Depth sort
  local _t_sort_start = _nowMs()
  local order = {}
  for i, voxel in ipairs(model) do
    local t = rotation.transformVoxel(voxel, {
      middlePoint = middlePoint,
      xRotation = params.xRotation,
      yRotation = params.yRotation,
      zRotation = params.zRotation
    })
    local vcx = t.x + 0.5
    local vcy = t.y + 0.5
    local vcz = t.z + 0.5
    local dx = vcx - cameraPos.x
    local dy = vcy - cameraPos.y
    local dz = vcz - cameraPos.z
    order[#order+1] = {
      voxel = voxel,
      transformed = t,
      depth = dx*dx + dy*dy + dz*dz,
      hiddenFaces = optimized[i].hiddenFaces or {}
    }
  end
  table.sort(order, function(a,b) return a.depth > b.depth end)
  if _metrics then _metrics.t_transformSort_ms = _nowMs() - _t_sort_start end

  -- Patch 3: Build unified dynamic lighting cache inside params.lighting._cache
  if params.shadingMode == "Dynamic" and params.lighting then
    local L = params.lighting

    -- Compute camera-space light direction from yaw/pitch (camera-fixed)
    local camLight = computeLightDirection(L.yaw or 25, L.pitch or 25)
    local camMag = math.sqrt(camLight.x*camLight.x + camLight.y*camLight.y + camLight.z*camLight.z)
    if camMag > 1e-6 then camLight.x, camLight.y, camLight.z = camLight.x/camMag, camLight.y/camMag, camLight.z/camMag
    else camLight = {x=0,y=0,z=1} end

    -- Base exponent from diffuse (lerp 5..1)
    local diffPct = (L.diffuse or 60)/100
    -- Patch 1: directionality removed; exponent depends only on diffuse (5 -> 1)
    local exponent = 5 - 4 * diffPct
    if exponent < 0.2 then exponent = 0.2 end

    -- Ambient legacy curve
    local ambientPct = (L.ambient or 30)/100
    local ambient = 0.02 + 0.48 * ambientPct

    -- Light color normalized
    local lc = L.lightColor or Color(255,255,255)
    local lightColor = {
      r = (lc.red or lc.r or 255)/255,
      g = (lc.green or lc.g or 255)/255,
      b = (lc.blue or lc.b or 255)/255
    }

    -- Rotation matrix for model (used to map camera-space light into model-space)
    local rotM = mathUtils.createRotationMatrix(params.xRotation or 0, params.yRotation or 0, params.zRotation or 0)
    local rotatedNormals = cacheRotatedNormals(rotM)

    -- Convert camera-space light into model-space for geometry needs (cone axis, radial attenuation).
    -- However: rotatedNormals were computed as R * n (camera-space). For correct shading we must
    -- compute ndotl in the same space — so keep camLight (camera-space) for shading and store
    -- the model-space vector separately for geometry.
    local inv = mathUtils.transposeMatrix(rotM)
    local lightModel = {
      x = inv[1][1] * camLight.x + inv[1][2] * camLight.y + inv[1][3] * camLight.z,
      y = inv[2][1] * camLight.x + inv[2][2] * camLight.y + inv[2][3] * camLight.z,
      z = inv[3][1] * camLight.x + inv[3][2] * camLight.y + inv[3][3] * camLight.z
    }
    local lm = math.sqrt(lightModel.x*lightModel.x + lightModel.y*lightModel.y + lightModel.z*lightModel.z)
    if lm > 1e-6 then lightModel.x, lightModel.y, lightModel.z = lightModel.x/lm, lightModel.y/lm, lightModel.z/lm
    else lightModel = {x=0,y=0,z=1} end

    -- Model geometry helpers for radial attenuation (diameter interpreted relative to model radius)
    local diag = math.sqrt(modelWidth*modelWidth + modelHeight*modelHeight + modelDepth*modelDepth)
    local modelRadius = 0.5 * diag
    local diaPct = (L.diameter or 100)/100
    local baseRadius = math.max(0, diaPct * modelRadius)
    local coreRadius = baseRadius * math.max(0, (1 - 0.4 * diffPct))

    -- Compute rim distance from center so rim points lie on bounding sphere
    local rimDistFromCenter = 0
    local S = modelRadius
    if baseRadius >= S then
      rimDistFromCenter = 0
      baseRadius = math.min(baseRadius, S * 0.999)
    else
      rimDistFromCenter = math.sqrt(math.max(0, S*S - baseRadius*baseRadius))
    end

    -- Axis in model space (points from center toward light)
    local axisModel = { x = lightModel.x, y = lightModel.y, z = lightModel.z }

    -- Populate the unified cache inside lighting table
    L._cache = {
      -- Use camera-space direction for shading (rotatedNormals are camera-space).
      lightDir = camLight,             -- camera-space light direction (used for ndotl)
      lightModel = lightModel,         -- model-space light direction (keep for cone/geometry)          -- model-space light direction
      exponent = exponent,
      ambient = ambient,
      lightColor = lightColor,
      rotatedNormals = rotatedNormals,
      viewDir = {x=0,y=0,z=1},
      modelCenter = {x=middlePoint.x, y=middlePoint.y, z=middlePoint.z},
      modelRadius = modelRadius,
      baseRadius = baseRadius,
      coreRadius = coreRadius,
      rimDistFromCenter = rimDistFromCenter,
      axis = axisModel
    }
    -- Backwards-compat exports
    params._dynLightCache = L._cache
    params.dyn = params.dyn or L._cache
    params.dynamicLighting = params.dynamicLighting or L._cache
  else
    if params.lighting then params.lighting._cache = nil end
    params._dynLightCache = nil
  end

  local _t_draw_start = _nowMs()
  for _, item in ipairs(order) do
    local v = item.voxel
    local tv = item.transformed
    -- raw visibility (before adjacency cull) for metrics
    local faceVisRaw = previewRenderer.calculateFaceVisibility(tv, cameraPos, params.orthogonal, {
      xRotation = params.xRotation,
      yRotation = params.yRotation,
      zRotation = params.zRotation,
      voxelSize = voxelSize
    })
    local faceVis = {front=false,back=false,right=false,left=false,top=false,bottom=false}
    -- count backfaces for metrics
    if _metrics then
      for fname, vis in pairs(faceVisRaw) do
        if not vis then _metrics.facesBackfaced = _metrics.facesBackfaced + 1 end
      end
    end
    -- apply adjacency culling
    for fname, vis in pairs(faceVisRaw) do faceVis[fname] = vis end
    for faceName, hidden in pairs(item.hiddenFaces) do
      if hidden then
        faceVis[faceName] = false
        if _metrics then _metrics.facesCulledAdj = _metrics.facesCulledAdj + 1 end
      end
    end

    -- Dynamic per-voxel: radial attenuation & simple shadow placeholder
    if params.shadingMode == "Dynamic" and params.lighting and params.lighting._cache then
      local cache = params.lighting._cache
      -- Compute perpendicular distance from voxel to the light axis (axis passes through model center)
      local vx = v.x - cache.modelCenter.x
      local vy = v.y - cache.modelCenter.y
      local vz = v.z - cache.modelCenter.z
      local ax, ay, az = cache.axis.x, cache.axis.y, cache.axis.z
      -- projection length along axis
      local proj = vx*ax + vy*ay + vz*az
      -- perpendicular vector = v - proj*axis
      local px = vx - proj*ax
      local py = vy - proj*ay
      local pz = vz - proj*az
      local perpDist = math.sqrt(px*px + py*py + pz*pz)

      local radial = 1
      local diameterRadius = cache.baseRadius or 0.0001
      if diameterRadius and diameterRadius > 1e-6 then
        if perpDist <= cache.coreRadius then
          radial = 1
        elseif perpDist >= diameterRadius then
          radial = 0
        else
          local t = (perpDist - cache.coreRadius) / (diameterRadius - cache.coreRadius)
          radial = 1 - (t*t*(3 - 2*t)) -- inverted smoothstep
        end
      end
      params._radialFactor = radial
      params.shadowFactor = 1
    elseif params.shadingMode == "Dynamic" then
      params._radialFactor = 1
      params.shadowFactor = 1
    end

    local sx = centerX + (tv.x - middlePoint.x) * voxelSize
    local sy = centerY + (tv.y - middlePoint.y) * voxelSize
    -- Count faces to be drawn for metrics
    if _metrics then
      local drawCount = 0
      for fname, vis in pairs(faceVis) do if vis then drawCount = drawCount + 1 end end
      _metrics.facesDrawn = _metrics.facesDrawn + drawCount
      _metrics.polygonsFilled = _metrics.polygonsFilled + drawCount
    end
    previewRenderer.drawVoxel(image, sx, sy, voxelSize, v.color, faceVis, params, tv, middlePoint, camera)
  end
  if _metrics then _metrics.t_draw_ms = _nowMs() - _t_draw_start end

  if params.enableOutline and params.outlineSettings then
    local _t_outline_start = _nowMs()
    image = previewRenderer.applyOutline(image, params.outlineSettings)
    if _metrics then _metrics.t_outline_ms = _nowMs() - _t_outline_start end
  end

  if ss > 1 then
    local _t_down_start = _nowMs()
    image = previewRenderer.downsampleInteger(image, ss, params.downsample or "nearest")
    -- Safety clamp (should already match)
    if image.width ~= outW or image.height ~= outH then
      local fixed = Image(outW, outH, image.colorMode)
      fixed:drawImage(image, 0, 0)
      image = fixed
    end
    if _metrics then _metrics.t_downsample_ms = _nowMs() - _t_down_start end
  end
  if _metrics then _metrics.t_total_ms = _nowMs() - _t_start end
  return image
end

--------------------------------------------------------------------------------
-- Wrapper: renderVoxelModel (handles remote first)
--------------------------------------------------------------------------------
function previewRenderer.renderVoxelModel(model, params)
  params = params or {}
  local _metrics = params.metrics
  local xRot = params.x or params.xRotation or 0
  local yRot = params.y or params.yRotation or 0
  local zRot = params.z or params.zRotation or 0
  local scale = params.scale or params.scaleLevel or 1.0
  params.scale = scale

  -- Native renderer fast-path (Basic / Stack / Dynamic)
  local canNativeNative = nativeBridge_ok
    and nativeBridge
    and nativeBridge.isAvailable()

  local rr = _getRemote()
  if rr and rr.isEnabled and rr.isEnabled() then
    canNativeNative = false
  end

  if canNativeNative and model and #model > 0 then
    local flat = {}
    for i,v in ipairs(model) do
      local c = v.color or {}
      flat[i] = {
        v.x or 0, v.y or 0, v.z or 0,
        math.max(0, math.min(255, c.r or c.red or 255)),
        math.max(0, math.min(255, c.g or c.green or 255)),
        math.max(0, math.min(255, c.b or c.blue or 255)),
        math.max(0, math.min(255, c.a or c.alpha or 255))
      }
    end
    local bg = params.backgroundColor
    local nativeParams = {
      width  = params.width or 200,
      height = params.height or 200,
      xRotation = xRot, yRotation = yRot, zRotation = zRot,
      scale = scale,
      orthogonal = params.orthogonal or params.orthogonalView or false,
      basicShadeIntensity = params.basicShadeIntensity or 50,
      basicLightIntensity = params.basicLightIntensity or 50,
      fovDegrees = params.fovDegrees or params.fov,
      perspectiveScaleRef = params.perspectiveScaleRef or "middle",
      backgroundColor = bg and {
        r = bg.red or bg.r, g = bg.green or bg.g, b = bg.blue or bg.b, a = bg.alpha or bg.a
      } or {r=0,g=0,b=0,a=0}
    }
    -- Dynamic lighting param packaging (only when needed)
    if params.shadingMode == "Dynamic" and params.lighting then
      local lc = params.lighting.lightColor or Color(255,255,255)
      nativeParams.lighting = {
        pitch      = params.lighting.pitch or 0,
        yaw        = params.lighting.yaw or 0,
        diffuse    = params.lighting.diffuse or 60,
        diameter   = params.lighting.diameter or 100,
        ambient    = params.lighting.ambient or 30,
        rimEnabled = params.lighting.rimEnabled and true or false,
        lightColor = {
          r = lc.red or lc.r or 255,
          g = lc.green or lc.g or 255,
          b = lc.blue or lc.b or 255
        }
      }
    end
    local nativeResult
    if params.shadingMode == "Stack" and nativeBridge.renderStack then
      nativeParams.fxStack = params.fxStack
      nativeResult = nativeBridge.renderStack(flat, nativeParams)
    elseif params.shadingMode == "Dynamic" and nativeBridge.renderDynamic then
      nativeResult = nativeBridge.renderDynamic(flat, nativeParams)
    else
      nativeResult = nativeBridge.renderBasic(flat, nativeParams)
    end
    if nativeResult and nativeResult.pixels then
      local w = nativeResult.width
      local h = nativeResult.height
      local bytes = nativeResult.pixels
      local expected = w * h * 4
      if #bytes == expected then
        local img = Image(w, h, ColorMode.RGB)
        local idx = 1
        for y=0,h-1 do
          for x=0,w-1 do
            local r = string.byte(bytes, idx    )
            local g = string.byte(bytes, idx + 1)
            local b = string.byte(bytes, idx + 2)
            local a = string.byte(bytes, idx + 3)
            idx = idx + 4
            img:putPixel(x, y, app.pixelColor.rgba(r,g,b,a))
          end
        end
        if _metrics then
          if params.shadingMode=="Stack" then
            _metrics.backend = "native-stack"
          elseif params.shadingMode=="Dynamic" then
            _metrics.backend = "native-dynamic"
          else
            _metrics.backend = "native-basic"
          end
         end
        return img
      else
        print("[asevoxel-native] native buffer mismatch (fallback)")
      end
    end
  end

  -- (remote path retained)
  if rr and rr.isEnabled and rr.isEnabled() then
    if _metrics then _metrics.backend = "remote" end
    -- NOTE: FX Stack NOT applied remotely yet.
    local voxelsFlat = {}
    for _, v in ipairs(model) do
      voxelsFlat[#voxelsFlat+1] = {
        v.x, v.y, v.z,
        math.max(0, math.min(255, v.color.r or 0)),
        math.max(0, math.min(255, v.color.g or 0)),
        math.max(0, math.min(255, v.color.b or 0)),
        math.max(0, math.min(255, v.color.a or 255))
      }
    end
    local lightingGrid = {}
    for i=1,27 do lightingGrid[i]=0 end
    lightingGrid[2*9 + 1*3 + 1 + 1] = 1
    local outlineSettings = params.outlineSettings or {}
    local outlineColor = outlineSettings.color
    local outline = {
      enabled = params.enableOutline or false,
      place = outlineSettings.place or "outside",
      pattern = outlineSettings.matrix or "circle",
      color = (outlineColor and {
        r = outlineColor.red or outlineColor.r or 0,
        g = outlineColor.green or outlineColor.g or 0,
        b = outlineColor.blue or outlineColor.b or 0,
        a = outlineColor.alpha or outlineColor.a or 255
      }) or {r=0,g=0,b=0,a=255}
    }
    local bg = params.backgroundColor
    local backgroundColor = bg and {
      r = bg.red or bg.r or 0,
      g = bg.green or bg.g or 0,
      b = bg.blue or bg.b or 0,
      a = bg.alpha or bg.a or 0
    } or {r=0,g=0,b=0,a=0}

    local options = {
      rotation = { xRot, yRot, zRot },
      width = params.width,
      height = params.height,
      scale = scale,
      backgroundColor = backgroundColor,
      orthographic = params.orthogonal or params.orthogonalView or false,
      depthFactor = (params.depth or params.depthFactor or (params.depthPerspective and params.depthPerspective/100)) or 0,
      shading = {
        mode = "flat",
        ambient = 0.2,
        useAlpha = false
      },
      lighting = { grid = lightingGrid, spherical = true },
      outline = outline
    }
    local img, err = remoteRenderer.render(voxelsFlat, options)
    if img then return img end
    if err then print("Remote render failed: " .. tostring(err)) end
  end

  return previewRenderer.renderPreview(model, {
    xRotation = xRot,
    yRotation = yRot,
    zRotation = zRot,
    scale = scale,
    width = params.width,
    height = params.height,
    orthogonal = params.orthogonal or params.orthogonalView or false,
    backgroundColor = params.backgroundColor,
    enableOutline = params.enableOutline or false,
    outlineSettings = params.outlineSettings,
    fovDegrees = params.fovDegrees or params.fov or (params.depthPerspective and (5 + (75-5)*(params.depthPerspective/100))) or nil,
    -- NEW: forward perspective scale reference to renderer
    perspectiveScaleRef = params.perspectiveScaleRef or "middle",
    fxStack = params.fxStack,
    shadingMode = params.shadingMode or "Stack",
    lighting = params.lighting,
    metrics = _metrics,
  })
end

--------------------------------------------------------------------------------
-- Outline
--------------------------------------------------------------------------------
function previewRenderer.applyOutline(image, outlineSettings)
  if not outlineSettings then return image end
  local place  = outlineSettings.place or "outside"
  local matrix = outlineSettings.matrix or "circle"
  local outlineColor = Color(0,0,0)
  if outlineSettings.color then
    if type(outlineSettings.color) == "userdata" then
      outlineColor = outlineSettings.color
    elseif type(outlineSettings.color) == "table" then
      outlineColor = Color(
        outlineSettings.color.r or 0,
        outlineSettings.color.g or 0,
        outlineSettings.color.b or 0,
        outlineSettings.color.a or 255
      )
    end
  end

  local kernelOffsets
  if matrix == "circle" then
    kernelOffsets = {{0,-1},{-1,0},{1,0},{0,1}}
  elseif matrix == "square" then
    kernelOffsets = {
      {-1,-1},{0,-1},{1,-1},
      {-1, 0},       {1, 0},
      {-1, 1},{0, 1},{1, 1}
    }
  elseif matrix == "horizontal" then
    kernelOffsets = {{-1,0},{1,0}}
  elseif matrix == "vertical" then
    kernelOffsets = {{0,-1},{0,1}}
  else
    kernelOffsets = {{0,-1},{-1,0},{1,0},{0,1}}
  end

  local width, height = image.width, image.height
  if width < 3 or height < 3 then return image end

  local result = image:clone()
  local edgePixels = {}

  if place == "outside" then
    for y = 1, height-2 do
      for x = 1, width-2 do
        local a = app.pixelColor.rgbaA(image:getPixel(x,y))
        if a == 0 then
          local hasOpaque = false
          for _, o in ipairs(kernelOffsets) do
            local nx, ny = x+o[1], y+o[2]
            if nx>=0 and nx<width and ny>=0 and ny<height then
              local na = app.pixelColor.rgbaA(image:getPixel(nx,ny))
              if na > 0 then hasOpaque=true; break end
            end
          end
          if hasOpaque then edgePixels[#edgePixels+1] = {x=x,y=y} end
        end
      end
    end
  else -- inside
    for y = 1, height-2 do
      for x = 1, width-2 do
        local a = app.pixelColor.rgbaA(image:getPixel(x,y))
        if a > 0 then
          local hasTransparent = false
          for _, o in ipairs(kernelOffsets) do
            local nx, ny = x+o[1], y+o[2]
            if nx>=0 and nx<width and ny>=0 and ny<height then
              local na = app.pixelColor.rgbaA(image:getPixel(nx,ny))
              if na == 0 then hasTransparent = true; break end
            end
          end
          if hasTransparent then edgePixels[#edgePixels+1] = {x=x,y=y} end
        end
      end
    end
  end

  for _, p in ipairs(edgePixels) do
    result:putPixel(p.x, p.y, outlineColor)
  end
  return result
end

--------------------------------------------------------------------------------
-- Downsample (integer factor)
--------------------------------------------------------------------------------
function previewRenderer.downsampleInteger(src, factor, mode)
  local outW = math.max(1, math.floor(src.width / factor))
  local outH = math.max(1, math.floor(src.height / factor))
  local dst = Image(outW, outH, src.colorMode)
  local useBox = (mode == "box")
  for oy = 0, outH - 1 do
    local iy0 = oy * factor
    for ox = 0, outW - 1 do
      local ix0 = ox * factor
      if not useBox then
        dst:putPixel(ox, oy, src:getPixel(ix0, iy0))
      else
        local rSum,gSum,bSum,aSum = 0,0,0,0
        for ky=0,factor-1 do
          for kx=0,factor-1 do
            local c = src:getPixel(ix0+kx, iy0+ky)
            rSum = rSum + app.pixelColor.rgbaR(c)
            gSum = gSum + app.pixelColor.rgbaG(c)
            bSum = bSum + app.pixelColor.rgbaB(c)
            aSum = aSum + app.pixelColor.rgbaA(c)
          end
        end
        local cnt = factor*factor
        local r = math.floor(rSum/cnt + 0.5)
        local g = math.floor(gSum/cnt + 0.5)
        local b = math.floor(bSum/cnt + 0.5)
        local a = math.floor(aSum/cnt + 0.5)
        dst:putPixel(ox, oy, app.pixelColor.rgba(r,g,b,a))
      end
    end
  end
  return dst
end

--------------------------------------------------------------------------------
-- OBJ Export (Y-flip version)
--------------------------------------------------------------------------------
-- REPLACED exportOBJ: adds Y-axis inversion (sprite Y-down -> OBJ Y-up)
function previewRenderer.exportOBJ(voxels, filePath, options)
  options = options or {}
  local scale = options.scaleModel or 1.0
  local includeColors = (options.includeColors ~= false)
  local useMaterials = (options.colorFormat or "materials") == "materials"

  -- Bounds for Y inversion (Aseprite Y-down -> OBJ Y-up)
  local bounds = previewRenderer.calculateModelBounds(voxels)
  local minY, maxY = bounds.minY, bounds.maxY
  local heightSpan = maxY - minY

  local f = io.open(filePath, "w")
  if not f then return false, "Cannot open OBJ file" end
  f:write("# Exported from AseVoxel\n")

  local mtlFile
  local materialMap = {}
  local matCount = 0

  if includeColors and useMaterials then
    local mtlPath = app.fs.joinPath(app.fs.filePath(filePath), "voxel_export.mtl")
    f:write("mtllib voxel_export.mtl\n")
    mtlFile = io.open(mtlPath, "w")
    mtlFile:write("# Materials generated by AseVoxel\n")
  end

  -- Cube vertex layout (unit cube centered at origin)
  local CUBE_VERTS = {
    {-0.5,-0.5,-0.5}, { 0.5,-0.5,-0.5}, { 0.5, 0.5,-0.5}, {-0.5, 0.5,-0.5}, -- back
    {-0.5,-0.5, 0.5}, { 0.5,-0.5, 0.5}, { 0.5, 0.5, 0.5}, {-0.5, 0.5, 0.5}, -- front
  }

  -- Face definitions (each quad in CCW order)
  local FACES = {
    {4,3,2,1, normal={ 0, 0,-1}}, -- back
    {5,6,7,8, normal={ 0, 0, 1}}, -- front
    {2,3,7,6, normal={ 1, 0, 0}}, -- right
    {1,5,8,4, normal={-1, 0, 0}}, -- left
    {4,8,7,3, normal={ 0, 1, 0}}, -- top
    {1,2,6,5, normal={ 0,-1, 0}}, -- bottom
  }

  -- Write shared normals
  for _, face in ipairs(FACES) do
    local n = face.normal
    f:write(string.format("vn %.4f %.4f %.4f\n", n[1], n[2], n[3]))
  end

  local vertOffset = 0
  for _, v in ipairs(voxels) do
    local x = v.x * scale
    local y = ((heightSpan - (v.y - minY)) + minY) * scale
    local z = v.z * scale
    local r = (v.color.r or 255)
    local g = (v.color.g or 255)
    local b = (v.color.b or 255)

    local matName
    if includeColors and useMaterials then
      local key = string.format("%d_%d_%d", r, g, b)
      matName = materialMap[key]
      if not matName then
        matCount = matCount + 1
        matName = "voxel_" .. matCount
        materialMap[key] = matName
        if mtlFile then
          mtlFile:write("newmtl "..matName.."\n")
          mtlFile:write(string.format("Kd %.4f %.4f %.4f\n", r/255, g/255, b/255))
          mtlFile:write("d 1.0\nillum 2\n\n")
        end
      end
    end

    if matName then
      f:write("usemtl "..matName.."\n")
    end

    -- write cube vertices
    for _, cv in ipairs(CUBE_VERTS) do
      f:write(string.format("v %.4f %.4f %.4f\n",
        x + cv[1]*scale, y + cv[2]*scale, z + cv[3]*scale))
    end

    -- write faces referencing shared normals (vn indices 1..6)
    for faceIndex, face in ipairs(FACES) do
      local vi = {}
      for _, idx in ipairs(face) do
        table.insert(vi, string.format("%d//%d", vertOffset + idx, faceIndex))
      end
      f:write("f "..table.concat(vi," ").."\n")
    end

    vertOffset = vertOffset + 8
  end

  if mtlFile then mtlFile:close() end
  f:close()
  return true
end


return previewRenderer