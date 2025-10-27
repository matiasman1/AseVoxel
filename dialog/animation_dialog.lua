-- animation_dialog.lua
-- Animation creation dialog

local animationDialog = {}

-- Lazy loaders
local function getDialogManager()
  return AseVoxel.dialog.dialog_manager
end

local function getPreviewUtils()
  return AseVoxel.previewUtils
end

function animationDialog.open(viewParams, voxelModel, modelDimensions)
  if not voxelModel or #voxelModel == 0 then
    app.alert("No model to animate!")
    return
  end
  
  local dlg = Dialog("Create Animation")

  -- Display current Euler orientation (start pose reference for animation)
  local fovText = (viewParams.orthogonalView and "Ortho")
                  or string.format("FOV: %.0f°", viewParams.fovDegrees or 45)
  dlg:label{
    id = "currentEulerLabel",
    text = string.format(
      "Current position (Euler)  X: %.0f  Y: %.0f  Z: %.0f   Scale: %.0f%%   %s",
      (viewParams.xRotation or viewParams.eulerX or 0),
      (viewParams.yRotation or viewParams.eulerY or 0),
      (viewParams.zRotation or viewParams.eulerZ or 0),
      (viewParams.scaleLevel or 1) * 100,
      fovText
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
    options = {"4", "6", "8", "9", "10", "12", "15", "18", "20", "24", "30", "36", "40", "45", "60", "72", "90", "120", "180", "360" },
    option = "36",
    onchange = function()
      -- Convert from string to number
      local steps = tonumber(dlg.data.animationSteps) or 36
      local total = tonumber(dlg.data.totalRotation) or 360
      local degreesPerStep = total / steps
      
      -- Make sure we use the same calculation method here as in the export function
      local frameDuration = math.ceil(1440 / steps)
      
      dlg:modify{
        id = "stepsInfo",
        text = string.format("%.2f° per step, %d ms/frame", 
                          degreesPerStep, 
                          frameDuration)
      }
    end
  }
  
  -- New: Start Angle and Total Rotation sliders for partial loops
  dlg:slider{
    id = "startAngle",
    label = "Start:",
    min = 0, 
    max = 359, 
    value = 0,
    onchange = function()
      local steps = tonumber(dlg.data.animationSteps) or 36
      local total = tonumber(dlg.data.totalRotation) or 360
      local dps = total / steps
      dlg:modify{
        id = "stepsInfo", 
        text = string.format("%.2f° per step, %d ms/frame", 
                           dps, 
                           math.ceil(1440 / steps))
      }
    end
  }
  
  dlg:slider{
    id = "totalRotation",
    label = "Span:",
    min = 1, 
    max = 360, 
    value = 360,
    onchange = function()
      local steps = tonumber(dlg.data.animationSteps) or 36
      local total = tonumber(dlg.data.totalRotation) or 360
      local dps = total / steps
      dlg:modify{
        id = "stepsInfo", 
        text = string.format("%.2f° per step, %d ms/frame", 
                           dps, 
                           math.ceil(1440 / steps))
      }
    end
  }
  
  dlg:label{
    id = "stepsInfo",
    text = "10.00° per step, 40 ms/frame"
  }

  -- Update current Euler label live if dialog opened after rotations changed
  pcall(function()
    dlg:modify{
      id = "currentEulerLabel",
      text = string.format(
        "Current position (Euler)  X: %.0f  Y: %.0f  Z: %.0f   Scale: %.0f%%   %s",
        (viewParams.xRotation or viewParams.eulerX or 0),
        (viewParams.yRotation or viewParams.eulerY or 0),
        (viewParams.zRotation or viewParams.eulerZ or 0),
        (viewParams.scaleLevel or 1) * 100,
        ((viewParams.orthogonalView and "Ortho") or string.format("FOV: %.0f°", viewParams.fovDegrees or 45))
      )
    }
  end)

  -- Add a scale label to show the current scale that will be used
  dlg:label{
    id = "scaleInfo",
    text = string.format("Current scale: %.0f%%", viewParams.scaleLevel * 100)
  }
  
  dlg:separator()
  
  dlg:button{
    id = "createButton",
    text = "Create Animation",
    focus = true,
    onclick = function()
      local dialogManager = getDialogManager()
      local previewUtils = getPreviewUtils()
      
      local params = {
        xRotation = viewParams.xRotation,
        yRotation = viewParams.yRotation,
        zRotation = viewParams.zRotation,
        depthPerspective = viewParams.depthPerspective,
        orthogonalView = viewParams.orthogonalView,
        animationAxis = dlg.data.animationAxis,
        animationSteps = dlg.data.animationSteps,
        startAngle = dlg.data.startAngle or 0,
        totalRotation = dlg.data.totalRotation or 360,
        canvasSize = viewParams.canvasSize or 200,
        scaleLevel = viewParams.scaleLevel or 1.0,
        rotationMatrix = dialogManager.getCurrentRotationMatrix(),
        fxStack = viewParams.fxStack,          -- pass current stack
        shadingMode = viewParams.shadingMode,  -- preserve shading mode if any
        lighting = viewParams.lighting,        -- pass dynamic lighting for shaded animation
        viewDir = {0,0,1},                     -- camera-fixed lighting direction
        keepCameraLight = true,
        fovDegrees = viewParams.fovDegrees,    -- pass through current FOV for perspective animations
        -- NEW: pass the current perspective reference selection to animation renderer
        perspectiveScaleRef = viewParams.perspectiveScaleRef
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

return animationDialog
