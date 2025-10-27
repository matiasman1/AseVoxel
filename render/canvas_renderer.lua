-- canvas_renderer.lua
-- Direct canvas rendering using GraphicsContext path APIs
-- Bypasses offscreen Image rasterization for performance and quality

local canvasRenderer = {}

-- Access dependencies through global namespace
local function getRotation()
  return AseVoxel.math.rotation
end

local function getMeshBuilder()
  return AseVoxel.render.mesh_builder
end

local function getFaceVisibility()
  return AseVoxel.render.face_visibility
end

local function getShading()
  return AseVoxel.render.shading
end

local function getFxStack()
  return AseVoxel.render.fx_stack
end

-- Helper: Draw a single quad face using GraphicsContext paths
local function drawQuadPath(ctx, p1, p2, p3, p4, color)
  -- Ensure color is a proper Color object
  local finalColor
  if type(color) == "table" and not color.red then
    -- Convert {r, g, b, a} table to Color object
    finalColor = Color(
      color.r or color[1] or 255,
      color.g or color[2] or 255,
      color.b or color[3] or 255,
      color.a or color[4] or 255
    )
  else
    finalColor = color
  end
  
  ctx.color = finalColor
  ctx.blendMode = BlendMode.NORMAL
  
  ctx:beginPath()
  ctx:moveTo(p1.x, p1.y)
  ctx:lineTo(p2.x, p2.y)
  ctx:lineTo(p3.x, p3.y)
  ctx:lineTo(p4.x, p4.y)
  ctx:closePath()
  ctx:fill()
end

-- Helper: Draw quad with optional outline
local function drawQuadWithOutline(ctx, p1, p2, p3, p4, fillColor, outlineColor, outlineWidth)
  -- Ensure fillColor is a proper Color object
  local finalFillColor
  if type(fillColor) == "table" and not fillColor.red then
    finalFillColor = Color(
      fillColor.r or fillColor[1] or 255,
      fillColor.g or fillColor[2] or 255,
      fillColor.b or fillColor[3] or 255,
      fillColor.a or fillColor[4] or 255
    )
  else
    finalFillColor = fillColor
  end
  
  ctx.color = finalFillColor
  ctx.blendMode = BlendMode.NORMAL
  ctx:beginPath()
  ctx:moveTo(p1.x, p1.y)
  ctx:lineTo(p2.x, p2.y)
  ctx:lineTo(p3.x, p3.y)
  ctx:lineTo(p4.x, p4.y)
  ctx:closePath()
  ctx:fill()
  
  -- Draw outline if specified
  if outlineColor and outlineWidth and outlineWidth > 0 then
    -- Convert outline color too
    local finalOutlineColor
    if type(outlineColor) == "table" and not outlineColor.red then
      finalOutlineColor = Color(
        outlineColor.r or outlineColor[1] or 0,
        outlineColor.g or outlineColor[2] or 0,
        outlineColor.b or outlineColor[3] or 0,
        outlineColor.a or outlineColor[4] or 255
      )
    else
      finalOutlineColor = outlineColor
    end
    ctx.color = finalOutlineColor
    ctx.strokeWidth = outlineWidth
    ctx:stroke()
  end
end

-- Calculate middle point for camera positioning
local function calculateMiddlePoint(voxelModel)
  if not voxelModel or #voxelModel == 0 then
    return {x = 0, y = 0, z = 0}
  end
  
  local minX, maxX = math.huge, -math.huge
  local minY, maxY = math.huge, -math.huge
  local minZ, maxZ = math.huge, -math.huge
  
  for _, voxel in ipairs(voxelModel) do
    if voxel.x < minX then minX = voxel.x end
    if voxel.x > maxX then maxX = voxel.x end
    if voxel.y < minY then minY = voxel.y end
    if voxel.y > maxY then maxY = voxel.y end
    if voxel.z < minZ then minZ = voxel.z end
    if voxel.z > maxZ then maxZ = voxel.z end
  end
  
  return {
    x = (minX + maxX) / 2,
    y = (minY + maxY) / 2,
    z = (minZ + maxZ) / 2
  }
