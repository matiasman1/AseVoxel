-- mesh_renderer.lua
-- Renders a triangle mesh with flat, unshaded colors (no lighting).
-- Matches camera/rotation semantics of previewRenderer: Euler Z*Y*X, orthographic/perspective with FOV and perspectiveScaleRef.
-- Dependencies: Loaded via AseVoxel.mathUtils namespace

local meshRenderer = {}

-- Access mathUtils through global namespace (loaded by loader.lua)
local function getMathUtils()
  return AseVoxel.mathUtils
end

local function rotationComponents(xDeg, yDeg, zDeg)
  local xr, yr, zr = math.rad(xDeg or 0), math.rad(yDeg or 0), math.rad(zDeg or 0)
  local cx, sx = math.cos(xr), math.sin(xr)
  local cy, sy = math.cos(yr), math.sin(yr)
  local cz, sz = math.cos(zr), math.sin(zr)
  return cx,sx, cy,sy, cz,sz
end

local function computeMeshBounds(vertices)
  local minX, maxX = math.huge, -math.huge
  local minY, maxY = math.huge, -math.huge
  local minZ, maxZ = math.huge, -math.huge
  for _, v in ipairs(vertices) do
    if v[1] < minX then minX = v[1] end
    if v[1] > maxX then maxX = v[1] end
    if v[2] < minY then minY = v[2] end
    if v[2] > maxY then maxY = v[2] end
    if v[3] < minZ then minZ = v[3] end
    if v[3] > maxZ then maxZ = v[3] end
  end
  return {minX=minX,maxX=maxX,minY=minY,maxY=maxY,minZ=minZ,maxZ=maxZ}
end

local function computeMiddlePointAndSize(vertices)
  local b = computeMeshBounds(vertices)
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

