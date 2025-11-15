-- dialogueManager.lua
local previewRenderer = require("previewRenderer")
local mathUtils = require("mathUtils")
local rotation = require("rotation")
local fileUtils = require("fileUtils")
local previewUtils = require("previewUtils")
local dialogueManager = {}

-- Current state to keep track of controls across dialogs
dialogueManager.controlsDialog = nil
dialogueManager.exportDialog = nil
dialogueManager.mainDialog = nil
dialogueManager.previewDialog = nil

-- Store the current rotation matrix globally for co-dependent behavior
dialogueManager.currentRotationMatrix = mathUtils.identity()

-- Add a flag to prevent recursive updates
dialogueManager.isUpdatingControls = false
-- Add a global update lock with timestamp to prevent UI cascades
dialogueManager.updateLock = false
dialogueManager.lastUpdateTime = 0
dialogueManager.updateThrottleMs = 0 -- let viewerCore handle mouse throttling

-- Safe update function that prevents recursive calls and throttles updates
function dialogueManager.safeUpdate(viewParams, updateCallback)
  local currentTime = os.clock() * 1000
  if dialogueManager.updateLock or 
     (currentTime - dialogueManager.lastUpdateTime) < dialogueManager.updateThrottleMs then
    return
  end
  dialogueManager.updateLock = true
  dialogueManager.lastUpdateTime = currentTime
  pcall(function()
    updateCallback(viewParams)
  end)
  dialogueManager.updateLock = false
end