end

-- Transform a 3D point to 2D screen space
-- IMPORTANT: Scale is applied AFTER projection to preserve perspective
local function transformPoint(x, y, z, middlePoint, rotation, scale, width, height, orthogonal, fovDegrees, offsetX, offsetY)
  -- Center around middle point
  local dx = x - middlePoint.x
  local dy = y - middlePoint.y
  local dz = z - middlePoint.z
  
  -- Apply rotation (using Euler angles Z*Y*X order)
  local xr, yr, zr = math.rad(rotation.x or 0), math.rad(rotation.y or 0), math.rad(rotation.z or 0)
  local cx, sx = math.cos(xr), math.sin(xr)
  local cy, sy = math.cos(yr), math.sin(yr)
  local cz, sz = math.cos(zr), math.sin(zr)
  
  -- Z rotation
  local x1 = dx * cz - dy * sz
  local y1 = dx * sz + dy * cz
  local z1 = dz
  
  -- Y rotation
  local x2 = x1 * cy + z1 * sy
  local y2 = y1
  local z2 = -x1 * sy + z1 * cy
  
  -- X rotation
  local x3 = x2
  local y3 = y2 * cx - z2 * sx
  local z3 = y2 * sx + z2 * cx
  
  -- Project to 2D first, THEN apply scale
  local screenX, screenY
  if orthogonal then
    screenX = x3 * scale
    screenY = -y3 * scale  -- Flip Y for screen coordinates
  else
    -- Perspective projection (like aseSlab)
    local fovRad = math.rad(fovDegrees or 45)
    local distance = 100  -- projection distance
    local factor = distance / (distance - z3)
    screenX = x3 * (factor * scale)
    screenY = -y3 * (factor * scale)
  end
  
  -- Center on canvas and apply offset
  screenX = screenX + width / 2 + (offsetX or 0)
  screenY = screenY + height / 2 + (offsetY or 0)
  
  return {x = screenX, y = screenY, z = z3}
end

