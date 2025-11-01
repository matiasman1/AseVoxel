-- Test file for shader stack system
-- This file can be run to verify shader loading and basic functionality

local function testShaderStack()
  print("========================================")
  print("AseVoxel Shader Stack Test")
  print("========================================")
  
  -- Load shader stack module
  local shaderStack = dofile("render/shader_stack.lua")
  
  if not shaderStack then
    print("ERROR: Failed to load shader_stack.lua")
    return false
  end
  
  print("\n✓ shader_stack.lua loaded successfully")
  
  -- Load shaders
  print("\nAttempting to load shaders...")
  shaderStack.loadShaders()
  
  -- List loaded shaders
  print("\n--- Registered Lighting Shaders ---")
  for id, shader in pairs(shaderStack.registry.lighting) do
    print("  - " .. id .. " (" .. (shader.info.name or "Unknown") .. ")")
  end
  
  print("\n--- Registered FX Shaders ---")
  for id, shader in pairs(shaderStack.registry.fx) do
    print("  - " .. id .. " (" .. (shader.info.name or "Unknown") .. ")")
  end
  
  -- Test basic shader
  print("\n--- Testing Basic Light Shader ---")
  local basicShader = shaderStack.getShader("basicLight", "lighting")
  if basicShader then
    print("✓ Basic Light shader found")
    print("  Name: " .. basicShader.info.name)
    print("  Description: " .. basicShader.info.description)
    print("  Parameters: " .. #basicShader.paramSchema)
    
    -- List parameters
    for i, param in ipairs(basicShader.paramSchema) do
      print("    - " .. param.name .. " (" .. param.type .. "): " .. (param.label or ""))
    end
  else
    print("✗ Basic Light shader not found")
  end
  
  -- Test dynamic shader
  print("\n--- Testing Dynamic Light Shader ---")
  local dynamicShader = shaderStack.getShader("dynamicLight", "lighting")
  if dynamicShader then
    print("✓ Dynamic Light shader found")
    print("  Parameters: " .. #dynamicShader.paramSchema)
  else
    print("✗ Dynamic Light shader not found")
  end
  
  -- Test FX shaders
  print("\n--- Testing FX Shaders ---")
  local fxShaders = {"faceshade", "iso", "faceshadeCamera"}
  for _, shaderId in ipairs(fxShaders) do
    local shader = shaderStack.getShader(shaderId, "fx")
    if shader then
      print("✓ " .. shaderId .. " (" .. shader.info.name .. ")")
    else
      print("✗ " .. shaderId .. " not found")
    end
  end
  
  -- Test shader stack execution (with mock data)
  print("\n--- Testing Shader Stack Execution ---")
  local mockShaderData = {
    faces = {
      {
        voxel = {x=0, y=0, z=0},
        face = "top",
        normal = {x=0, y=1, z=0},
        color = {r=255, g=128, b=64, a=255}
      },
      {
        voxel = {x=0, y=0, z=0},
        face = "front",
        normal = {x=0, y=0, z=1},
        color = {r=128, g=255, b=64, a=255}
      }
    },
    camera = {
      position = {x=0, y=0, z=10},
      direction = {x=0, y=0, z=-1}
    },
    middlePoint = {x=0, y=0, z=0},
    width = 400,
    height = 400,
    voxelSize = 2.0
  }
  
  local stackConfig = {
    lighting = {
      {
        id = "basicLight",
        enabled = true,
        params = {
          lightIntensity = 80,
          shadeIntensity = 40
        },
        inputFrom = "base_color"
      }
    },
    fx = {}
  }
  
  local result = shaderStack.execute(mockShaderData, stackConfig)
  
  if result and result.faces then
    print("✓ Shader stack executed successfully")
    print("  Output faces: " .. #result.faces)
    print("  Face 1 color: R=" .. result.faces[1].color.r .. 
          " G=" .. result.faces[1].color.g .. 
          " B=" .. result.faces[1].color.b)
  else
    print("✗ Shader stack execution failed")
  end
  
  print("\n========================================")
  print("Test Complete")
  print("========================================")
  
  return true
end

-- Run test if executed directly
if arg and arg[0] then
  testShaderStack()
end

return {
  test = testShaderStack
}
