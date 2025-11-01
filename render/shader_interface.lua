-- Common protocol for all shaders (lighting + FX)

local shaderInterface = {}

-- Shader metadata structure
shaderInterface.ShaderInfo = {
  id = "unique_shader_id",           -- e.g. "dynamicLight"
  name = "Human Readable Name",      -- e.g. "Dynamic Lighting"
  version = "1.0.0",
  author = "Author Name",
  category = "lighting",             -- "lighting" or "fx"
  complexity = "O(n)",               -- Performance hint: O(1), O(n), O(n²), etc.
  description = "What this shader does",
  
  -- Feature flags
  supportsNative = true,             -- Has C++ implementation
  requiresGeometry = true,           -- Needs neighbor voxel data
  requiresDepth = false,             -- Needs camera distance
  requiresNormals = true,            -- Needs face normals
  
  -- Input/output capabilities
  inputs = {
    "base_color",                    -- Can read original voxel color
    "previous_shader",               -- Can read previous shader output
    "geometry",                      -- Can read voxel positions
    "normals"                        -- Can read face normals
  },
  outputs = {
    "color",                         -- Produces color output
    "alpha"                          -- Produces alpha output
  }
}

-- Shader parameter schema (for auto-UI generation)
shaderInterface.ParamSchema = {
  {
    name = "intensity",
    type = "slider",                 -- slider, color, vector, bool, choice, material
    min = 0,
    max = 100,
    default = 50,
    label = "Intensity",
    tooltip = "Controls shader strength"
  },
  -- ... more parameters
}

-- Main shader interface
function shaderInterface.process(shaderData, params)
  -- shaderData structure:
  -- {
  --   faces = { {voxel={x,y,z}, face="top", normal={x,y,z}, color={r,g,b,a}, ...}, ... },
  --   voxels = { {x,y,z, color={r,g,b,a}, neighbors={...}}, ... },
  --   camera = {position={x,y,z}, rotation={x,y,z}, direction={x,y,z}, fov=45, ...},
  --   modelBounds = {minX, maxX, minY, maxY, minZ, maxZ},
  --   middlePoint = {x, y, z},
  --   width = 400,
  --   height = 400,
  --   voxelSize = 2.5
  -- }
  --
  -- params: table of shader-specific parameters
  --
  -- Returns: modified shaderData (with updated face colors)
  
  return shaderData
end

-- Optional: Custom UI builder (overrides auto-generated UI)
function shaderInterface.buildUI(dlg, params, onChange)
  -- dlg: Aseprite Dialog object
  -- params: current parameter values
  -- onChange: callback(newParams) when user changes values
  
  -- If not implemented, UI is auto-generated from ParamSchema
end

return shaderInterface
