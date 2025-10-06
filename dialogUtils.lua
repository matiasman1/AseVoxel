-- Dialog creation and management utilities
local previewUtils = require("previewUtils")
local previewRenderer = require("previewRenderer")
local mathUtils = require("mathUtils")
local rotation = require("rotation")
local fileUtils = require("fileUtils")

local dialogUtils = {}

-- Open a help dialog with usage instructions
function dialogUtils.openHelpDialog()
  local dlg = Dialog("Voxel Model Viewer Help")
  
  -- Instead of using \n inside a single label (Aseprite Dialogs don't support it),
  -- split into multiple labels and newrows.
  dlg:label{ id = "helpLine1", text = "Voxel Model Viewer" }
  dlg:newrow()
  dlg:label{ id = "helpLine2", text = "" } -- spacing
  dlg:newrow()
  dlg:label{ id = "helpLine3", text = "Controls:" }
  dlg:newrow()
  dlg:label{ id = "helpLine4", text = "- Left-click and drag to use trackball rotation" }
  dlg:newrow()
  dlg:label{ id = "helpLine5", text = "- Middle-click and drag for orbit camera" }
  dlg:newrow()
  dlg:label{ id = "helpLine6", text = "- Use View Controls dialog for precise angle control" }
  dlg:newrow()
  dlg:label{ id = "helpLine7", text = "" } -- spacing
  dlg:newrow()
  dlg:label{ id = "helpLine8", text = "Layers:" }
  dlg:newrow()
  dlg:label{ id = "helpLine9", text = "- Each visible layer becomes a Z-level in the 3D model" }
  dlg:newrow()
  dlg:label{ id = "helpLine10", text = "- Top layers appear in front (lower Z value)" }
  dlg:newrow()
  dlg:label{ id = "helpLine11", text = "- Non-transparent pixels become voxels" }
  dlg:newrow()
  dlg:label{ id = "helpLine12", text = "" } -- spacing
  dlg:newrow()
  dlg:label{ id = "helpLine13", text = "Animation:" }
  dlg:newrow()
  dlg:label{ id = "helpLine14", text = "- Create animations along X, Y, Z axes or Pitch/Yaw/Roll" }
  dlg:newrow()
  dlg:label{ id = "helpLine15", text = "- Set the number of frames and it creates a GIF" }
  dlg:newrow()
  dlg:label{ id = "helpLine16", text = "" } -- spacing
  dlg:newrow()
  dlg:label{ id = "helpLine17", text = "Export:" }
  dlg:newrow()
  dlg:label{ id = "helpLine18", text = "- Export to OBJ, PLY, or STL formats" }
  dlg:newrow()
  dlg:label{ id = "helpLine19", text = "- Materials and colors preserved in OBJ format" }
  dlg:newrow()
  dlg:label{ id = "helpLine20", text = "" } -- spacing
  dlg:newrow()
  dlg:label{ id = "helpLine21", text = "For more help visit:" }
  dlg:newrow()
  dlg:label{ id = "helpLine22", text = "https://github.com/mattiasgustavsson/voxelmaker" }

  dlg:button{
    id = "closeBtn",
    text = "Close",
    focus = true,
    onclick = function()
      dlg:close()
    end
  }
  
  dlg:show{ wait = true }
end

-- Opens the animation dialog
function dialogUtils.openAnimationDialog(viewParams, modelDimensions, voxelModel, canvasSize, scaleLevel)
  local dlg = Dialog("Create Animation")

  -- show current Euler orientation as reference
  dlg:label{
    id = "currentEulerLabel",
    text = string.format(
      "Current position (Euler)  X: %.0f  Y: %.0f  Z: %.0f",
      (viewParams.xRotation or viewParams.eulerX or 0),
      (viewParams.yRotation or viewParams.eulerY or 0),
      (viewParams.zRotation or viewParams.eulerZ or 0)
    )
  }
  dlg:separator()
  
  dlg:combobox{
    id = "animationAxis",
    label = "Rotation Axis:",
    options = { "X", "Y", "Z", "Pitch", "Yaw", "Roll" },
    option = "Y"
  }
  
  dlg:combobox{
    id = "animationSteps",
    label = "Steps:",
    options = {"4", "5", "6", "8", "9", "10", "12", "15", "18", "20", "24", "30", "36", "40", "45", "60", "72", "90", "120", "180", "360" },
    option = "36",
    onchange = function()
      -- Convert from string to number
      local steps = tonumber(dlg.data.animationSteps)
      if not steps then steps = 36 end
      local degreesPerStep = 360 / steps
      
      -- Make sure we use the same calculation method here as in the export function
      local frameDuration = math.ceil(1440 / steps)
      
      dlg:modify{
        id = "stepsInfo",
        text = string.format("%d° per step, %d ms/frame", 
                          degreesPerStep, 
                          frameDuration)
      }
    end
  }
  
  dlg:label{
    id = "stepsInfo",
    text = "10.0° per step, 40 ms/frame"
  }
  
  dlg:separator()
  
  dlg:button{
    id = "createButton",
    text = "Create Animation",
    focus = true,
    onclick = function()
      local params = {
        xRotation = viewParams.xRotation,
        yRotation = viewParams.yRotation,
        zRotation = viewParams.zRotation,
        depthPerspective = viewParams.depthPerspective,
        orthogonalView = viewParams.orthogonalView,
        animationAxis = dlg.data.animationAxis,
        animationSteps = dlg.data.animationSteps,
        canvasSize = canvasSize,
        scaleLevel = scaleLevel,
        shadingMode = viewParams.shadingMode,  -- preserve shading
        fxStack = viewParams.fxStack,          -- pass current fx stack
        lighting = viewParams.lighting         -- pass dynamic lighting
      }
      
      previewUtils.createAnimation(voxelModel, modelDimensions, params)
      dlg:close()
    end
  }
  
  dlg:button{
    id = "cancelButton",
    text = "Cancel",
    onclick = function()
      dlg:close()
    end
  }
  
  dlg:show{ wait = true }
end

-- Opens the export model dialog
function dialogUtils.openExportModelDialog(voxelModel)
  if not voxelModel or #voxelModel == 0 then
    app.alert("No model to export!")
    return
  end

  local dlg = Dialog("Export Voxel Model")
  local sprite = app.activeSprite
  
  -- Default export options
  local exportOptions = {
    format = "obj",
    includeTexture = true,
    scaleModel = 1.0,
    optimizeMesh = true
  }
  
  -- Canvas size calculation - make it appropriate for scale 10
  local canvasWidth = 160  -- Fixed canvas size for export preview
  local canvasHeight = 160
  
  -- Generate a small preview of the model
  local middlePoint = previewRenderer.calculateMiddlePoint(voxelModel)
  
  -- Render a small preview for the dialog
  local params = {
    x = 315, -- Default rotation angles for preview
    y = 324,
    z = 29,
    depth = 50,
    orthogonal = false,
    pixelSize = 2,
    canvasSize = canvasWidth
  }
  
  local previewImage = previewRenderer.renderVoxelModel(voxelModel, params)
  
  -- Create the dialog UI
  -- Preview section
  dlg:canvas{
    id = "previewCanvas",
    width = canvasWidth,
    height = canvasHeight,
    onpaint = function(ev)
      local ctx = ev.context
      
      if previewImage then
        -- Calculate center position to place the preview image
        local offsetX = (canvasWidth - previewImage.width) / 2
        local offsetY = (canvasHeight - previewImage.height) / 2
        
        -- Draw the preview image centered in the canvas
        ctx:drawImage(previewImage, offsetX, offsetY)
      else
        -- Draw placeholder text
        ctx:fillText("Loading preview...", canvasWidth/2-50, canvasHeight/2)
      end
    end
  }
  
  -- Replace single multiline label with multiple labels/newrows
  dlg:label{
    id = "modelInfo_title",
    text = "Model Information:"
  }
  dlg:newrow()
  dlg:label{
    id = "modelInfo_count",
    text = "Voxel count: " .. #voxelModel
  }
  dlg:newrow()
  dlg:label{
    id = "modelInfo_dims",
    text = "Dimensions: " .. middlePoint.sizeX .. "×" .. 
            middlePoint.sizeY .. "×" .. middlePoint.sizeZ .. " voxels"
  }
  
  -- Export format options
  dlg:separator{ text = "Export Format" }
  
  dlg:combobox{
    id = "format",
    label = "Format:",
    option = "obj",
    options = { "obj", "ply", "stl" },
    onchange = function()
      exportOptions.format = dlg.data.format
      
      -- Enable/disable texture options based on format
      local enableTexture = dlg.data.format == "obj"
      dlg:modify{
        id = "includeTexture",
        enabled = enableTexture
      }
    end
  }
  
  dlg:check{
    id = "includeTexture",
    label = "Include Material:",
    selected = true,
    onchange = function()
      exportOptions.includeTexture = dlg.data.includeTexture
    end
  }
  
  -- Model manipulation options
  dlg:separator{ text = "Model Options" }
  
  dlg:number{
    id = "scaleModel",
    label = "Scale:",
    text = "1.0",
    decimals = 2,
    onchange = function()
      exportOptions.scaleModel = dlg.data.scaleModel
    end
  }
  
  dlg:check{
    id = "optimizeMesh",
    label = "Optimize Mesh",
    selected = true,
    onchange = function()
      exportOptions.optimizeMesh = dlg.data.optimizeMesh
    end
  }
  
  -- File location
  dlg:separator{ text = "Export Location" }
  
  local defaultPath = ""
  local defaultFilename = "model.obj"
  
  -- Try to get default path and filename from current sprite
  if sprite and sprite.filename then
    defaultPath = app.fs.filePath(sprite.filename)
    defaultFilename = app.fs.fileName(sprite.filename):gsub("%.%w+$", "") .. ".obj"
  end
  
  dlg:entry{
    id = "filename",
    label = "Filename:",
    text = defaultFilename,
    focus = true
  }
  
  dlg:button{
    id = "browseButton",
    text = "Select Location...",
    onclick = function()
      -- Create a simple directory browser dialog
      local browseDlg = Dialog("Select Directory")
      local currentDir = defaultPath
      if currentDir == "" then
        currentDir = app.fs.currentPath
      end
      
      browseDlg:label{
        id = "dirLabel",
        text = "Current directory: \n" .. currentDir
      }
      
      browseDlg:entry{
        id = "dirName",
        text = currentDir,
        label = "Path:",
        focus = true
      }
      
      browseDlg:button{
        id = "selectBtn",
        text = "Select",
        focus = true,
        onclick = function()
          local newPath = browseDlg.data.dirName
          if app.fs.isDirectory(newPath) then
            defaultPath = newPath
            -- Update the filename to reflect the full path
            dlg:modify{
              id = "filename",
              text = app.fs.joinPath(defaultPath, app.fs.fileName(dlg.data.filename))
            }
            browseDlg:close()
          else
            app.alert("Invalid directory path")
          end
        end
      }
      
      browseDlg:button{
        id = "cancelBtn",
        text = "Cancel",
        onclick = function()
          browseDlg:close()
        end
      }
      
      browseDlg:show{wait=true}
    end
  }
  
  -- Action buttons
  dlg:separator()
  
  dlg:button{
    id = "exportButton",
    text = "Export",
    focus = true,
    onclick = function()
      -- Get export path
      local filename = dlg.data.filename
      if not filename:match("%.%w+$") then
        filename = filename .. "." .. exportOptions.format
      end
      
      -- Check if path is absolute without using isPathSeparator
      local isAbsolutePath = false
      if app.fs and app.fs.pathSeparator then
        isAbsolutePath = filename:sub(1, 1) == app.fs.pathSeparator or filename:sub(2, 2) == ":"
      else
        -- Fallback method: check for Unix-style or Windows-style paths
        isAbsolutePath = (filename:sub(1, 1) == "/" or filename:sub(1, 1) == "\\" or 
                          (filename:len() > 1 and filename:sub(2, 2) == ":"))
      end
      
      local filePath
      if isAbsolutePath then
        -- Absolute path
        filePath = filename
      else
        -- Relative path - use a safe path joining method
        if app.fs and app.fs.joinPath then
          filePath = app.fs.joinPath(defaultPath, filename)
        else
          -- Simple fallback path joining
          local separator = "/"
          if defaultPath ~= "" and not defaultPath:match("[\\/]$") then
            defaultPath = defaultPath .. separator
          end
          filePath = defaultPath .. filename
        end
      end
      
      -- Export the model based on selected format
      local success = false
      if exportOptions.format == "obj" then
        success = previewRenderer.exportOBJ(voxelModel, filePath)
      else
        -- For other formats, use generic export
        success = fileUtils.exportGeneric(voxelModel, filePath, exportOptions)
      end
      
      if success then
        app.alert("3D model exported successfully to:\n" .. filePath)
        dlg:close()
      else
        app.alert("Failed to export 3D model!")
      end
    end
  }
  
  dlg:button{
    id = "cancelButton",
    text = "Cancel",
    onclick = function()
      dlg:close()
    end
  }
  
  dlg:show{ wait = false }
end

return dialogUtils
