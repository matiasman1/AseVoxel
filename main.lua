-- main.lua
local modelViewer = require("modelViewer")

function init(plugin)
  -- Create a single command for AseVoxel
  plugin:newCommand{
    id = "AseVoxel",
    title = "AseVoxel",
    group = "edit_transform", -- Put in edit menu
    onclick = function()
      if not app.activeSprite then
        app.alert("Please open a sprite first!")
        return
      end
      modelViewer.openModelViewer()
    end
  }
  
  print("AseVoxel extension initialized!")
end

function exit(plugin)
  -- Cleanup, if needed.
  print("AseVoxel extension unloaded")
end
