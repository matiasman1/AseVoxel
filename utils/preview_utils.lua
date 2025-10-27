-- General purpose functions for preview rendering and updating

-- Lazy loaders to break circular dependencies
local function getPreviewRenderer()
  return AseVoxel.previewRenderer
end

local function getMathUtils()
  return AseVoxel.mathUtils
end

local function getRotation()
  return AseVoxel.rotation
end

local previewUtils = {}

-- Update the 3D preview with current rotation settings
function previewUtils.updatePreview(dlg, params)
  local previewRenderer = getPreviewRenderer()
  local sprite = app.activeSprite
  if not sprite then
    app.alert("No active sprite found!")
    return nil
  end
  
  -- Generate the voxel model from sprite layers
  local voxelModel = previewRenderer.generateVoxelModel(sprite)
  if #voxelModel == 0 then
    app.alert("No voxels found in the sprite layers!")
    return nil
  end
  
  -- Get middle point and dimensions
  local middlePoint = previewRenderer.calculateMiddlePoint(voxelModel)
  
  -- Set rendering parameters
  local renderParams = {
    x = params.xRotation,
    y = params.yRotation,
    z = params.zRotation,
    fovDegrees = params.fovDegrees or params.fov or (params.depthPerspective and (5 + (75-5)*(params.depthPerspective/100))) or 45,
    orthogonal = params.orthogonalView,
    pixelSize = 1,
    middlePoint = middlePoint,
    canvasSize = params.canvasSize,
    sprite = sprite,
    scaleLevel = params.scaleLevel / 8 -- Convert scale level to previous zoom factor format
  }
  
  -- Render the model
  local previewImage = previewRenderer.renderVoxelModel(voxelModel, renderParams)
  
  -- Force redraw of canvas without resizing dialog
  dlg:repaint()
  
  -- Update model info display
  dlg:modify{
    id = "modelInfo", 
    text = "Voxel count: " .. #voxelModel .. "\nModel size: " .. 
           middlePoint.sizeX .. "×" .. 
           middlePoint.sizeY .. "×" .. 
           middlePoint.sizeZ .. " voxels\n" ..
           "Scale: " .. string.format("%.0f%%", params.scaleLevel * 100)
  }
  
  -- Update control dialog if it exists
  if params.controlsDialog then
    params.controlsDialog:modify{id="xRotation", value=params.xRotation}
    params.controlsDialog:modify{id="yRotation", value=params.yRotation}
    params.controlsDialog:modify{id="zRotation", value=params.zRotation}
    params.controlsDialog:modify{id="depthPerspective", value=params.depthPerspective}
    params.controlsDialog:modify{id="orthogonalView", selected=params.orthogonalView}
    params.controlsDialog:modify{id="scaleSlider", value=params.scaleLevel}
    params.controlsDialog:modify{id="scaleLabel", text="Scale: " .. string.format("%.0f%%", params.scaleLevel * 100)}
    if params.fovDegrees then
      params.controlsDialog:modify{id="depthPerspective", value=math.floor(params.fovDegrees)}
    elseif params.depthPerspective then
      local fov = 5 + (75-5)*((params.depthPerspective or 50)/100)
      params.controlsDialog:modify{id="depthPerspective", value=math.floor(fov)}
    end
  end
  
  return {
    image = previewImage,
    model = voxelModel,
    dimensions = middlePoint
  }
end

