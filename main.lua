-- main.lua
-- AseVoxel Extension Bootstrap
-- Entry point for the Aseprite extension

-- Discover the path to this script using debug.getinfo
local scriptInfo = debug.getinfo(1, "S")
local scriptSource = scriptInfo.source
if scriptSource:sub(1, 1) == "@" then
  scriptSource = scriptSource:sub(2)
end
local scriptPath = scriptSource:match("^(.+[/\\])[^/\\]+$") or "./"

-- Load the central module loader
local AseVoxel = dofile(scriptPath .. "loader.lua")

-- Extension initialization function (called by Aseprite)
function init(plugin)
  print("[AseVoxel] Initializing extension...")
  
  -- Create the main menu command
  plugin:newCommand{
    id = "AseVoxel",
    title = "AseVoxel Viewer",
    group = "view_extras",
    onclick = function()
      if not app.activeSprite then
        app.alert("Please open a sprite first!")
        return
      end
      
      -- Call the main viewer (Phase 3 refactored entry point)
      AseVoxel.viewer.open()
    end
  }
  
  print("[AseVoxel] Extension initialized successfully!")
end

-- Extension cleanup function (called by Aseprite on unload)
function exit(plugin)
  print("[AseVoxel] Extension unloaded")
end