-- Generate face quads for a voxel
local function generateVoxelFaces(voxel, middlePoint, rotation, voxelSize, width, height, orthogonal, fovDegrees, offsetX, offsetY, shadingMode, fxStack, lighting, params)
  local faces = {}
  
  -- Define cube faces (6 faces, 4 vertices each)
  local faceDefinitions = {
    {name = "front",  normal = {x=0, y=0, z=1},  vertices = {
      {x = voxel.x - 0.5, y = voxel.y - 0.5, z = voxel.z + 0.5},
      {x = voxel.x + 0.5, y = voxel.y - 0.5, z = voxel.z + 0.5},
      {x = voxel.x + 0.5, y = voxel.y + 0.5, z = voxel.z + 0.5},
      {x = voxel.x - 0.5, y = voxel.y + 0.5, z = voxel.z + 0.5},
    }},
    {name = "back",   normal = {x=0, y=0, z=-1}, vertices = {
      {x = voxel.x + 0.5, y = voxel.y - 0.5, z = voxel.z - 0.5},
      {x = voxel.x - 0.5, y = voxel.y - 0.5, z = voxel.z - 0.5},
      {x = voxel.x - 0.5, y = voxel.y + 0.5, z = voxel.z - 0.5},
      {x = voxel.x + 0.5, y = voxel.y + 0.5, z = voxel.z - 0.5},
    }},
    {name = "right",  normal = {x=1, y=0, z=0},  vertices = {
      {x = voxel.x + 0.5, y = voxel.y - 0.5, z = voxel.z + 0.5},
      {x = voxel.x + 0.5, y = voxel.y - 0.5, z = voxel.z - 0.5},
      {x = voxel.x + 0.5, y = voxel.y + 0.5, z = voxel.z - 0.5},
      {x = voxel.x + 0.5, y = voxel.y + 0.5, z = voxel.z + 0.5},
    }},
    {name = "left",   normal = {x=-1, y=0, z=0}, vertices = {
      {x = voxel.x - 0.5, y = voxel.y - 0.5, z = voxel.z - 0.5},
      {x = voxel.x - 0.5, y = voxel.y - 0.5, z = voxel.z + 0.5},
      {x = voxel.x - 0.5, y = voxel.y + 0.5, z = voxel.z + 0.5},
      {x = voxel.x - 0.5, y = voxel.y + 0.5, z = voxel.z - 0.5},
    }},
    {name = "top",    normal = {x=0, y=1, z=0},  vertices = {
      {x = voxel.x - 0.5, y = voxel.y + 0.5, z = voxel.z + 0.5},
      {x = voxel.x + 0.5, y = voxel.y + 0.5, z = voxel.z + 0.5},
      {x = voxel.x + 0.5, y = voxel.y + 0.5, z = voxel.z - 0.5},
      {x = voxel.x - 0.5, y = voxel.y + 0.5, z = voxel.z - 0.5},
    }},
    {name = "bottom", normal = {x=0, y=-1, z=0}, vertices = {
      {x = voxel.x - 0.5, y = voxel.y - 0.5, z = voxel.z - 0.5},
      {x = voxel.x + 0.5, y = voxel.y - 0.5, z = voxel.z - 0.5},
      {x = voxel.x + 0.5, y = voxel.y - 0.5, z = voxel.z + 0.5},
      {x = voxel.x - 0.5, y = voxel.y - 0.5, z = voxel.z + 0.5},
    }},
  }
  
  -- Get shading module
  local shading = getShading()
  
  for _, faceDef in ipairs(faceDefinitions) do
    -- Transform vertices to screen space
    local screenVerts = {}
    local avgDepth = 0
    for _, vert in ipairs(faceDef.vertices) do
      local transformed = transformPoint(
        vert.x, vert.y, vert.z,
        middlePoint, rotation, voxelSize, width, height,
        orthogonal, fovDegrees, offsetX, offsetY
      )
      table.insert(screenVerts, transformed)
      avgDepth = avgDepth + transformed.z
    end
    avgDepth = avgDepth / #screenVerts
    
    -- Calculate face color based on shading mode
    local faceColor = voxel.color
    if shading and shadingMode then
      -- Build params for shadeFaceColor (unified shading function)
      local shadingParams = {
        shadingMode = shadingMode,
        basicShadeIntensity = params.basicShadeIntensity or 50,
        basicLightIntensity = params.basicLightIntensity or 50,
        fxStack = fxStack,
        lighting = lighting,
        xRotation = rotation.x,
        yRotation = rotation.y,
        zRotation = rotation.z,
      }
      
      faceColor = shading.shadeFaceColor(faceDef.name, voxel.color, shadingParams)
    end
    
    table.insert(faces, {
      verts = screenVerts,
      color = faceColor,
      depth = avgDepth,
      name = faceDef.name
    })
  end
  
  return faces
end

