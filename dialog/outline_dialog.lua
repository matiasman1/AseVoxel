-- outline_dialog.lua
-- Outline settings dialog

local outlineDialog = {}

function outlineDialog.open(viewParams, updateCallback)
  local dlg = Dialog("Outline Settings")
  
  dlg:combobox{
    id = "outlineMode",
    label = "Outline Mode:",
    options = {"Model (Fast)", "Voxels (Slow)"},
    option = (viewParams.outlineSettings and viewParams.outlineSettings.mode == "voxels") 
             and "Voxels (Slow)" or "Model (Fast)"
  }
  
  dlg:combobox{
    id = "place",
    label = "Position:",
    options = {"inside", "outside", "center"},
    option = (viewParams.outlineSettings and viewParams.outlineSettings.place) or "outside"
  }
  
  dlg:combobox{
    id = "matrix",
    label = "Shape:",
    options = {"circle", "square", "horizontal", "vertical"},
    option = (viewParams.outlineSettings and viewParams.outlineSettings.matrix) or "circle"
  }
  
  dlg:color{
    id = "color",
    label = "Color:",
    color = (viewParams.outlineSettings and viewParams.outlineSettings.color) or Color(0, 0, 0)
  }
  
  dlg:button{
    id = "ok",
    text = "OK",
    onclick = function()
      -- Create outline settings
      viewParams.outlineSettings = {
        mode = (dlg.data.outlineMode == "Voxels (Slow)") and "voxels" or "model",
        place = dlg.data.place,
        matrix = dlg.data.matrix,
        color = dlg.data.color
      }
      
      -- Enable outline
      viewParams.enableOutline = true
      
      -- Update preview
      updateCallback()
      
      dlg:close()
    end
  }
  
  dlg:button{
    id = "cancel",
    text = "Cancel",
    onclick = function()
      dlg:close()
    end
  }
  
  dlg:show{ wait = true }
end

return outlineDialog