-- Triangle rasterizer: scanline fill using half-open rule on Y, inclusive on X
local function drawTriangle(image, p0, p1, p2, color)
  -- Sort by y
  if p1.y < p0.y then p0, p1 = p1, p0 end
  if p2.y < p0.y then p0, p2 = p2, p0 end
  if p2.y < p1.y then p1, p2 = p2, p1 end

  local function edgeIntersections(y, a, b)
    if a.y == b.y then return nil end
    if y < a.y or y >= b.y then return nil end
    local t = (y - a.y) / (b.y - a.y)
    return a.x + (b.x - a.x) * t
  end

  local y0 = math.max(0, math.floor(p0.y))
  local y2 = math.min(image.height-1, math.ceil(p2.y))

  for y = y0, y2 do
    local scanY = y + 0.5
    local xs = {}

    local x01 = edgeIntersections(scanY, p0, p1)
    local x12 = edgeIntersections(scanY, p1, p2)
    local x02 = edgeIntersections(scanY, p0, p2)
    if x01 then xs[#xs+1] = x01 end
    if x12 then xs[#xs+1] = x12 end
    if x02 then xs[#xs+1] = x02 end

    if #xs >= 2 then
      table.sort(xs)
      for k = 1, #xs, 2 do
        local x0 = xs[k]
        local x1 = xs[k+1] or x0
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

-- Renders mesh with flat color per triangle, ignoring any lighting/shading fields in params
-- params: width, height, xRotation, yRotation, zRotation, scale, orthogonal, fovDegrees, perspectiveScaleRef, backgroundColor
function meshRenderer.render(mesh, params)
  -- NEW: Start profiling for mesh mode
  local enableProfiling = params.enableProfiling
  local profiler = AseVoxel.utils.performance_profiler
  if enableProfiling and profiler then
    profiler.startProfile("meshRenderer")
    profiler.mark("total")
    profiler.mark("setup")
  end
  
  local width  = params.width or 200
  local height = params.height or 200
  local img = Image(width, height, ColorMode.RGB)
  if params.backgroundColor then
    img:clear(params.backgroundColor)
  else
    img:clear(Color(0,0,0,0))
  end
  if not mesh or not mesh.vertices or not mesh.triangles or #mesh.triangles == 0 then
    if enableProfiling and profiler then
      profiler.measure("setup")
      profiler.measure("total")
    end
    return img
  end

  local centerX, centerY = width/2, height/2
  local xRot = params.xRotation or 0
  local yRot = params.yRotation or 0
  local zRot = params.zRotation or 0
  local cx,sx, cy,sy, cz,sz = rotationComponents(xRot, yRot, zRot)

  local mp = computeMiddlePointAndSize(mesh.vertices)
  local maxDimension = math.max(mp.sizeX, mp.sizeY, mp.sizeZ)
  local diag = math.sqrt(mp.sizeX*mp.sizeX + mp.sizeY*mp.sizeY + mp.sizeZ*mp.sizeZ)
  local modelRadiusApprox = 0.5 * diag

  -- Choose scale and camera consistent with previewRenderer
  local orthogonal = params.orthogonal and true or false
  local fovDeg = params.fovDegrees
  local cameraDistance
  local focalLength
  local cameraPos
  local voxelSize -- pixels per world unit at reference depth

  local maxAllowed = math.min(width, height) * 0.9
  local baseTargetPix = params.scale or params.scaleLevel or 1.0
  if baseTargetPix <= 0 then baseTargetPix = 1 end

  if (not orthogonal) and fovDeg then
    -- Perspective path with same calibration semantics as previewRenderer
    fovDeg = math.max(5, math.min(75, fovDeg))
    local warpT = (fovDeg - 5) / (75 - 5)
    local amplified = warpT ^ (1/3)
    local BASE_NEAR  = 1.2
    local FAR_EXTRA  = 45.0
    cameraDistance = maxDimension * (BASE_NEAR + (1 - amplified)^2 * FAR_EXTRA)
    cameraPos = { x = mp.x, y = mp.y, z = mp.z + cameraDistance }
    local fovRad = math.rad(fovDeg)
    focalLength = (height/2) / math.tan(fovRad/2)

    -- Determine rotated Z extents to compute reference depth based on perspectiveScaleRef
    local function rotZ(x,y,z)
      -- translate to center
      local rx, ry, rz = x - mp.x, y - mp.y, z - mp.z
      -- X
      local y2 = ry * cx - rz * sx
      local z2 = ry * sx + rz * cx
      ry, rz = y2, z2
      -- Y
      local x2 = rx * cy + rz * sy
      local z3 = -rx * sy + rz * cy
      rx, rz = x2, z3
      -- Z rotation doesn't affect Z component magnitude used for depth
      local _x3 = rx * cz - ry * sz
      local _y3 = rx * sz + ry * cz
      return mp.z + z3
    end
    local b = mp._bounds
    local corners = {
      {b.minX,b.minY,b.minZ},{b.maxX,b.minY,b.minZ},{b.minX,b.maxY,b.minZ},{b.maxX,b.maxY,b.minZ},
      {b.minX,b.minY,b.maxZ},{b.maxX,b.minY,b.maxZ},{b.minX,b.maxY,b.maxZ},{b.maxX,b.maxY,b.maxZ}
    }
    local zMin, zMax = math.huge, -math.huge
    for _,c in ipairs(corners) do
      local rzWorld = rotZ(c[1], c[2], c[3])
      if rzWorld < zMin then zMin = rzWorld end
      if rzWorld > zMax then zMax = rzWorld end
    end
    local depthBack  = math.max(0.001, cameraPos.z - zMin)
    local depthFront = math.max(0.001, cameraPos.z - zMax)
    local depthMiddle= math.max(0.001, cameraDistance)

    local refMode = params.perspectiveScaleRef or "middle"
    local depthRef = depthMiddle
    if refMode == "front" or refMode == "Front" then
      depthRef = depthFront
    elseif refMode == "back" or refMode == "Back" then
      depthRef = depthBack
    end

    voxelSize = baseTargetPix * (depthRef / focalLength)
    if voxelSize * maxDimension > maxAllowed then
      voxelSize = maxAllowed / maxDimension
    end
  else
    -- Orthographic path
    cameraDistance = maxDimension * 5
    cameraPos = { x = mp.x, y = mp.y, z = mp.z + cameraDistance }
    voxelSize = math.max(1, baseTargetPix)
    if voxelSize * maxDimension > maxAllowed then
      voxelSize = maxAllowed / maxDimension
    end
  end

  if enableProfiling and profiler then
    profiler.measure("setup")
    profiler.mark("vertex_transform")
  end

  -- Project all vertices once, store projected coords and depths
  local proj = {} -- array of { x, y, depth } by vertex index
  for i, v in ipairs(mesh.vertices) do
    local x = v[1] - mp.x
    local y = v[2] - mp.y
    local z = v[3] - mp.z
    -- X rotation
    local y2 = y * cx - z * sx
    local z2 = y * sx + z * cx
    y, z = y2, z2
    -- Y rotation
    local x2 = x * cy + z * sy
    local z3 = -x * sy + z * cy
    x, z = x2, z3
    -- Z rotation
    local x3 = x * cz - y * sz
    local y3 = x * sz + y * cz
    x, y = x3, y3

    local worldZ = mp.z + z
    local sxp, syp
    local depth = cameraPos.z - worldZ
    if not orthogonal and focalLength then
      local scale = focalLength / math.max(0.001, depth)
      sxp = centerX + (x * voxelSize) * scale
      syp = centerY + (y * voxelSize) * scale
    else
      sxp = centerX + x * voxelSize
      syp = centerY + y * voxelSize
    end
    proj[i] = { x = sxp, y = syp, depth = depth }
  end

  if enableProfiling and profiler then
    profiler.measure("vertex_transform")
    profiler.mark("triangle_sort")
  end

  -- Build triangle list with average depth and sort far->near (Painter's)
  local drawList = {}
  for _, t in ipairs(mesh.triangles) do
    local p1 = proj[t[1]]
    local p2 = proj[t[2]]
    local p3 = proj[t[3]]
    if p1 and p2 and p3 then
      local avgDepth = (p1.depth + p2.depth + p3.depth) / 3
      drawList[#drawList+1] = { p1=p1, p2=p2, p3=p3, depth=avgDepth, color=t.color }
    end
  end
  table.sort(drawList, function(a,b) return a.depth > b.depth end) -- far first

  if enableProfiling and profiler then
    profiler.measure("triangle_sort")
    profiler.mark("draw_triangles")
  end

  for _, it in ipairs(drawList) do
    local c = it.color or {r=255,g=255,b=255,a=255}
    local col = Color(c.r or 255, c.g or 255, c.b or 255, c.a or 255)
    drawTriangle(img, it.p1, it.p2, it.p3, col)
  end

  if enableProfiling and profiler then
    profiler.measure("draw_triangles")
    profiler.measure("total")
  end

  return img
end

return meshRenderer