-- Main rendering function: draw voxel model directly to GraphicsContext
function canvasRenderer.renderVoxelModel(ctx, voxelModel, params)
  local startTime = os.clock()
  
  if not ctx then
    return {success = false, error = "No GraphicsContext provided"}
  end
  
  if not voxelModel or #voxelModel == 0 then
    return {success = true, faceCount = 0, renderTimeMs = 0}
  end
  
  print("[canvas_renderer] Rendering " .. #voxelModel .. " voxels in DirectCanvas mode")
  
  -- Extract parameters
  local width = params.width or ctx.width or 400
  local height = params.height or ctx.height or 400
  local scale = params.scale or 1.0
  local orthogonal = params.orthogonal or false
  local fovDegrees = params.fovDegrees or 45
  local offsetX = params.offsetX or 0
  local offsetY = params.offsetY or 0
  local enableAntialiasing = params.enableAntialiasing ~= false  -- Default true
  local enableOutline = params.enableOutline or false
  local outlineColor = params.outlineColor
  local outlineWidth = params.outlineWidth or 1
  local shadingMode = params.shadingMode
  local fxStack = params.fxStack
  local lighting = params.lighting
  
  local rotation = {
    x = params.xRotation or 0,
    y = params.yRotation or 0,
    z = params.zRotation or 0
  }
  
  -- Calculate middle point for camera centering
  local middlePoint = calculateMiddlePoint(voxelModel)
  
  -- Calculate model dimensions
  local minX, maxX = math.huge, -math.huge
  local minY, maxY = math.huge, -math.huge
  local minZ, maxZ = math.huge, -math.huge
  for _, v in ipairs(voxelModel) do
    if v.x < minX then minX = v.x end
    if v.x > maxX then maxX = v.x end
    if v.y < minY then minY = v.y end
    if v.y > maxY then maxY = v.y end
    if v.z < minZ then minZ = v.z end
    if v.z > maxZ then maxZ = v.z end
  end
  local modelWidth = maxX - minX + 1
  local modelHeight = maxY - minY + 1
  local modelDepth = maxZ - minZ + 1
  local maxDimension = math.max(modelWidth, modelHeight, modelDepth)
  
  -- Calculate proper voxel size (match preview_renderer logic)
  -- Allow fractional scales (don't clamp to 1)
  local voxelSize = scale
  local maxAllowed = math.min(width, height) * 0.9
  if voxelSize * maxDimension > maxAllowed then
    voxelSize = maxAllowed / maxDimension
  end
  
  print("[canvas_renderer] Model dims: " .. modelWidth .. "x" .. modelHeight .. "x" .. modelDepth .. 
        ", voxelSize: " .. voxelSize .. ", scale: " .. scale)
  
  -- Generate all face quads
  local allFaces = {}
  for _, voxel in ipairs(voxelModel) do
    local voxelFaces = generateVoxelFaces(
      voxel, middlePoint, rotation, voxelSize, width, height,
      orthogonal, fovDegrees, offsetX, offsetY,
      shadingMode, fxStack, lighting, params
    )
    for _, face in ipairs(voxelFaces) do
      table.insert(allFaces, face)
    end
  end
  
  -- Sort faces by depth (painter's algorithm: back to front)
  table.sort(allFaces, function(a, b)
    return a.depth > b.depth
  end)
  
  print("[canvas_renderer] Generated " .. #allFaces .. " faces total")
  if #allFaces > 0 then
    if #allFaces[1].verts > 0 then
      local v = allFaces[1].verts[1]
      print("[canvas_renderer] First vertex: x=" .. v.x .. ", y=" .. v.y .. ", z=" .. v.z)
    end
  end
  
  -- Set rendering properties
  ctx.antialias = enableAntialiasing
  
  -- Draw all faces
  local faceCount = 0
  for _, face in ipairs(allFaces) do
    if #face.verts == 4 then
      if enableOutline then
        drawQuadWithOutline(
          ctx,
          face.verts[1], face.verts[2], face.verts[3], face.verts[4],
          face.color, outlineColor, outlineWidth
        )
      else
        drawQuadPath(
          ctx,
          face.verts[1], face.verts[2], face.verts[3], face.verts[4],
          face.color
        )
      end
      faceCount = faceCount + 1
    end
  end
  
  print("[canvas_renderer] Drew " .. faceCount .. " faces")
  
  local renderTimeMs = (os.clock() - startTime) * 1000
  
  return {
    success = true,
    faceCount = faceCount,
    renderTimeMs = renderTimeMs
  }
end

-- Prepare (pre-calculate) faces for fast drawing
-- This should be called when voxelModel or transform parameters change
-- Returns a table that can be passed to drawPreparedFaces()
function canvasRenderer.prepareFaces(voxelModel, params)
  local startTime = os.clock()
  
  local width = params.width or 400
  local height = params.height or 300
  local scale = params.scale or 1.0
  local orthogonal = params.orthogonal or false
  local fovDegrees = params.fovDegrees or 45
  local offsetX = params.offsetX or 0
  local offsetY = params.offsetY or 0
  local shadingMode = params.shadingMode
  local fxStack = params.fxStack
  local lighting = params.lighting
  local enableOutline = params.enableOutline or false
  local outlineColor = params.outlineColor
  local outlineWidth = params.outlineWidth or 1
  
  local rotation = {
    x = params.xRotation or 0,
    y = params.yRotation or 0,
    z = params.zRotation or 0
  }
  
  -- Calculate middle point for camera centering
  local middlePoint = calculateMiddlePoint(voxelModel)
  
  -- Calculate model dimensions
  local minX, maxX = math.huge, -math.huge
  local minY, maxY = math.huge, -math.huge
  local minZ, maxZ = math.huge, -math.huge
  for _, v in ipairs(voxelModel) do
    if v.x < minX then minX = v.x end
    if v.x > maxX then maxX = v.x end
    if v.y < minY then minY = v.y end
    if v.y > maxY then maxY = v.y end
    if v.z < minZ then minZ = v.z end
    if v.z > maxZ then maxZ = v.z end
  end
  local modelWidth = maxX - minX + 1
  local modelHeight = maxY - minY + 1
  local modelDepth = maxZ - minZ + 1
  local maxDimension = math.max(modelWidth, modelHeight, modelDepth)
  
  -- Calculate proper voxel size
  local voxelSize = scale
  local maxAllowed = math.min(width, height) * 0.9
  if voxelSize * maxDimension > maxAllowed then
    voxelSize = maxAllowed / maxDimension
  end
  
  -- Generate all face quads
  local allFaces = {}
  for _, voxel in ipairs(voxelModel) do
    local voxelFaces = generateVoxelFaces(
      voxel, middlePoint, rotation, voxelSize, width, height,
      orthogonal, fovDegrees, offsetX, offsetY,
      shadingMode, fxStack, lighting, params
    )
    for _, face in ipairs(voxelFaces) do
      table.insert(allFaces, face)
    end
  end
  
  -- Sort faces by depth (painter's algorithm: back to front)
  table.sort(allFaces, function(a, b)
    return a.depth > b.depth
  end)
  
  local prepareTimeMs = (os.clock() - startTime) * 1000
  
  return {
    faces = allFaces,
    enableOutline = enableOutline,
    outlineColor = outlineColor,
    outlineWidth = outlineWidth,
    prepareTimeMs = prepareTimeMs,
    faceCount = #allFaces
  }
end

-- Draw pre-calculated faces (fast, for onpaint callback)
-- This should be called in onpaint with faces prepared by prepareFaces()
function canvasRenderer.drawPreparedFaces(ctx, preparedData, enableAntialiasing)
  local startTime = os.clock()
  
  -- Set rendering properties
  ctx.antialias = (enableAntialiasing ~= false)
  
  -- Draw all faces
  local faceCount = 0
  for _, face in ipairs(preparedData.faces) do
    if #face.verts == 4 then
      if preparedData.enableOutline then
        drawQuadWithOutline(
          ctx,
          face.verts[1], face.verts[2], face.verts[3], face.verts[4],
          face.color,
          preparedData.outlineColor,
          preparedData.outlineWidth
        )
      else
        drawQuadPath(
          ctx,
          face.verts[1], face.verts[2], face.verts[3], face.verts[4],
          face.color
        )
      end
      faceCount = faceCount + 1
    end
  end
  
  local drawTimeMs = (os.clock() - startTime) * 1000
  
  return {
    success = true,
    faceCount = faceCount,
    drawTimeMs = drawTimeMs
  }
end

return canvasRenderer
