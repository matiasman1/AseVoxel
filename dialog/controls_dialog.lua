-- controls_dialog.lua
-- View Controls Dialog - Rotation system with Euler, Absolute, and Relative modes

local ControlsDialog = {}

-- Lazy-loaded dependencies
local dialogueManager = nil
local function getDialogManager()
  if dialogueManager ~= nil then return dialogueManager end
  dialogueManager = AseVoxel.dialog.dialog_manager
  return dialogueManager
end

local mathUtils = nil
local function getMathUtils()
  if mathUtils ~= nil then return mathUtils end
  mathUtils = {
    createRotationMatrix = function(x, y, z)
      return AseVoxel.math.rotation_matrix.createRotationMatrix(x, y, z)
    end,
    matrixToEuler = function(matrix)
      return AseVoxel.math.rotation_matrix.matrixToEuler(matrix)
    end,
    identity = function()
      return AseVoxel.math.matrix.identity()
    end
  }
  return mathUtils
end

local rotation = nil
local function getRotation()
  if rotation ~= nil then return rotation end
  rotation = AseVoxel.math.rotation
  return rotation
end

function ControlsDialog.openControlsDialog(parentDlg, viewParams, updateCallback)
  local mgr = getDialogManager()
  local mUtils = getMathUtils()
  local rot = getRotation()
  
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
      "[ControlsDialog.openControlsDialog] WARNING: expected viewParams table, got (%s,%s,%s). Creating defaults.",
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
    print("[ControlsDialog.openControlsDialog] NOTE: updateCallback missing or not a function; using no-op.")
  end
  ---------------------------------------------------------------------------

  -- Close any existing controls dialog
  if mgr.controlsDialog then
    pcall(function()
      mgr.controlsDialog:close()
    end)
  end

  local controlsDialog = Dialog{
    title = "View Controls"
  }
  mgr.controlsDialog = controlsDialog

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
    mgr.isUpdatingControls = true
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
    mgr.isUpdatingControls = false
  end

  local function updateRotationSectionVisibility(mode)
    mgr.isUpdatingControls = true
    local eulerElements = { "eulerSection","eulerSeparator","eulerExplain1","eulerExplain2","eulerX","eulerY","eulerZ" }
    local absoluteElements = { "absoluteSection","absoluteSeparator","absoluteExplain1","absoluteExplain2","absoluteX","absoluteY","absoluteZ" }
    local relativeElements = { "relativeSection","relativeSeparator","relativeExplain1","relativeExplain2","relativeX","relativeY","relativeZ" }
    for _, id in ipairs(eulerElements) do pcall(function() controlsDialog:modify{id=id, visible=(mode=="euler")} end) end
    for _, id in ipairs(absoluteElements) do pcall(function() controlsDialog:modify{id=id, visible=(mode=="absolute")} end) end
    for _, id in ipairs(relativeElements) do pcall(function() controlsDialog:modify{id=id, visible=(mode=="relative")} end) end
    mgr.isUpdatingControls = false
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
      if mgr.isUpdatingControls or mgr.updateLock then return end
      
      -- Directly update the master Euler angle
      viewParams.eulerX = controlsDialog.data.eulerX
      
      -- Update legacy values for compatibility
      viewParams.xRotation = viewParams.eulerX
      
      -- Recompute rotation matrix from Euler angles
      mgr.currentRotationMatrix = mUtils.createRotationMatrix(
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
      mgr.isUpdatingControls = true
      pcall(function()
        controlsDialog:modify{id="absoluteX", value=0}
        controlsDialog:modify{id="absoluteY", value=0}
        controlsDialog:modify{id="absoluteZ", value=0}
        controlsDialog:modify{id="relativeX", value=0}
        controlsDialog:modify{id="relativeY", value=0}
        controlsDialog:modify{id="relativeZ", value=0}
      end)
      mgr.isUpdatingControls = false      
      mgr.safeUpdate(viewParams, updateCallback)
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
      if mgr.isUpdatingControls or mgr.updateLock then return end
      
      -- Directly update the master Euler angle
      viewParams.eulerY = controlsDialog.data.eulerY
      
      -- Update legacy values for compatibility
      viewParams.yRotation = viewParams.eulerY
      
      -- Recompute rotation matrix from Euler angles
      mgr.currentRotationMatrix = mUtils.createRotationMatrix(
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
      mgr.isUpdatingControls = true
      pcall(function()
        controlsDialog:modify{id="absoluteX", value=0}
        controlsDialog:modify{id="absoluteY", value=0}
        controlsDialog:modify{id="absoluteZ", value=0}
        controlsDialog:modify{id="relativeX", value=0}
        controlsDialog:modify{id="relativeY", value=0}
        controlsDialog:modify{id="relativeZ", value=0}
      end)
      mgr.isUpdatingControls = false
      mgr.safeUpdate(viewParams, updateCallback)
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
      if mgr.isUpdatingControls or mgr.updateLock then return end
      
      -- Directly update the master Euler angle
      viewParams.eulerZ = controlsDialog.data.eulerZ
      
      -- Update legacy values for compatibility
      viewParams.zRotation = viewParams.eulerZ
      
      -- Recompute rotation matrix from Euler angles
      mgr.currentRotationMatrix = mUtils.createRotationMatrix(
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
      mgr.isUpdatingControls = true
      pcall(function()
        controlsDialog:modify{id="absoluteX", value=0}
        controlsDialog:modify{id="absoluteY", value=0}
        controlsDialog:modify{id="absoluteZ", value=0}
        controlsDialog:modify{id="relativeX", value=0}
        controlsDialog:modify{id="relativeY", value=0}
        controlsDialog:modify{id="relativeZ", value=0}
      end)
      mgr.isUpdatingControls = false
      mgr.safeUpdate(viewParams, updateCallback)
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
      if mgr.isUpdatingControls or mgr.updateLock then return end
      
      -- Get current value from slider
      local currentValue = controlsDialog.data.absoluteX
      
      -- Calculate the differential rotation, but with clamping to prevent large jumps
      local deltaX = currentValue - previousValues.absoluteX

      -- Only apply if delta is non-zero to avoid unnecessary matrix operations
      if deltaX ~= 0 then
        -- Apply only the delta rotation using the cached rotation matrix
        local newMatrix = rot.applyAbsoluteRotation(
          mgr.currentRotationMatrix,
          deltaX,  -- Apply X delta
          0,       -- No Y change
          0        -- No Z change
        )
        
        -- Extract Euler angles from the result
        local euler = mUtils.matrixToEuler(newMatrix)
        
        -- Update the master Euler angles
        viewParams.eulerX = euler.x
        viewParams.eulerY = euler.y
        viewParams.eulerZ = euler.z
        
        -- Update legacy values for compatibility
        viewParams.xRotation = viewParams.eulerX
        viewParams.yRotation = viewParams.eulerY
        viewParams.zRotation = viewParams.eulerZ
        
        -- Update the stored rotation matrix
        mgr.currentRotationMatrix = newMatrix
        
        -- Update the Euler sliders without triggering their events
        -- But do not reset the absolute controls
        mgr.isUpdatingControls = true
        pcall(function()
          controlsDialog:modify{id="eulerX", value=math.floor(viewParams.xRotation)}
          controlsDialog:modify{id="eulerY", value=math.floor(viewParams.yRotation)}
          controlsDialog:modify{id="eulerZ", value=math.floor(viewParams.zRotation)}
          
          -- Reset camera-relative controls to zero
          controlsDialog:modify{id="relativeX", value=0}
          controlsDialog:modify{id="relativeY", value=0}
          controlsDialog:modify{id="relativeZ", value=0}
        end)
        mgr.isUpdatingControls = false
        
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

        mgr.safeUpdate(viewParams, updateCallback)
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
      if mgr.isUpdatingControls or mgr.updateLock then return end
      
      -- Get current value from slider
      local currentValue = controlsDialog.data.absoluteY
      
      -- Calculate the differential rotation, but with clamping to prevent large jumps
      local deltaY = currentValue - previousValues.absoluteY

      -- Only apply if delta is non-zero to avoid unnecessary matrix operations
      if deltaY ~= 0 then
        -- Apply only the delta rotation using the cached rotation matrix
        local newMatrix = rot.applyAbsoluteRotation(
          mgr.currentRotationMatrix,
          0,        -- No X change
          deltaY,   -- Apply Y delta
          0         -- No Z change
        )
        
        -- Extract Euler angles from the result
        local euler = mUtils.matrixToEuler(newMatrix)
        
        -- Update the master Euler angles
        viewParams.eulerX = euler.x
        viewParams.eulerY = euler.y
        viewParams.eulerZ = euler.z
        
        -- Update legacy values for compatibility
        viewParams.xRotation = viewParams.eulerX
        viewParams.yRotation = viewParams.eulerY
        viewParams.zRotation = viewParams.eulerZ
        
        -- Update the stored rotation matrix
        mgr.currentRotationMatrix = newMatrix
        
        -- Update the Euler sliders without triggering their events
        -- But do not reset the absolute controls
        mgr.isUpdatingControls = true
        pcall(function()
          controlsDialog:modify{id="eulerX", value=math.floor(viewParams.eulerX)}
          controlsDialog:modify{id="eulerY", value=math.floor(viewParams.eulerY)}
          controlsDialog:modify{id="eulerZ", value=math.floor(viewParams.eulerZ)}
          
          -- Reset camera-relative controls to zero
          controlsDialog:modify{id="relativeX", value=0}
          controlsDialog:modify{id="relativeY", value=0}
          controlsDialog:modify{id="relativeZ", value=0}
        end)
        mgr.isUpdatingControls = false
        
        -- Update previous values
        previousValues.eulerX = viewParams.eulerX
        previousValues.eulerY = viewParams.eulerY
        previousValues.eulerZ = viewParams.eulerZ
        previousValues.relativeX = 0
        previousValues.relativeY = 0
        previousValues.relativeZ = 0
        
        
        mgr.safeUpdate(viewParams, updateCallback)
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
      if mgr.isUpdatingControls or mgr.updateLock then return end

      -- Get current value from slider
      local currentValue = controlsDialog.data.absoluteZ

      -- Calculate the differential rotation, but with clamping to prevent large jumps
      local deltaZ = currentValue - previousValues.absoluteZ

      -- Only apply if delta is non-zero to avoid unnecessary matrix operations
      if deltaZ ~= 0 then
        -- Apply only the delta rotation using the cached rotation matrix
        local newMatrix = rot.applyAbsoluteRotation(
          mgr.currentRotationMatrix,
          0,        -- No X change
          0,        -- No Y change
          deltaZ    -- Apply Z delta
        )

        -- Extract Euler angles from the result
        local euler = mUtils.matrixToEuler(newMatrix)

        -- Update the master Euler angles
        viewParams.eulerX = euler.x
        viewParams.eulerY = euler.y
        viewParams.eulerZ = euler.z

        -- Update legacy values for compatibility
        viewParams.xRotation = viewParams.eulerX
        viewParams.yRotation = viewParams.eulerY
        viewParams.zRotation = viewParams.eulerZ

        -- Update the stored rotation matrix
        mgr.currentRotationMatrix = newMatrix

        -- Update the Euler sliders without triggering their events
        -- But do not reset the absolute controls
        mgr.isUpdatingControls = true
        pcall(function()
          controlsDialog:modify{id="eulerX", value=math.floor(viewParams.eulerX)}
          controlsDialog:modify{id="eulerY", value=math.floor(viewParams.eulerY)}
          controlsDialog:modify{id="eulerZ", value=math.floor(viewParams.eulerZ)}

          -- Reset camera-relative controls to zero
          controlsDialog:modify{id="relativeX", value=0}
          controlsDialog:modify{id="relativeY", value=0}
          controlsDialog:modify{id="relativeZ", value=0}
        end)
        mgr.isUpdatingControls = false

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

        mgr.safeUpdate(viewParams, updateCallback)
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
      if mgr.isUpdatingControls or mgr.updateLock then return end
      
      -- Calculate pitch delta from previous value
      local pitchDelta = controlsDialog.data.relativeX - previousValues.relativeX
      -- Only apply if delta is non-zero to avoid unnecessary matrix operations
      if pitchDelta ~= 0 then
        -- Apply camera-relative pitch rotation
        local newMatrix = rot.applyRelativeRotation(
          mgr.currentRotationMatrix,
          pitchDelta, 0, 0
        )
        
        -- Extract Euler angles from the new matrix
        local euler = mUtils.matrixToEuler(newMatrix)
        
        -- Update the master Euler angles
        viewParams.eulerX = euler.x
        viewParams.eulerY = euler.y
        viewParams.eulerZ = euler.z
        
        -- Update legacy values for compatibility
        viewParams.xRotation = viewParams.eulerX
        viewParams.yRotation = viewParams.eulerY
        viewParams.zRotation = viewParams.eulerZ
        
        -- Update rotation matrix
        mgr.currentRotationMatrix = newMatrix
        
        -- Update the Euler sliders without triggering their events
        -- But do not reset the relative controls
        mgr.isUpdatingControls = true
        pcall(function()
          controlsDialog:modify{id="eulerX", value=math.floor(viewParams.eulerX)}
          controlsDialog:modify{id="eulerY", value=math.floor(viewParams.eulerY)}
          controlsDialog:modify{id="eulerZ", value=math.floor(viewParams.eulerZ)}
          
          -- Reset absolute controls to zero
          controlsDialog:modify{id="absoluteX", value=0}
          controlsDialog:modify{id="absoluteY", value=0}
          controlsDialog:modify{id="absoluteZ", value=0}
        end)
        mgr.isUpdatingControls = false
        
        -- Update previous values
        previousValues.eulerX = viewParams.eulerX
        previousValues.eulerY = viewParams.eulerY
        previousValues.eulerZ = viewParams.eulerZ
        previousValues.absoluteX = 0
        previousValues.absoluteY = 0
        previousValues.absoluteZ = 0
        
        
        mgr.safeUpdate(viewParams, updateCallback)
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
      if mgr.isUpdatingControls or mgr.updateLock then return end
      
      -- Calculate yaw delta from previous value
      local yawDelta = controlsDialog.data.relativeY - previousValues.relativeY
      
      -- Only apply if delta is non-zero to avoid unnecessary matrix operations
      if yawDelta ~= 0 then
        -- Apply camera-relative yaw rotation
        local newMatrix = rot.applyRelativeRotation(
          mgr.currentRotationMatrix,
          0, yawDelta, 0
        )
        
        -- Extract Euler angles from the new matrix
        local euler = mUtils.matrixToEuler(newMatrix)
        
        -- Update the master Euler angles
        viewParams.eulerX = euler.x
        viewParams.eulerY = euler.y
        viewParams.eulerZ = euler.z
        
        -- Update legacy values for compatibility
        viewParams.xRotation = viewParams.eulerX
        viewParams.yRotation = viewParams.eulerY
        viewParams.zRotation = viewParams.eulerZ
        
        -- Update rotation matrix
        mgr.currentRotationMatrix = newMatrix
        
        -- Update the Euler sliders without triggering their events
        -- But do not reset the relative controls
        mgr.isUpdatingControls = true
        pcall(function()
          controlsDialog:modify{id="eulerX", value=math.floor(viewParams.eulerX)}
          controlsDialog:modify{id="eulerY", value=math.floor(viewParams.eulerY)}
          controlsDialog:modify{id="eulerZ", value=math.floor(viewParams.eulerZ)}
          
          -- Reset absolute controls to zero
          controlsDialog:modify{id="absoluteX", value=0}
          controlsDialog:modify{id="absoluteY", value=0}
          controlsDialog:modify{id="absoluteZ", value=0}
        end)
        mgr.isUpdatingControls = false
        
        -- Update previous values
        previousValues.eulerX = viewParams.eulerX
        previousValues.eulerY = viewParams.eulerY
        previousValues.eulerZ = viewParams.eulerZ
        previousValues.absoluteX = 0
        previousValues.absoluteY = 0
        previousValues.absoluteZ = 0
        
        
        mgr.safeUpdate(viewParams, updateCallback)
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
      if mgr.isUpdatingControls or mgr.updateLock then return end
      
      -- Calculate roll delta from previous value
      local rollDelta = controlsDialog.data.relativeZ - previousValues.relativeZ
      
      -- Only apply if delta is non-zero to avoid unnecessary matrix operations
      if rollDelta ~= 0 then
        -- Apply camera-relative roll rotation
        local newMatrix = rot.applyRelativeRotation(
          mgr.currentRotationMatrix,
          0, 0, rollDelta
        )
        
        -- Extract Euler angles from the new matrix
        local euler = mUtils.matrixToEuler(newMatrix)
        
        -- Update the master Euler angles
        viewParams.eulerX = euler.x
        viewParams.eulerY = euler.y
        viewParams.eulerZ = euler.z
        
        -- Update legacy values for compatibility
        viewParams.xRotation = viewParams.eulerX
        viewParams.yRotation = viewParams.eulerY
        viewParams.zRotation = viewParams.eulerZ
        
        -- Update rotation matrix
        mgr.currentRotationMatrix = newMatrix
        
        -- Update the Euler sliders without triggering their events
        -- But do not reset the relative controls
        mgr.isUpdatingControls = true
        pcall(function()
          controlsDialog:modify{id="eulerX", value=math.floor(viewParams.eulerX)}
          controlsDialog:modify{id="eulerY", value=math.floor(viewParams.eulerY)}
          controlsDialog:modify{id="eulerZ", value=math.floor(viewParams.eulerZ)}
          
          -- Reset absolute controls to zero
          controlsDialog:modify{id="absoluteX", value=0}
          controlsDialog:modify{id="absoluteY", value=0}
          controlsDialog:modify{id="absoluteZ", value=0}
        end)
        mgr.isUpdatingControls = false
        
        -- Update previous values
        previousValues.eulerX = viewParams.eulerX
        previousValues.eulerY = viewParams.eulerY
        previousValues.eulerZ = viewParams.eulerZ
        previousValues.absoluteX = 0
        previousValues.absoluteY = 0
        previousValues.absoluteZ = 0
        
        
        mgr.safeUpdate(viewParams, updateCallback)
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
      mgr.safeUpdate(viewParams, updateCallback)
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
      mgr.safeUpdate(viewParams, updateCallback)
    end
  }
  
  controlsDialog:check{
    id = "orthogonalView",
    text = "Orthogonal View",
    selected = viewParams.orthogonalView,
    onclick = function() 
      viewParams.orthogonalView = controlsDialog.data.orthogonalView
      mgr.safeUpdate(viewParams, updateCallback)
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
      mgr.safeUpdate(viewParams, updateCallback)
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
      if mgr.updateLock then return end
      
      -- Set direct values for front view
      viewParams.eulerX = 0
      viewParams.eulerY = 0
      viewParams.eulerZ = 0
      
      -- Update legacy values
      viewParams.xRotation = viewParams.eulerX
      viewParams.yRotation = viewParams.eulerY
      viewParams.zRotation = viewParams.eulerZ
      
      -- Reset to front view (identity matrix with no rotation)
      mgr.currentRotationMatrix = mUtils.createRotationMatrix(
        viewParams.eulerX, viewParams.eulerY, viewParams.eulerZ
      )
      
      -- Update all sliders without triggering their change events
      updateSlidersWithoutTriggeringEvents(0, 0, 0)

      mgr.safeUpdate(viewParams, updateCallback)
    end
  }
  
  controlsDialog:button{
    id = "topView",
    text = "Top",
    onclick = function()
      if mgr.updateLock then return end
      
      -- Set direct values for top view (Euler angles)
      viewParams.eulerX = 270
      viewParams.eulerY = 0
      viewParams.eulerZ = 0
      viewParams.xRotation = viewParams.eulerX
      viewParams.yRotation = viewParams.eulerY
      viewParams.zRotation = viewParams.eulerZ
      mgr.currentRotationMatrix = mUtils.createRotationMatrix(
        viewParams.eulerX, viewParams.eulerY, viewParams.eulerZ
      )
      updateSlidersWithoutTriggeringEvents(viewParams.eulerX, viewParams.eulerY, viewParams.eulerZ)
      mgr.safeUpdate(viewParams, updateCallback)
    end
  }
  
  controlsDialog:button{
    id = "sideView",
    text = "Side",
    onclick = function()
      -- Skip if update is locked
      if mgr.updateLock then return end
      
      -- Set direct values for side view (Euler angles)
      viewParams.eulerX = 0
      viewParams.eulerY = 90
      viewParams.eulerZ = 0
      
      -- Update legacy values
      viewParams.xRotation = viewParams.eulerX
      viewParams.yRotation = viewParams.eulerY
      viewParams.zRotation = viewParams.eulerZ
      
      -- Update rotation matrix
      mgr.currentRotationMatrix = mUtils.createRotationMatrix(
        viewParams.eulerX, viewParams.eulerY, viewParams.eulerZ
      )
      
      -- Update all sliders without triggering their change events
      updateSlidersWithoutTriggeringEvents(
        viewParams.eulerX, viewParams.eulerY, viewParams.eulerZ
      )

      mgr.safeUpdate(viewParams, updateCallback)
    end
  }
  
  controlsDialog:button{
    id = "isoView",
    text = "Iso",
    onclick = function()
      if mgr.updateLock then return end
      
      -- Set direct values for iso view (Euler angles)
      viewParams.eulerX = 315
      viewParams.eulerY = 324
      viewParams.eulerZ = 29
      viewParams.xRotation = viewParams.eulerX
      viewParams.yRotation = viewParams.eulerY
      viewParams.zRotation = viewParams.eulerZ
      mgr.currentRotationMatrix = mUtils.createRotationMatrix(
        viewParams.eulerX, viewParams.eulerY, viewParams.eulerZ
      )
      updateSlidersWithoutTriggeringEvents(viewParams.eulerX, viewParams.eulerY, viewParams.eulerZ)
      mgr.safeUpdate(viewParams, updateCallback)
    end
  }
  
  controlsDialog:separator()
  
  controlsDialog:button{
    id = "closeButton",
    text = "Close",
    onclick = function()
      mgr.controlsDialog = nil
      controlsDialog:close()
    end
  }
  
  -- Initialize rotation sections visibility - start with Euler controls
  updateRotationSectionVisibility("euler")
  
  -- Show dialog
  controlsDialog:show{ wait = false }
  
  return controlsDialog
end

return ControlsDialog