--------------------------------------------------------------------------------
-- Controls Dialog Management - REDESIGNED WITH ROTATION MODES
--------------------------------------------------------------------------------
function dialogueManager.openControlsDialog(parentDlg, viewParams, updateCallback)
  ---------------------------------------------------------------------------
  -- Parameter normalization / defensive handling
  ---------------------------------------------------------------------------
  local originalTypes = {type(parentDlg), type(viewParams), type(updateCallback)}

  -- Case: caller used 2-arg form openControlsDialog(viewParams, updateCallback)
  if type(parentDlg) == "table" and (type(viewParams) == "function" or viewParams == nil) and updateCallback == nil then
    updateCallback = viewParams
    viewParams = parentDlg
    parentDlg = nil
  end

  -- If viewParams is still not a table, try shifting (in case first arg was not a dialog but a number)
  if type(viewParams) ~= "table" and type(parentDlg) == "table" and parentDlg.title == nil then
    -- Probably wrong order; nothing better to do than adopt parentDlg as viewParams
    viewParams = parentDlg
    parentDlg = nil
  end

  if type(viewParams) ~= "table" then
    print(string.format(
      "[dialogueManager.openControlsDialog] WARNING: expected viewParams table, got (%s,%s,%s). Creating defaults.",
      originalTypes[1], originalTypes[2], originalTypes[3]
    ))
    viewParams = {
      xRotation = 0, yRotation = 0, zRotation = 0,
      eulerX = 0, eulerY = 0, eulerZ = 0,
      depthPerspective = 50,
      orthogonalView = false,
      scaleLevel = 1.0,
      canvasSize = 200
    }
  end

  -- Ensure required fields exist
  viewParams.xRotation = viewParams.xRotation or viewParams.eulerX or 0
  viewParams.yRotation = viewParams.yRotation or viewParams.eulerY or 0
  viewParams.zRotation = viewParams.zRotation or viewParams.eulerZ or 0
  viewParams.eulerX = viewParams.eulerX or viewParams.xRotation
  viewParams.eulerY = viewParams.eulerY or viewParams.yRotation
  viewParams.eulerZ = viewParams.eulerZ or viewParams.zRotation
  viewParams.depthPerspective = viewParams.depthPerspective or 50
  viewParams.orthogonalView = (viewParams.orthogonalView == true)
  viewParams.scaleLevel = viewParams.scaleLevel or 1.0
  -- Initialize new FOV degrees (5°-75°) from legacy depthPerspective 0-100 range
  if not viewParams.fovDegrees then
    local pct = math.max(0, math.min(100, viewParams.depthPerspective or 50))
    viewParams.fovDegrees = 5 + (75-5)*(pct/100)
  end
  -- New: perspective scale reference ("middle" default, can be "back" or "front")
  if not viewParams.perspectiveScaleRef then
    viewParams.perspectiveScaleRef = "middle"
  end
  
  if type(updateCallback) ~= "function" then
    -- Fallback no-op to avoid crashes if callback omitted or wrong
    updateCallback = function() end
    print("[dialogueManager.openControlsDialog] NOTE: updateCallback missing or not a function; using no-op.")
  end
  ---------------------------------------------------------------------------

  -- Close any existing controls dialog
  if dialogueManager.controlsDialog then
    pcall(function()
      dialogueManager.controlsDialog:close()
    end)
  end

  local controlsDialog = Dialog{
    title = "View Controls"
  }
  dialogueManager.controlsDialog = controlsDialog

  local previousValues = {
    eulerX = viewParams.eulerX or viewParams.xRotation,
    eulerY = viewParams.eulerY or viewParams.yRotation,
    eulerZ = viewParams.eulerZ or viewParams.zRotation,
    absoluteX = 0,
    absoluteY = 0,
    absoluteZ = 0,
    relativeX = 0,
    relativeY = 0,
    relativeZ = 0
  }

  if not viewParams.eulerX then viewParams.eulerX = viewParams.xRotation or 0 end
  if not viewParams.eulerY then viewParams.eulerY = viewParams.yRotation or 0 end
  if not viewParams.eulerZ then viewParams.eulerZ = viewParams.zRotation or 0 end
  if not viewParams.absoluteX then viewParams.absoluteX = 0 end
  if not viewParams.absoluteY then viewParams.absoluteY = 0 end
  if not viewParams.absoluteZ then viewParams.absoluteZ = 0 end
  if not viewParams.relativeX then viewParams.relativeX = 0 end
  if not viewParams.relativeY then viewParams.relativeY = 0 end
  if not viewParams.relativeZ then viewParams.relativeZ = 0 end

  local function updateSlidersWithoutTriggeringEvents(x, y, z)
    dialogueManager.isUpdatingControls = true
    pcall(function()
      controlsDialog:modify{id="eulerX", value=math.floor(x)}
      controlsDialog:modify{id="eulerY", value=math.floor(y)}
      controlsDialog:modify{id="eulerZ", value=math.floor(z)}
      controlsDialog:modify{id="absoluteX", value=0}
      controlsDialog:modify{id="absoluteY", value=0}
      controlsDialog:modify{id="absoluteZ", value=0}
      controlsDialog:modify{id="relativeX", value=0}
      controlsDialog:modify{id="relativeY", value=0}
      controlsDialog:modify{id="relativeZ", value=0}
      previousValues.eulerX = x
      previousValues.eulerY = y
      previousValues.eulerZ = z
      previousValues.absoluteX = viewParams.absoluteX
      previousValues.absoluteY = viewParams.absoluteY
      previousValues.absoluteZ = viewParams.absoluteZ
      previousValues.relativeX = viewParams.relativeX
      previousValues.relativeY = viewParams.relativeY
      previousValues.relativeZ = viewParams.relativeZ
    end)
    dialogueManager.isUpdatingControls = false
  end

  local function updateRotationSectionVisibility(mode)
    dialogueManager.isUpdatingControls = true
    local eulerElements = { "eulerSection","eulerSeparator","eulerExplain1","eulerExplain2","eulerX","eulerY","eulerZ" }
    local absoluteElements = { "absoluteSection","absoluteSeparator","absoluteExplain1","absoluteExplain2","absoluteX","absoluteY","absoluteZ" }
    local relativeElements = { "relativeSection","relativeSeparator","relativeExplain1","relativeExplain2","relativeX","relativeY","relativeZ" }
    for _, id in ipairs(eulerElements) do pcall(function() controlsDialog:modify{id=id, visible=(mode=="euler")} end) end
    for _, id in ipairs(absoluteElements) do pcall(function() controlsDialog:modify{id=id, visible=(mode=="absolute")} end) end
    for _, id in ipairs(relativeElements) do pcall(function() controlsDialog:modify{id=id, visible=(mode=="relative")} end) end
    dialogueManager.isUpdatingControls = false
  end

  -- Add rotation system selector
  controlsDialog:separator{ text = "Rotation System" }
  controlsDialog:combobox{
    id = "rotationSystem",
    label = "System:",
    options = {
      "Euler Angles (Master Control)",
      "Absolute Rotation (Model-Space)",
      "Relative Rotation (Camera-Space)"
    },
    option = "Euler Angles (Master Control)",
    onchange = function()
      local selection = controlsDialog.data.rotationSystem
      if selection == "Euler Angles (Master Control)" then
        updateRotationSectionVisibility("euler")
      elseif selection == "Absolute Rotation (Model-Space)" then
        updateRotationSectionVisibility("absolute")
      elseif selection == "Relative Rotation (Camera-Space)" then
        updateRotationSectionVisibility("relative")
      end
    end
  }
  
  -- 1. EULER ANGLES ROTATION SYSTEM
  controlsDialog:separator{
    id = "eulerSeparator",
    text = "Euler Angles (Master Control)"
  }
  
  -- Add explanation for Euler rotation
  controlsDialog:label{
    id = "eulerExplain1",
    text = "Direct control of canonical rotation angles"
  }
  controlsDialog:newrow()
  controlsDialog:label{
    id = "eulerExplain2",
    text = "Best for precise angle input and reset"
  }
  
  -- Euler rotation controls
  controlsDialog:separator{
    id = "eulerSection",
    text = "Euler Angle Controls"
  }
  
  -- Add X rotation slider - Direct Euler angle control
  controlsDialog:slider{
    id = "eulerX",
    label = "X:",
    min = 0,
    max = 359,
    value = viewParams.eulerX,
    onchange = function()
      -- Skip if we're programmatically updating controls or locked
      if dialogueManager.isUpdatingControls or dialogueManager.updateLock then return end
      
      -- Directly update the master Euler angle
      viewParams.eulerX = controlsDialog.data.eulerX
      
      -- Update legacy values for compatibility
      viewParams.xRotation = viewParams.eulerX
      
      -- Recompute rotation matrix from Euler angles
      dialogueManager.currentRotationMatrix = mathUtils.createRotationMatrix(
        viewParams.eulerX,
        viewParams.eulerY,
        viewParams.eulerZ
      )
      
      -- Store the current value for next differential calculation
      previousValues.eulerX = controlsDialog.data.eulerX
      previousValues.absoluteX = viewParams.absoluteX
      previousValues.absoluteY = viewParams.absoluteY
      previousValues.absoluteZ = viewParams.absoluteZ
      previousValues.relativeX = viewParams.relativeX
      previousValues.relativeY = viewParams.relativeY
      previousValues.relativeZ = viewParams.relativeZ

      -- Reset other rotation controls to zero
      dialogueManager.isUpdatingControls = true
      pcall(function()
        controlsDialog:modify{id="absoluteX", value=0}
        controlsDialog:modify{id="absoluteY", value=0}
        controlsDialog:modify{id="absoluteZ", value=0}
        controlsDialog:modify{id="relativeX", value=0}
        controlsDialog:modify{id="relativeY", value=0}
        controlsDialog:modify{id="relativeZ", value=0}
      end)
      dialogueManager.isUpdatingControls = false      
      dialogueManager.safeUpdate(viewParams, updateCallback)
    end
  }
  
  -- Add Y rotation slider - Direct Euler angle control
  controlsDialog:slider{
    id = "eulerY",
    label = "Y:",
    min = 0,
    max = 359,
    value = viewParams.eulerY,
    onchange = function()
      -- Skip if we're programmatically updating controls or locked
      if dialogueManager.isUpdatingControls or dialogueManager.updateLock then return end
      
      -- Directly update the master Euler angle
      viewParams.eulerY = controlsDialog.data.eulerY
      
      -- Update legacy values for compatibility
      viewParams.yRotation = viewParams.eulerY
      
      -- Recompute rotation matrix from Euler angles
      dialogueManager.currentRotationMatrix = mathUtils.createRotationMatrix(
        viewParams.eulerX,
        viewParams.eulerY,
        viewParams.eulerZ
      )
      
      -- Store the current value for next differential calculation
      previousValues.eulerY = controlsDialog.data.eulerY
      previousValues.absoluteX = viewParams.absoluteX
      previousValues.absoluteY = viewParams.absoluteY
      previousValues.absoluteZ = viewParams.absoluteZ
      previousValues.relativeX = viewParams.relativeX
      previousValues.relativeY = viewParams.relativeY
      previousValues.relativeZ = viewParams.relativeZ

      -- Reset other rotation controls to zero
      dialogueManager.isUpdatingControls = true
      pcall(function()
        controlsDialog:modify{id="absoluteX", value=0}
        controlsDialog:modify{id="absoluteY", value=0}
        controlsDialog:modify{id="absoluteZ", value=0}
        controlsDialog:modify{id="relativeX", value=0}
        controlsDialog:modify{id="relativeY", value=0}
        controlsDialog:modify{id="relativeZ", value=0}
      end)
      dialogueManager.isUpdatingControls = false
      dialogueManager.safeUpdate(viewParams, updateCallback)
    end
  }
  
  -- Add Z rotation slider - Direct Euler angle control
  controlsDialog:slider{
    id = "eulerZ",
    label = "Z:",
    min = 0,
    max = 359,
    value = viewParams.eulerZ,
    onchange = function()
      -- Skip if we're programmatically updating controls or locked
      if dialogueManager.isUpdatingControls or dialogueManager.updateLock then return end
      
      -- Directly update the master Euler angle
      viewParams.eulerZ = controlsDialog.data.eulerZ
      
      -- Update legacy values for compatibility
      viewParams.zRotation = viewParams.eulerZ
      
      -- Recompute rotation matrix from Euler angles
      dialogueManager.currentRotationMatrix = mathUtils.createRotationMatrix(
        viewParams.eulerX,
        viewParams.eulerY,
        viewParams.eulerZ
      )
      
      -- Store the current value for next differential calculation
      previousValues.eulerZ = controlsDialog.data.eulerZ
      previousValues.absoluteX = viewParams.absoluteX
      previousValues.absoluteY = viewParams.absoluteY
      previousValues.absoluteZ = viewParams.absoluteZ
      previousValues.relativeX = viewParams.relativeX
      previousValues.relativeY = viewParams.relativeY
      previousValues.relativeZ = viewParams.relativeZ

      -- Reset other rotation controls to zero
      dialogueManager.isUpdatingControls = true
      pcall(function()
        controlsDialog:modify{id="absoluteX", value=0}
        controlsDialog:modify{id="absoluteY", value=0}
        controlsDialog:modify{id="absoluteZ", value=0}
        controlsDialog:modify{id="relativeX", value=0}
        controlsDialog:modify{id="relativeY", value=0}
        controlsDialog:modify{id="relativeZ", value=0}
      end)
      dialogueManager.isUpdatingControls = false
      dialogueManager.safeUpdate(viewParams, updateCallback)
    end
  }
  
  -- 2. ABSOLUTE ROTATION SYSTEM
  controlsDialog:separator{
    id = "absoluteSeparator",
    text = "Absolute Rotation (Model-Space)",
    visible = false
  }
  
  -- Add explanation for Absolute rotation
  controlsDialog:label{
    id = "absoluteExplain1",
    text = "Incremental rotations in model's own coordinate system",
    visible = false
  }
  controlsDialog:newrow()
  controlsDialog:label{
    id = "absoluteExplain2",
    text = "Best for adding rotation around model's current axes",
    visible = false
  }
  
  -- Absolute rotation controls
  controlsDialog:separator{
    id = "absoluteSection",
    text = "Absolute Rotation Controls",
    visible = false
  }
  
  -- Add X rotation slider - MODEL SPACE rotation around X axis
  controlsDialog:slider{
    id = "absoluteX",
    label = "X:",
    min = -180,
    max = 180,
    value = 0,
    visible = false,
    onchange = function()
      -- Skip if we're programmatically updating controls or locked
      if dialogueManager.isUpdatingControls or dialogueManager.updateLock then return end
      
      -- Get current value from slider
      local currentValue = controlsDialog.data.absoluteX
      
      -- Calculate the differential rotation, but with clamping to prevent large jumps
      local deltaX = currentValue - previousValues.absoluteX

      -- Only apply if delta is non-zero to avoid unnecessary matrix operations
      if deltaX ~= 0 then
        -- Apply only the delta rotation using the cached rotation matrix
        local newMatrix = rotation.applyAbsoluteRotation(
          dialogueManager.currentRotationMatrix,
          deltaX,  -- Apply X delta
          0,       -- No Y change
          0        -- No Z change
        )
        
        -- Extract Euler angles from the result
        local euler = mathUtils.matrixToEuler(newMatrix)
        
        -- Update the master Euler angles
        viewParams.eulerX = euler.x
        viewParams.eulerY = euler.y
        viewParams.eulerZ = euler.z
        
        -- Update legacy values for compatibility
        viewParams.xRotation = viewParams.eulerX
        viewParams.yRotation = viewParams.eulerY
        viewParams.zRotation = viewParams.eulerZ
        
        -- Update the stored rotation matrix
        dialogueManager.currentRotationMatrix = newMatrix
        
        -- Update the Euler sliders without triggering their events
        -- But do not reset the absolute controls
        dialogueManager.isUpdatingControls = true
        pcall(function()
          controlsDialog:modify{id="eulerX", value=math.floor(viewParams.xRotation)}
          controlsDialog:modify{id="eulerY", value=math.floor(viewParams.yRotation)}
          controlsDialog:modify{id="eulerZ", value=math.floor(viewParams.zRotation)}
          
          -- Reset camera-relative controls to zero
          controlsDialog:modify{id="relativeX", value=0}
          controlsDialog:modify{id="relativeY", value=0}
          controlsDialog:modify{id="relativeZ", value=0}
        end)
        dialogueManager.isUpdatingControls = false
        
        -- Update previous values
        previousValues.eulerX = viewParams.eulerX
        previousValues.eulerY = viewParams.eulerY
        previousValues.eulerZ = viewParams.eulerZ
        previousValues.relativeX = 0
        previousValues.relativeY = 0
        previousValues.relativeZ = 0
        previousValues.absoluteX = currentValue
        previousValues.absoluteY = 0
        previousValues.absoluteZ = 0

        dialogueManager.safeUpdate(viewParams, updateCallback)
      end
      
      -- CRITICAL: Always update the previous value for next delta calculation
      previousValues.absoluteX = currentValue
    end
  }
  
  -- Add Y rotation slider - MODEL SPACE rotation around Y axis
  controlsDialog:slider{
    id = "absoluteY",
    label = "Y:",
    min = -180,
    max = 180,
    value = 0,
    visible = false,
    onchange = function()
      -- Skip if we're programmatically updating controls or locked
      if dialogueManager.isUpdatingControls or dialogueManager.updateLock then return end
      
      -- Get current value from slider
      local currentValue = controlsDialog.data.absoluteY
      
      -- Calculate the differential rotation, but with clamping to prevent large jumps
      local deltaY = currentValue - previousValues.absoluteY

      -- Only apply if delta is non-zero to avoid unnecessary matrix operations
      if deltaY ~= 0 then
        -- Apply only the delta rotation using the cached rotation matrix
        local newMatrix = rotation.applyAbsoluteRotation(
          dialogueManager.currentRotationMatrix,
          0,        -- No X change
          deltaY,   -- Apply Y delta
          0         -- No Z change
        )
        
        -- Extract Euler angles from the result
        local euler = mathUtils.matrixToEuler(newMatrix)
        
        -- Update the master Euler angles
        viewParams.eulerX = euler.x
        viewParams.eulerY = euler.y
        viewParams.eulerZ = euler.z
        
        -- Update legacy values for compatibility
        viewParams.xRotation = viewParams.eulerX
        viewParams.yRotation = viewParams.eulerY
        viewParams.zRotation = viewParams.eulerZ
        
        -- Update the stored rotation matrix
        dialogueManager.currentRotationMatrix = newMatrix
        
        -- Update the Euler sliders without triggering their events
        -- But do not reset the absolute controls
        dialogueManager.isUpdatingControls = true
        pcall(function()
          controlsDialog:modify{id="eulerX", value=math.floor(viewParams.eulerX)}
          controlsDialog:modify{id="eulerY", value=math.floor(viewParams.eulerY)}
          controlsDialog:modify{id="eulerZ", value=math.floor(viewParams.eulerZ)}
          
          -- Reset camera-relative controls to zero
          controlsDialog:modify{id="relativeX", value=0}
          controlsDialog:modify{id="relativeY", value=0}
          controlsDialog:modify{id="relativeZ", value=0}
        end)
        dialogueManager.isUpdatingControls = false
        
        -- Update previous values
        previousValues.eulerX = viewParams.eulerX
        previousValues.eulerY = viewParams.eulerY
        previousValues.eulerZ = viewParams.eulerZ
        previousValues.relativeX = 0
        previousValues.relativeY = 0
        previousValues.relativeZ = 0
        
        
        dialogueManager.safeUpdate(viewParams, updateCallback)
      end
      
      -- CRITICAL: Always update the previous value for next delta calculation
      previousValues.absoluteY = currentValue
    end
  }
  
  -- Add Z rotation slider - MODEL SPACE rotation around Z axis
  controlsDialog:slider{
    id = "absoluteZ",
    label = "Z:",
    min = -180,
    max = 180,
    value = 0,
    visible = false,
    onchange = function()
      -- Skip if we're programmatically updating controls or locked
      if dialogueManager.isUpdatingControls or dialogueManager.updateLock then return end

      -- Get current value from slider
      local currentValue = controlsDialog.data.absoluteZ

      -- Calculate the differential rotation, but with clamping to prevent large jumps
      local deltaZ = currentValue - previousValues.absoluteZ

      -- Only apply if delta is non-zero to avoid unnecessary matrix operations
      if deltaZ ~= 0 then
        -- Apply only the delta rotation using the cached rotation matrix
        local newMatrix = rotation.applyAbsoluteRotation(
          dialogueManager.currentRotationMatrix,
          0,        -- No X change
          0,        -- No Y change
          deltaZ    -- Apply Z delta
        )

        -- Extract Euler angles from the result
        local euler = mathUtils.matrixToEuler(newMatrix)

        -- Update the master Euler angles
        viewParams.eulerX = euler.x
        viewParams.eulerY = euler.y
        viewParams.eulerZ = euler.z

        -- Update legacy values for compatibility
        viewParams.xRotation = viewParams.eulerX
        viewParams.yRotation = viewParams.eulerY
        viewParams.zRotation = viewParams.eulerZ

        -- Update the stored rotation matrix
        dialogueManager.currentRotationMatrix = newMatrix

        -- Update the Euler sliders without triggering their events
        -- But do not reset the absolute controls
        dialogueManager.isUpdatingControls = true
        pcall(function()
          controlsDialog:modify{id="eulerX", value=math.floor(viewParams.eulerX)}
          controlsDialog:modify{id="eulerY", value=math.floor(viewParams.eulerY)}
          controlsDialog:modify{id="eulerZ", value=math.floor(viewParams.eulerZ)}

          -- Reset camera-relative controls to zero
          controlsDialog:modify{id="relativeX", value=0}
          controlsDialog:modify{id="relativeY", value=0}
          controlsDialog:modify{id="relativeZ", value=0}
        end)
        dialogueManager.isUpdatingControls = false

        -- Update previous values
        previousValues.eulerX = viewParams.eulerX
        previousValues.eulerY = viewParams.eulerY
        previousValues.eulerZ = viewParams.eulerZ
        previousValues.relativeX = 0
        previousValues.relativeY = 0
        previousValues.relativeZ = 0
        previousValues.absoluteX = 0
        previousValues.absoluteY = 0
        previousValues.absoluteZ = currentValue

        dialogueManager.safeUpdate(viewParams, updateCallback)
      end

      -- CRITICAL: Always update the previous value for next delta calculation
      previousValues.absoluteZ = currentValue
    end
  }
  
  -- 3. RELATIVE ROTATION SYSTEM
  controlsDialog:separator{
    id = "relativeSeparator",
    text = "Relative Rotation (Camera-Space)",
    visible = false
  }
  
  -- Add explanation for Relative rotation
  controlsDialog:label{
    id = "relativeExplain1",
    text = "Rotations applied relative to current view",
    visible = false
  }
  controlsDialog:newrow()
  controlsDialog:label{
    id = "relativeExplain2",
    text = "Best for orbit-style navigation and trackball control",
    visible = false
  }
  
  -- Relative rotation controls
  controlsDialog:separator{
    id = "relativeSection",
    text = "Camera-Relative Controls",
    visible = false
  }
  
  -- Add pitch control (relative X rotation)
  controlsDialog:slider{
    id = "relativeX",
    label = "Pitch:",
    min = -90,
    max = 90,
    value = 0,
    visible = false,
    onchange = function() 
      -- Skip if we're programmatically updating controls or locked
      if dialogueManager.isUpdatingControls or dialogueManager.updateLock then return end
      
      -- Calculate pitch delta from previous value
      local pitchDelta = controlsDialog.data.relativeX - previousValues.relativeX
      -- Only apply if delta is non-zero to avoid unnecessary matrix operations
      if pitchDelta ~= 0 then
        -- Apply camera-relative pitch rotation
        local newMatrix = rotation.applyRelativeRotation(
          dialogueManager.currentRotationMatrix,
          pitchDelta, 0, 0
        )
        
        -- Extract Euler angles from the new matrix
        local euler = mathUtils.matrixToEuler(newMatrix)
        
        -- Update the master Euler angles
        viewParams.eulerX = euler.x
        viewParams.eulerY = euler.y
        viewParams.eulerZ = euler.z
        
        -- Update legacy values for compatibility
        viewParams.xRotation = viewParams.eulerX
        viewParams.yRotation = viewParams.eulerY
        viewParams.zRotation = viewParams.eulerZ
        
        -- Update rotation matrix
        dialogueManager.currentRotationMatrix = newMatrix
        
        -- Update the Euler sliders without triggering their events
        -- But do not reset the relative controls
        dialogueManager.isUpdatingControls = true
        pcall(function()
          controlsDialog:modify{id="eulerX", value=math.floor(viewParams.eulerX)}
          controlsDialog:modify{id="eulerY", value=math.floor(viewParams.eulerY)}
          controlsDialog:modify{id="eulerZ", value=math.floor(viewParams.eulerZ)}
          
          -- Reset absolute controls to zero
          controlsDialog:modify{id="absoluteX", value=0}
          controlsDialog:modify{id="absoluteY", value=0}
          controlsDialog:modify{id="absoluteZ", value=0}
        end)
        dialogueManager.isUpdatingControls = false
        
        -- Update previous values
        previousValues.eulerX = viewParams.eulerX
        previousValues.eulerY = viewParams.eulerY
        previousValues.eulerZ = viewParams.eulerZ
        previousValues.absoluteX = 0
        previousValues.absoluteY = 0
        previousValues.absoluteZ = 0
        
        
        dialogueManager.safeUpdate(viewParams, updateCallback)
      end
      
      -- CRITICAL: Always update the previous value for next delta calculation
      previousValues.relativeX = controlsDialog.data.relativeX
    end
  }
  
  -- Add yaw control (relative Y rotation)
  controlsDialog:slider{
    id = "relativeY",
    label = "Yaw:",
    min = -90,
    max = 90,
    value = 0,
    visible = false,
    onchange = function() 
      -- Skip if we're programmatically updating controls or locked
      if dialogueManager.isUpdatingControls or dialogueManager.updateLock then return end
      
      -- Calculate yaw delta from previous value
      local yawDelta = controlsDialog.data.relativeY - previousValues.relativeY
      
      -- Only apply if delta is non-zero to avoid unnecessary matrix operations
      if yawDelta ~= 0 then
        -- Apply camera-relative yaw rotation
        local newMatrix = rotation.applyRelativeRotation(
          dialogueManager.currentRotationMatrix,
          0, yawDelta, 0
        )
        
        -- Extract Euler angles from the new matrix
        local euler = mathUtils.matrixToEuler(newMatrix)
        
        -- Update the master Euler angles
        viewParams.eulerX = euler.x
        viewParams.eulerY = euler.y
        viewParams.eulerZ = euler.z
        
        -- Update legacy values for compatibility
        viewParams.xRotation = viewParams.eulerX
        viewParams.yRotation = viewParams.eulerY
        viewParams.zRotation = viewParams.eulerZ
        
        -- Update rotation matrix
        dialogueManager.currentRotationMatrix = newMatrix
        
        -- Update the Euler sliders without triggering their events
        -- But do not reset the relative controls
        dialogueManager.isUpdatingControls = true
        pcall(function()
          controlsDialog:modify{id="eulerX", value=math.floor(viewParams.eulerX)}
          controlsDialog:modify{id="eulerY", value=math.floor(viewParams.eulerY)}
          controlsDialog:modify{id="eulerZ", value=math.floor(viewParams.eulerZ)}
          
          -- Reset absolute controls to zero
          controlsDialog:modify{id="absoluteX", value=0}
          controlsDialog:modify{id="absoluteY", value=0}
          controlsDialog:modify{id="absoluteZ", value=0}
        end)
        dialogueManager.isUpdatingControls = false
        
        -- Update previous values
        previousValues.eulerX = viewParams.eulerX
        previousValues.eulerY = viewParams.eulerY
        previousValues.eulerZ = viewParams.eulerZ
        previousValues.absoluteX = 0
        previousValues.absoluteY = 0
        previousValues.absoluteZ = 0
        
        
        dialogueManager.safeUpdate(viewParams, updateCallback)
      end
      
      -- CRITICAL: Always update the previous value for next delta calculation
      previousValues.relativeY = controlsDialog.data.relativeY
    end
  }
  
  -- Add roll control (relative Z rotation)
  controlsDialog:slider{
    id = "relativeZ",
    label = "Roll:",
    min = -90,
    max = 90,
    value = 0,
    visible = false,
    onchange = function() 
      -- Skip if we're programmatically updating controls or locked
      if dialogueManager.isUpdatingControls or dialogueManager.updateLock then return end
      
      -- Calculate roll delta from previous value
      local rollDelta = controlsDialog.data.relativeZ - previousValues.relativeZ
      
      -- Only apply if delta is non-zero to avoid unnecessary matrix operations
      if rollDelta ~= 0 then
        -- Apply camera-relative roll rotation
        local newMatrix = rotation.applyRelativeRotation(
          dialogueManager.currentRotationMatrix,
          0, 0, rollDelta
        )
        
        -- Extract Euler angles from the new matrix
        local euler = mathUtils.matrixToEuler(newMatrix)
        
        -- Update the master Euler angles
        viewParams.eulerX = euler.x
        viewParams.eulerY = euler.y
        viewParams.eulerZ = euler.z
        
        -- Update legacy values for compatibility
        viewParams.xRotation = viewParams.eulerX
        viewParams.yRotation = viewParams.eulerY
        viewParams.zRotation = viewParams.eulerZ
        
        -- Update rotation matrix
        dialogueManager.currentRotationMatrix = newMatrix
        
        -- Update the Euler sliders without triggering their events
        -- But do not reset the relative controls
        dialogueManager.isUpdatingControls = true
        pcall(function()
          controlsDialog:modify{id="eulerX", value=math.floor(viewParams.eulerX)}
          controlsDialog:modify{id="eulerY", value=math.floor(viewParams.eulerY)}
          controlsDialog:modify{id="eulerZ", value=math.floor(viewParams.eulerZ)}
          
          -- Reset absolute controls to zero
          controlsDialog:modify{id="absoluteX", value=0}
          controlsDialog:modify{id="absoluteY", value=0}
          controlsDialog:modify{id="absoluteZ", value=0}
        end)
        dialogueManager.isUpdatingControls = false
        
        -- Update previous values
        previousValues.eulerX = viewParams.eulerX
        previousValues.eulerY = viewParams.eulerY
        previousValues.eulerZ = viewParams.eulerZ
        previousValues.absoluteX = 0
        previousValues.absoluteY = 0
        previousValues.absoluteZ = 0
        
        
        dialogueManager.safeUpdate(viewParams, updateCallback)
      end
      
      -- CRITICAL: Always update the previous value for next delta calculation
      previousValues.relativeZ = controlsDialog.data.relativeZ
    end
  }
  
  -- OTHER CONTROLS (these remain the same for all rotation modes)
  controlsDialog:separator{ text = "Perspective" }
  -- Replaced old 0-100 depth slider with direct FOV degrees (5°-75°)
  controlsDialog:slider{
    id = "depthPerspective", -- keep id for compatibility
    label = "FOV:",
    min = 5,
    max = 75,
    value = math.floor(viewParams.fovDegrees or 45),
    onchange = function()
      viewParams.fovDegrees = controlsDialog.data.depthPerspective
      dialogueManager.safeUpdate(viewParams, updateCallback)
    end
  }
  -- New: Perspective scale reference (visible only when not orthographic)
  local function _refToOption(ref)
    if ref == "back" then return "Back"
    elseif ref == "front" then return "Front"
    else return "Middle" end
  end
  controlsDialog:combobox{
    id = "perspScaleRef",
    label = "Perspective Ref:",
    options = { "Middle", "Back", "Front" },
    option = _refToOption(viewParams.perspectiveScaleRef),
    visible = (not viewParams.orthogonalView),
    onchange = function()
      local opt = controlsDialog.data.perspScaleRef
      if opt == "Back" then
        viewParams.perspectiveScaleRef = "back"
      elseif opt == "Front" then
        viewParams.perspectiveScaleRef = "front"
      else
        viewParams.perspectiveScaleRef = "middle"
      end
      dialogueManager.safeUpdate(viewParams, updateCallback)
    end
  }
  
  controlsDialog:check{
    id = "orthogonalView",
    text = "Orthogonal View",
    selected = viewParams.orthogonalView,
    onclick = function() 
      viewParams.orthogonalView = controlsDialog.data.orthogonalView
      dialogueManager.safeUpdate(viewParams, updateCallback)
      -- Disable FOV slider when orthographic forced
      pcall(function()
        controlsDialog:modify{ id="depthPerspective", enabled = (not controlsDialog.data.orthogonalView) }
        controlsDialog:modify{ id="perspScaleRef", visible = (not controlsDialog.data.orthogonalView) }
      end)
    end
  }
  -- Initialize FOV slider enabled state
  pcall(function()
    controlsDialog:modify{ id="depthPerspective", enabled = (not viewParams.orthogonalView) }
    controlsDialog:modify{ id="perspScaleRef", visible = (not viewParams.orthogonalView) }
  end)

  controlsDialog:separator{ text = "Scale Controls" }
  
  controlsDialog:slider{
    id = "scaleSlider",
    min = 1,
    max = 10,
    value = viewParams.scaleLevel * 2,
    onchange = function()
      viewParams.scaleLevel = controlsDialog.data.scaleSlider / 2
      controlsDialog:modify{id="scaleLabel", text="Scale: " .. string.format("%.0f%%", viewParams.scaleLevel * 100)}
      dialogueManager.safeUpdate(viewParams, updateCallback)
    end
  }
  
  controlsDialog:label{
    id = "scaleLabel",
    text = "Scale: " .. string.format("%.0f%%", viewParams.scaleLevel * 100)
  }
  
  controlsDialog:separator{ text = "Quick Views" }
  
  controlsDialog:button{
    id = "frontView",
    text = "Front",
    onclick = function()
      -- Skip if update is locked
      if dialogueManager.updateLock then return end
      
      -- Set direct values for front view
      viewParams.eulerX = 0
      viewParams.eulerY = 0
      viewParams.eulerZ = 0
      
      -- Update legacy values
      viewParams.xRotation = viewParams.eulerX
      viewParams.yRotation = viewParams.eulerY
      viewParams.zRotation = viewParams.eulerZ
      
      -- Reset to front view (identity matrix with no rotation)
      dialogueManager.currentRotationMatrix = mathUtils.createRotationMatrix(
        viewParams.eulerX, viewParams.eulerY, viewParams.eulerZ
      )
      
      -- Update all sliders without triggering their change events
      updateSlidersWithoutTriggeringEvents(0, 0, 0)

      dialogueManager.safeUpdate(viewParams, updateCallback)
    end
  }
  
  controlsDialog:button{
    id = "topView",
    text = "Top",
    onclick = function()
      if dialogueManager.updateLock then return end
      
      -- Set direct values for top view (Euler angles)
      viewParams.eulerX = 270
      viewParams.eulerY = 0
      viewParams.eulerZ = 0
      viewParams.xRotation = viewParams.eulerX
      viewParams.yRotation = viewParams.eulerY
      viewParams.zRotation = viewParams.eulerZ
      dialogueManager.currentRotationMatrix = mathUtils.createRotationMatrix(
        viewParams.eulerX, viewParams.eulerY, viewParams.eulerZ
      )
      updateSlidersWithoutTriggeringEvents(viewParams.eulerX, viewParams.eulerY, viewParams.eulerZ)
      dialogueManager.safeUpdate(viewParams, updateCallback)
    end
  }
  
  controlsDialog:button{
    id = "sideView",
    text = "Side",
    onclick = function()
      -- Skip if update is locked
      if dialogueManager.updateLock then return end
      
      -- Set direct values for side view (Euler angles)
      viewParams.eulerX = 0
      viewParams.eulerY = 90
      viewParams.eulerZ = 0
      
      -- Update legacy values
      viewParams.xRotation = viewParams.eulerX
      viewParams.yRotation = viewParams.eulerY
      viewParams.zRotation = viewParams.eulerZ
      
      -- Update rotation matrix
      dialogueManager.currentRotationMatrix = mathUtils.createRotationMatrix(
        viewParams.eulerX, viewParams.eulerY, viewParams.eulerZ
      )
      
      -- Update all sliders without triggering their change events
      updateSlidersWithoutTriggeringEvents(
        viewParams.eulerX, viewParams.eulerY, viewParams.eulerZ
      )

      dialogueManager.safeUpdate(viewParams, updateCallback)
    end
  }
  
  controlsDialog:button{
    id = "isoView",
    text = "Iso",
    onclick = function()
      if dialogueManager.updateLock then return end
      
      -- Set direct values for iso view (Euler angles)
      viewParams.eulerX = 315
      viewParams.eulerY = 324
      viewParams.eulerZ = 29
      viewParams.xRotation = viewParams.eulerX
      viewParams.yRotation = viewParams.eulerY
      viewParams.zRotation = viewParams.eulerZ
      dialogueManager.currentRotationMatrix = mathUtils.createRotationMatrix(
        viewParams.eulerX, viewParams.eulerY, viewParams.eulerZ
      )
      updateSlidersWithoutTriggeringEvents(viewParams.eulerX, viewParams.eulerY, viewParams.eulerZ)
      dialogueManager.safeUpdate(viewParams, updateCallback)
    end
  }
  
  controlsDialog:separator()
  
  controlsDialog:button{
    id = "closeButton",
    text = "Close",
    onclick = function()
      dialogueManager.controlsDialog = nil
      controlsDialog:close()
    end
  }
  
  -- Initialize rotation sections visibility - start with Euler controls
  updateRotationSectionVisibility("euler")
  
  -- Show dialog
  controlsDialog:show{ wait = false }
  
  return controlsDialog
