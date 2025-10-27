-- export_dialog.lua
-- Create an export dialog using native file dialog and export commands
-- Dependencies: Loaded via AseVoxel.io and AseVoxel.render namespaces

local ExportDialog = {}

-- Access dependencies through global namespace (loaded by loader.lua)
local function getFileUtils()
  return AseVoxel.io.file_common
end

local function getPreviewRenderer()
  return AseVoxel.render.preview_renderer
end

-- Create an export dialog using native file dialog and export commands
ExportDialog.show = function(sprite, options)
  options = options or {}
  
  local dlg = Dialog("Export Options")
  local voxelModel = nil
  local previewImage = nil
  local sprite = app.activeSprite

  -- Ensure viewParams is defined (may be provided via options) to avoid nil errors
  local viewParams = options.viewParams or { scaleLevel = 1.0 }
  
  -- Default export options
  local exportOptions = {
    format = "obj",
    includeTexture = true,
    scaleModel = 1.0,
    optimizeMesh = true
  }
  
  -- Canvas size calculation - make it appropriate for scale 10
  local canvasWidth = 160  -- Set fixed canvas size similar to 0.1.4 for scale 10
  local canvasHeight = 160 -- Set fixed canvas size similar to 0.1.4 for scale 10
  
  -- Generate a small preview of the model
  local function generatePreview()
    if not sprite then return end
    -- Regenerate from the active sprite so the dialog reflects current layers/changes
    local previewRenderer = getPreviewRenderer()
    local regenerated = previewRenderer.generateVoxelModel(sprite)
    if not regenerated or #regenerated == 0 then
      dlg:modify{ id = "modelInfo_count", text = "Voxel count: (No voxels found)" }
      dlg:modify{ id = "modelInfo_dims",  text = "" }
      previewImage = nil
      dlg:repaint()
      return
    end
    voxelModel = regenerated
    local currentMiddlePoint = previewRenderer.calculateMiddlePoint(voxelModel)

    -- Always use orthogonal and scale 300 for export preview, with stack lighting
    local params = {
      x = 315,
      y = 324,
      z = 29,
      fovDegrees = 45,           -- Neutral FOV, not used since orthogonal=true
      orthogonal = true,         -- Always orthogonal for preview
      scale = 3.0,               -- 300% scale
      shadingMode = "Stack",     -- Use stack lighting for export preview
      fxStack = viewParams.fxStack,
      pixelSize = 1,
      canvasSize = canvasWidth,
      zoomFactor = 0.25
    }
    previewImage = previewRenderer.renderVoxelModel(voxelModel, params)

    dlg:modify{ id = "modelInfo_count", text = "Voxel count: " .. #voxelModel }
    dlg:modify{ id = "modelInfo_dims",
                text = "Dimensions: " .. currentMiddlePoint.sizeX .. "×" ..
                       currentMiddlePoint.sizeY .. "×" .. currentMiddlePoint.sizeZ .. " voxels" }
    dlg:repaint()
  end

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
  
  dlg:label{ id = "modelInfo_title", text = "Model Information:" }
  dlg:newrow()
  dlg:label{ id = "modelInfo_count", text = "Loading..." }
  dlg:newrow()
  dlg:label{ id = "modelInfo_dims",  text = "" }
  
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
    id = "usePixelScale",
    label = "Use Pixel Scale",
    selected = true,
    onchange = function()
      exportOptions.exportAtScale = dlg.data.usePixelScale and viewParams.scaleLevel or nil
      
      -- Update display to show effective scale
      if dlg.data.usePixelScale then
        dlg:modify{
          id = "scaleInfo",
          text = string.format("Effective scale: %.0f%% (%.2f units per voxel)", 
                              viewParams.scaleLevel * 100, viewParams.scaleLevel)
        }
      else
        dlg:modify{
          id = "scaleInfo",
          text = "Using custom scale factor"
        }
      end
    end
  }
  
  dlg:label{
    id = "scaleInfo",
    text = string.format("Effective scale: %.0f%% (%.2f units per voxel)", 
                        viewParams.scaleLevel * 100, viewParams.scaleLevel)
  }
  
  dlg:check{
    id = "optimizeMesh",
    label = "Optimize Mesh",
    selected = true,
    onchange = function()
      exportOptions.optimizeMesh = dlg.data.optimizeMesh
    end
  }
  
  -- Outline options
  dlg:separator{ text="Outline Options" }
  dlg:check{
    id = "enableOutlines",
    label = "Enable Outlines",
    selected = not (options and options.enableOutlines == false)
  }
  dlg:color{
    id = "outlineColor",
    label = "Outline Color:",
    color = (options and options.outlineColor) or Color{ r = 0, g = 0, b = 0 }
  }
  dlg:slider{
    id = "outlineWidth",
    label = "Outline Width:",
    min = 1,
    max = 3,
    value = (options and options.outlineWidth) or 1
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
      if not voxelModel or #voxelModel == 0 then
        app.alert("No voxels to export!")
        return
      end
      
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
      local previewRenderer = getPreviewRenderer()
      local fileUtils = getFileUtils()
      if exportOptions.format == "obj" then
        success = previewRenderer.exportOBJ(voxelModel, filePath, exportOptions)
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
  
  -- Show dialog and generate preview without waiting
  dlg:show{ wait = false }
  generatePreview()
  -- Lightweight refresh to pick up quick edits, then regenerate preview
  app.refresh()
  generatePreview()
 end

return ExportDialog