-- Creates an animation of the model rotating around a selected axis
function previewUtils.createAnimation(voxelModel, modelDimensions, params)
  if not voxelModel or #voxelModel == 0 then
    app.alert("No voxels to animate!")
    return false
  end
  
  local previewRenderer = getPreviewRenderer()
  local mathUtils = getMathUtils()
  local rotation = getRotation()
  
  local sprite = app.activeSprite
  if not sprite then
    app.alert("No active sprite!")
    return false
  end

  -- REPLACED: step/angle setup (adds startAngle & totalRotation)
  local steps        = tonumber(params.animationSteps) or 36
  local startAngle   = tonumber(params.startAngle) or 0
  local totalRotation= tonumber(params.totalRotation) or 360
  local perStep      = totalRotation / steps
  local frameDuration = math.ceil(1440 / steps)
  -- Pass through FOV/perspective mode for animation frames
  local fovDegrees = params.fovDegrees or (params.depthPerspective and (5 + (75-5)*(params.depthPerspective/100))) or 45
  local orthogonal = params.orthogonalView
  local perspectiveScaleRef = params.perspectiveScaleRef or "middle"
  -- Base orientation (matrix + Euler) at animation start
  local baseMatrix = params.rotationMatrix or mathUtils.createRotationMatrix(
    params.xRotation or 0,
    params.yRotation or 0,
    params.zRotation or 0
  )
  local baseEuler = {
    x = params.xRotation or 0,
    y = params.yRotation or 0,
    z = params.zRotation or 0
  }
  
  local baseFilename = "animation"
  if sprite.filename then
    baseFilename = app.fs.fileName(sprite.filename):gsub("%.%w+$", "")
  end
  
  -- Create a new sprite for the animation
  local canvasSize = 300 -- Default size
  if modelDimensions then
    local diagonal = math.sqrt(modelDimensions.sizeX^2 + modelDimensions.sizeY^2 + modelDimensions.sizeZ^2)
    canvasSize = math.max(150, math.floor(diagonal * 5))
  end
  local animSprite = Sprite(canvasSize, canvasSize, ColorMode.RGB)
  if sprite.colorMode == ColorMode.INDEXED or sprite.colorMode == ColorMode.RGB then
    -- Copy palette from original sprite
    for i = 0, #sprite.palettes[1]-1 do
      local color = sprite.palettes[1]:getColor(i)
      animSprite.palettes[1]:setColor(i, color)
    end
  end
  
  app.transaction(function()
    -- Remove the default layer and create a new one
    animSprite:deleteLayer("Layer 1")
    local layer = animSprite:newLayer()
    layer.name = "Voxel Model"

    for frame = 0, steps - 1 do
      if frame > 0 then animSprite:newFrame() end
      local angle = startAngle + frame * perStep
      local ax = params.animationAxis
      local frameMatrix
      if ax == "X" or ax == "Y" or ax == "Z" then
        -- Apply absolute model-space rotation relative to starting orientation
        -- Use applyAbsoluteRotation on the baseMatrix with per-axis delta to keep co-dependent order
        if ax == "X" then
          frameMatrix = rotation.applyAbsoluteRotation(baseMatrix, angle, 0, 0)
        elseif ax == "Y" then
          frameMatrix = rotation.applyAbsoluteRotation(baseMatrix, 0, angle, 0)
        else
          frameMatrix = rotation.applyAbsoluteRotation(baseMatrix, 0, 0, angle)
        end
       elseif ax == "Pitch" or ax == "Yaw" or ax == "Roll" then
         local pitch, yaw, roll = 0, 0, 0
         if ax == "Pitch" then pitch = angle elseif ax == "Yaw" then yaw = angle else roll = angle end
         -- Apply as relative (camera-space) increment from base each frame
         frameMatrix = mathUtils.applyRelativeRotation(baseMatrix, pitch, yaw, roll)
       else
         frameMatrix = baseMatrix
       end

      -- Convert matrix to Euler for renderer (previewRenderer ignores direct matrix)
      local e = mathUtils.matrixToEuler(frameMatrix)

      local renderParams = {
        x = e.x, y = e.y, z = e.z,
        fovDegrees = fovDegrees,
        orthogonal = orthogonal,
        perspectiveScaleRef = perspectiveScaleRef,
        pixelSize = 1,
        middlePoint = modelDimensions,
        canvasSize = params.canvasSize,
        sprite = sprite,
        scaleLevel = params.scaleLevel,
        fxStack = params.fxStack,
        shadingMode = params.shadingMode,
        lighting = params.lighting,              -- propagate dynamic lighting
        viewDir = params.viewDir or {0,0,1}
      }

      local frameImage = previewRenderer.renderVoxelModel(voxelModel, renderParams)
      local cel = animSprite:newCel(layer, frame + 1, frameImage)
      local offsetX = math.floor((canvasSize - frameImage.width) / 2)
      local offsetY = math.floor((canvasSize - frameImage.height) / 2)
      cel.position = Point(offsetX, offsetY)
      animSprite.frames[frame + 1].duration = frameDuration / 1000
    end
    
    -- Set animation properties
    animSprite.filename = baseFilename .. "_" .. params.animationAxis
  end)
  
  app.activeSprite = animSprite
  app.command.PlayAnimation()
  app.alert(string.format(
    "Animation created with %d frames (%.2f° per frame, total %d°, %d ms/frame)",
    steps, perStep, totalRotation, frameDuration
  ))
  return true
end

return previewUtils