end

--------------------------------------------------------------------------------
-- Help Dialog
--------------------------------------------------------------------------------
function dialogueManager.openHelpDialog()
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

--------------------------------------------------------------------------------
-- Animation Dialog
--------------------------------------------------------------------------------
function dialogueManager.openAnimationDialog(viewParams, voxelModel, modelDimensions)
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
        rotationMatrix = dialogueManager.currentRotationMatrix,
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

--------------------------------------------------------------------------------
-- Export Dialog
--------------------------------------------------------------------------------
function dialogueManager.openExportDialog(voxelModel)
  if not voxelModel or #voxelModel == 0 then
    app.alert("No model to export!")
    return
  end
  
  local dlg = Dialog("Export Voxel Model")
  local previewImage = nil
  local sprite = app.activeSprite
  
  -- Default export options
  local exportOptions = {
    format = "obj",
    includeTexture = true,
    scaleModel = 1.0,
    optimizeMesh = true
  }
  
  -- Get middle point for model size calculation
  local middlePoint = previewRenderer.calculateMiddlePoint(voxelModel)
  
  -- Calculate canvas size based on model dimensions and max scale
  local maxScale = 10
  local diagonal = math.sqrt(
    middlePoint.sizeX^2 + 
    middlePoint.sizeY^2 + 
    middlePoint.sizeZ^2
  )
  local canvasWidth = math.ceil(diagonal * maxScale / 2) -- Half size for preview
  local canvasHeight = canvasWidth
  
  -- Generate a small preview of the model
  local function generatePreview()
    if not sprite then return end
    -- Regenerate from the active sprite so the dialog reflects current layers/changes
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

    -- Render a compact preview using a smaller pixel size and zoom factor
    local params = {
      x = 315,
      y = 324,
      z = 29,
      depth = 50,
      orthogonal = false,
      pixelSize = 1,
      canvasSize = canvasWidth,
      zoomFactor = 1
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
  
  -- Show dialog and generate preview without waiting
  dlg:show{ wait = false }
  generatePreview()
  -- Lightweight refresh to pick up quick edits, then regenerate preview
  app.refresh()
  generatePreview()

  -- Store dialog reference
  dialogueManager.exportDialog = dlg
end

--------------------------------------------------------------------------------
-- Outline Dialog
--------------------------------------------------------------------------------
function dialogueManager.openOutlineDialog(viewParams, updateCallback)
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

return dialogueManager