-- geometry_pipeline.lua
-- Shared geometry transformation and processing utilities
-- Used by both canvas_renderer and rasterizer for consistency

local geometryPipeline = {}

-- Calculate bounding box and middle point of voxel model
function geometryPipeline.calculateModelBounds(voxelModel)
  if not voxelModel or #voxelModel == 0 then
    return {
      minX = 0, maxX = 0,
      minY = 0, maxY = 0,
      minZ = 0, maxZ = 0,
      middlePoint = {x = 0, y = 0, z = 0},
      sizeX = 0, sizeY = 0, sizeZ = 0
    }
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
    minX = minX, maxX = maxX,
    minY = minY, maxY = maxY,
    minZ = minZ, maxZ = maxZ,
    middlePoint = {
      x = (minX + maxX) / 2,
      y = (minY + maxY) / 2,
      z = (minZ + maxZ) / 2
    },
    sizeX = maxX - minX + 1,
    sizeY = maxY - minY + 1,
    sizeZ = maxZ - minZ + 1
  }
end

-- Apply Euler rotation (Z*Y*X order) to a 3D point
function geometryPipeline.rotatePoint(x, y, z, xRotDeg, yRotDeg, zRotDeg)
  local xr = math.rad(xRotDeg or 0)
  local yr = math.rad(yRotDeg or 0)
  local zr = math.rad(zRotDeg or 0)
  
  local cx, sx = math.cos(xr), math.sin(xr)
  local cy, sy = math.cos(yr), math.sin(yr)
  local cz, sz = math.cos(zr), math.sin(zr)
  
  -- Z rotation
  local x1 = x * cz - y * sz
  local y1 = x * sz + y * cz
  local z1 = z
  
  -- Y rotation
  local x2 = x1 * cy + z1 * sy
  local y2 = y1
  local z2 = -x1 * sy + z1 * cy
  
  -- X rotation
  local x3 = x2
  local y3 = y2 * cx - z2 * sx
  local z3 = y2 * sx + z2 * cx
  
  return x3, y3, z3
end

-- Project 3D point to 2D screen space
function geometryPipeline.projectPoint(x, y, z, params)
  local width = params.width or 400
  local height = params.height or 400
  local scale = params.scale or 1.0
  local orthogonal = params.orthogonal or false
  local fovDegrees = params.fovDegrees or 45
  local offsetX = params.offsetX or 0
  local offsetY = params.offsetY or 0
  
  -- Apply scale
  local sx = x * scale
  local sy = y * scale
  local sz = z * scale
  
  -- Project to 2D
  local screenX, screenY
  if orthogonal then
    screenX = sx
    screenY = -sy  -- Flip Y for screen coordinates
  else
    -- Perspective projection
    local fovRad = math.rad(fovDegrees)
    local distance = 100
    local projScale = distance * math.tan(fovRad / 2)
    local perspective = projScale / (distance + sz)
    screenX = sx * perspective
    screenY = -sy * perspective
  end
  
  -- Center on canvas and apply offset
  screenX = screenX + width / 2 + offsetX
  screenY = screenY + height / 2 + offsetY
  
  return screenX, screenY, sz
end

-- Transform a 3D point through full pipeline: center, rotate, project
function geometryPipeline.transformPoint(x, y, z, middlePoint, params)
  -- Center around middle point
  local dx = x - middlePoint.x
  local dy = y - middlePoint.y
  local dz = z - middlePoint.z
  
  -- Rotate
  local rx, ry, rz = geometryPipeline.rotatePoint(
    dx, dy, dz,
    params.xRotation or 0,
    params.yRotation or 0,
    params.zRotation or 0
  )
  
  -- Project to screen
  local sx, sy, depth = geometryPipeline.projectPoint(rx, ry, rz, params)
  
  return {x = sx, y = sy, z = depth}
end

