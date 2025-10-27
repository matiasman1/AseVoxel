-- export_stl.lua
-- STL file export for voxel models

local exportSTL = {}

--------------------------------------------------------------------------------
-- Export the voxel model to STL format
-- @param voxels The voxel model to export
-- @param filePath Output file path for the STL file
-- @param options Optional export options
-- @return Boolean indicating success or failure
--------------------------------------------------------------------------------
function exportSTL.export(voxels, filePath, options)
  options = options or {}

  local scaleModel = options.scaleModel or 1.0
  
  -- Ensure file has .stl extension
  if not filePath:lower():match("%.stl$") then
    filePath = filePath .. ".stl"
  end
  
  -- Compute Y inversion bounds (fixes minY nil error)
  local minY, maxY = math.huge, -math.huge
  for _, v in ipairs(voxels) do
    if v.y < minY then minY = v.y end
    if v.y > maxY then maxY = v.y end
  end
  local heightSpan = maxY - minY
  
  -- Open file for writing
  local stlFile = io.open(filePath, "w")
  if not stlFile then
    return false, "Could not open file for writing"
  end
  
  -- Write STL header
  stlFile:write("solid voxelmodel\n")
  
  -- Process each voxel and output as triangles
  for _, voxel in ipairs(voxels) do
    -- Create cube vertices (scaled and Y-inverted)
    local x = voxel.x * scaleModel
    local invY = (heightSpan - (voxel.y - minY)) + minY
    local y = invY * scaleModel
    local z = voxel.z * scaleModel
    local size = scaleModel
    
    -- Define 8 vertices of the cube
    local v1 = {x, y, z}
    local v2 = {x + size, y, z}
    local v3 = {x + size, y, z + size}
    local v4 = {x, y, z + size}
    local v5 = {x, y + size, z}
    local v6 = {x + size, y + size, z}
    local v7 = {x + size, y + size, z + size}
    local v8 = {x, y + size, z + size}
    
    -- 12 triangles (2 per cube face)
    local triangles = {
      -- Bottom face
      {v1, v2, v3, normal = {0, -1, 0}},
      {v3, v4, v1, normal = {0, -1, 0}},
      -- Top face
      {v5, v8, v7, normal = {0, 1, 0}},
      {v7, v6, v5, normal = {0, 1, 0}},
      -- Front face
      {v4, v3, v7, normal = {0, 0, 1}},
      {v7, v8, v4, normal = {0, 0, 1}},
      -- Back face
      {v1, v5, v6, normal = {0, 0, -1}},
      {v6, v2, v1, normal = {0, 0, -1}},
      -- Left face
      {v1, v4, v8, normal = {-1, 0, 0}},
      {v8, v5, v1, normal = {-1, 0, 0}},
      -- Right face
      {v3, v2, v6, normal = {1, 0, 0}},
      {v6, v7, v3, normal = {1, 0, 0}},
    }

    for _, tri in ipairs(triangles) do
      local n = tri.normal
      stlFile:write(string.format("  facet normal %.6f %.6f %.6f\n", n[1], n[2], n[3]))
      stlFile:write("    outer loop\n")
      for i = 1, 3 do
        stlFile:write(string.format("      vertex %.6f %.6f %.6f\n",
          tri[i][1], tri[i][2], tri[i][3]))
      end
      stlFile:write("    endloop\n  endfacet\n")
    end
  end
  
  -- Write STL footer
  stlFile:write("endsolid voxelmodel\n")
  stlFile:close()
  return true
end

return exportSTL
