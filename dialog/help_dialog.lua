-- help_dialog.lua
-- Help and documentation dialog

local helpDialog = {}

function helpDialog.open()
  local dlg = Dialog("Voxel Model Maker Help")
  
  -- Title
  dlg:label{id = "titleLabel", text = "Voxel Model Maker for Aseprite"}
  dlg:newrow()
  dlg:label{text = ""} -- Empty line for spacing
  dlg:newrow()
  
  -- Basic usage
  dlg:label{text = "How to use:"}
  dlg:newrow()
  dlg:label{text = "1. Create a sprite with multiple layers"}
  dlg:newrow()
  dlg:label{text = "2. Each pixel represents one voxel in 3D space"}
  dlg:newrow()
  dlg:label{text = "3. X,Y positions in the layer define X,Y in the 3D model"}
  dlg:newrow()
  dlg:label{text = "4. Layer position defines Z depth in the 3D model"}
  dlg:newrow()
  dlg:label{text = "5. Use mouse to control the view:"}
  dlg:newrow()
  dlg:label{text = "   - Left-click drag: Pan preview"}
  dlg:newrow()
  dlg:label{text = "   - Middle-click drag: Rotate model"}
  dlg:newrow()
  dlg:label{text = "   - Scroll wheel: Change scale"}
  dlg:newrow()
  dlg:label{text = ""} -- Empty line for spacing
  dlg:newrow()
  
  -- Rotation controls - updated to include new modes
  dlg:label{text = "Rotation Controls:"}
  dlg:newrow()
  dlg:label{text = "• Euler Mode: Direct control of individual angles"}
  dlg:newrow()
  dlg:label{text = "• Absolute Mode: Rotations apply in model space"}
  dlg:newrow()
  dlg:label{text = "• Relative Mode: Rotations apply in camera space"}
  dlg:newrow()
  dlg:label{text = ""} -- Empty line for spacing
  dlg:newrow()
  
  -- Animation options
  dlg:label{text = "Animation Options:"}
  dlg:newrow()
  dlg:label{text = "• X/Y/Z: Model-space incremental rotations"}
  dlg:newrow()
  dlg:label{text = "• Euler X/Y/Z: Direct angle increments"}
  dlg:newrow()
  dlg:label{text = "• Pitch/Yaw/Roll: Camera-space rotations"}
  dlg:newrow()
  dlg:label{text = ""} -- Empty line for spacing
  dlg:newrow()
  
  -- Additional instructions
  dlg:label{text = "6. Use the View Controls panel for precise adjustments"}
  dlg:newrow()
  dlg:label{text = "7. Export as OBJ/STL/PLY to use in 3D software"}
  dlg:newrow()
  dlg:label{text = ""} -- Empty line for spacing
  dlg:newrow()
  dlg:label{text = "Tip: Top layers are at the front (Z=1), bottom layers at back"}
  
  dlg:button{
    id = "closeButton",
    text = "Close",
    onclick = function()
      dlg:close()
    end
  }
  
  dlg:show{ wait = true }
end

return helpDialog