-- Define cube face geometry (vertices relative to voxel center)
geometryPipeline.CUBE_FACES = {
  front = {
    name = "front",
    normal = {x = 0, y = 0, z = 1},
    vertices = {
      {x = -0.5, y = -0.5, z = 0.5},
      {x = 0.5, y = -0.5, z = 0.5},
      {x = 0.5, y = 0.5, z = 0.5},
      {x = -0.5, y = 0.5, z = 0.5},
    }
  },
  back = {
    name = "back",
    normal = {x = 0, y = 0, z = -1},
    vertices = {
      {x = 0.5, y = -0.5, z = -0.5},
      {x = -0.5, y = -0.5, z = -0.5},
      {x = -0.5, y = 0.5, z = -0.5},
      {x = 0.5, y = 0.5, z = -0.5},
    }
  },
  right = {
    name = "right",
    normal = {x = 1, y = 0, z = 0},
    vertices = {
      {x = 0.5, y = -0.5, z = 0.5},
      {x = 0.5, y = -0.5, z = -0.5},
      {x = 0.5, y = 0.5, z = -0.5},
      {x = 0.5, y = 0.5, z = 0.5},
    }
  },
  left = {
    name = "left",
    normal = {x = -1, y = 0, z = 0},
    vertices = {
      {x = -0.5, y = -0.5, z = -0.5},
      {x = -0.5, y = -0.5, z = 0.5},
      {x = -0.5, y = 0.5, z = 0.5},
      {x = -0.5, y = 0.5, z = -0.5},
    }
  },
  top = {
    name = "top",
    normal = {x = 0, y = 1, z = 0},
    vertices = {
      {x = -0.5, y = 0.5, z = 0.5},
      {x = 0.5, y = 0.5, z = 0.5},
      {x = 0.5, y = 0.5, z = -0.5},
      {x = -0.5, y = 0.5, z = -0.5},
    }
  },
  bottom = {
    name = "bottom",
    normal = {x = 0, y = -1, z = 0},
    vertices = {
      {x = -0.5, y = -0.5, z = -0.5},
      {x = 0.5, y = -0.5, z = -0.5},
      {x = 0.5, y = -0.5, z = 0.5},
      {x = -0.5, y = -0.5, z = 0.5},
    }
  },
}

-- Generate face quads for a single voxel with shading applied
function geometryPipeline.generateVoxelFaces(voxel, middlePoint, params, shadingModule, fxStack, lighting)
  local faces = {}
  
  for faceName, faceDef in pairs(geometryPipeline.CUBE_FACES) do
    -- Transform vertices to screen space
    local screenVerts = {}
    local avgDepth = 0
    
    for _, relVert in ipairs(faceDef.vertices) do
      local worldX = voxel.x + relVert.x
      local worldY = voxel.y + relVert.y
      local worldZ = voxel.z + relVert.z
      
      local transformed = geometryPipeline.transformPoint(worldX, worldY, worldZ, middlePoint, params)
      table.insert(screenVerts, transformed)
      avgDepth = avgDepth + transformed.z
    end
    avgDepth = avgDepth / #screenVerts
    
    -- Apply shading to get face color
    local faceColor = voxel.color
    if shadingModule and params.shadingMode then
      if params.shadingMode == "Basic" then
        faceColor = shadingModule.applyBasicShading(voxel.color, faceName, {
          basicShadeIntensity = params.basicShadeIntensity or 50,
          basicLightIntensity = params.basicLightIntensity or 50
        })
      elseif params.shadingMode == "Stack" and fxStack then
        faceColor = shadingModule.applyFxStack(voxel.color, faceName, fxStack, voxel)
      elseif params.shadingMode == "Dynamic" and lighting then
        faceColor = shadingModule.applyDynamicLighting(voxel.color, faceName, faceDef.normal, lighting, voxel)
      end
    end
    
    table.insert(faces, {
      verts = screenVerts,
      color = faceColor,
      depth = avgDepth,
      name = faceName,
      normal = faceDef.normal
    })
  end
  
  return faces
end

-- Sort faces by depth using painter's algorithm (back to front)
function geometryPipeline.sortFacesByDepth(faces)
  table.sort(faces, function(a, b)
    return a.depth > b.depth
  end)
  return faces
end

-- Check if a screen-space quad is within canvas bounds (for culling)
function geometryPipeline.isQuadVisible(verts, width, height, margin)
  margin = margin or 10
  local minX, maxX = math.huge, -math.huge
  local minY, maxY = math.huge, -math.huge
  
  for _, v in ipairs(verts) do
    if v.x < minX then minX = v.x end
    if v.x > maxX then maxX = v.x end
    if v.y < minY then minY = v.y end
    if v.y > maxY then maxY = v.y end
  end
  
  -- Check if completely outside canvas bounds (with margin)
  if maxX < -margin or minX > width + margin then return false end
  if maxY < -margin or minY > height + margin then return false end
  
  return true
end

return geometryPipeline
