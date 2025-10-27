-- viewer.lua
-- Main model viewer orchestration - entry point and dialog lifecycle
-- Dependencies: Loaded via AseVoxel namespace

local viewer = {}

-- Access dependencies through global namespace
local function getDialogManager()
  return AseVoxel.dialog.dialog_manager
end

local function getViewerState()
  return AseVoxel.viewerState
end

local function getMainDialog()
  return AseVoxel.dialog.main_dialog
end

local function getPreviewDialog()
  return AseVoxel.dialog.preview_dialog
end

local function getViewerCore()
  return AseVoxel.viewerCore
end

local function getPreviewRenderer()
  return AseVoxel.render.preview_renderer
end

local function getMathUtils()
  return AseVoxel.mathUtils
end

local function getRotation()
  return AseVoxel.math.rotation
end

local function getFxStack()
  return AseVoxel.fxStack
end

-- Open the AseVoxel model viewer
function viewer.open()
  local dialogueManager = getDialogManager()
  local viewerState = getViewerState()
  local mainDialog = getMainDialog()
  local previewDialog = getPreviewDialog()
  local viewerCore = getViewerCore()
  local previewRenderer = getPreviewRenderer()
  local mathUtils = getMathUtils()
  local rotation = getRotation()
  local fxStack = getFxStack()
  
  -- First, ensure any existing orphaned dialogs are closed
  if dialogueManager and dialogueManager.controlsDialog then
    pcall(function()
      dialogueManager.controlsDialog:close()
      dialogueManager.controlsDialog = nil
    end)
  end
  
  -- Close any existing preview windows
  if dialogueManager.previewDialog then
    pcall(function()
      dialogueManager.previewDialog:close()
      dialogueManager.previewDialog = nil
    end)
  end

  -- Shared state between dialogs
  local previewState = {
    image = nil,
    voxelModel = nil,
    modelDimensions = nil,
    canvasWidth = 200,
    canvasHeight = 200
  }
  
  -- Flag to track whether initial positioning has been done
  local initialPositioningDone = false
  
  -- Create default view parameters
  local viewParams = viewerState.createDefaultParams()
  
  -- Initialize FX stack if available
  if fxStack then
    viewParams.fxStack = fxStack.makeDefaultStack()
  end
  
  -- Initialize the rotation matrix from Euler angles
  dialogueManager.currentRotationMatrix = mathUtils.createRotationMatrix(
    viewParams.eulerX, viewParams.eulerY, viewParams.eulerZ
  )
  
  -- Forward declare schedulePreview so it can be used in helper functions
  local schedulePreview
  
  -- Helper: update layer scroll status label in main dialog
  local function updateLayerScrollStatusLabel()
    local st = previewRenderer.getLayerScrollState()
    local txt
    if not st.enabled then
      txt = "Layer Scroll: OFF"
    else
      txt = string.format("Layer Scroll: Layer %d/%d (Behind=%d, Front=%d)",
        st.focusIndex, st.total, st.behind, st.front)
    end
    local mainDlg = dialogueManager.mainDialog
    if mainDlg then
      pcall(function() mainDlg:modify{ id="layerScrollStatus", text = txt } end)
    end
  end

  -- Helper: rotate the voxel model by 90 degrees
  local function rotateModel(direction)
    local sprite = app.activeSprite
    if not sprite then
      app.alert("No active sprite!")
      return
    end
    
    -- Get the current voxel model
    local voxelModel = previewRenderer.generateVoxelModel(sprite)
    if #voxelModel == 0 then
      app.alert("No voxels to rotate!")
      return
    end
    
    -- Calculate current bounds
    local bounds = previewRenderer.calculateModelBounds(voxelModel)
    local minX = bounds.minX
    local minY = bounds.minY
    local minZ = bounds.minZ
    local width = bounds.maxX - bounds.minX + 1
    local height = bounds.maxY - bounds.minY + 1
    local depth = bounds.maxZ - bounds.minZ + 1
    
    -- Ensure sprite canvas is at least cubic
    local maxDim = math.max(width, height, depth)
    if sprite.width < maxDim or sprite.height < maxDim then
      pcall(function()
        local b = sprite.bounds
        local newBounds = Rectangle(b.x, b.y, math.max(b.width, maxDim), math.max(b.height, maxDim))
        pcall(function() app.command.CanvasSize{ ui = false, bounds = newBounds } end)
      end)
    end

    -- Transform voxel coordinates
    local newVoxels = {}
    for _, voxel in ipairs(voxelModel) do
      local originX = voxel.x - minX
      local originY = voxel.y - minY
      local originZ = voxel.z - minZ
      
      local nx, ny, nz
      
      if direction == "right" then
        nx = originZ
        ny = originY
        nz = width - originX - 1
      elseif direction == "left" then
        nx = depth - originZ - 1
        ny = originY
        nz = originX
      elseif direction == "down" then
        nx = originX
        ny = originZ
        nz = height - originY - 1
      elseif direction == "up" then
        nx = originX
        ny = depth - originZ - 1
        nz = originY
      else
        return
      end
      
      table.insert(newVoxels, {
        x = nx,
        y = ny,
        z = nz,
        color = voxel.color
      })
    end
    
    -- Calculate new bounds
    local newBounds = previewRenderer.calculateModelBounds(newVoxels)
    local newWidth = newBounds.maxX - newBounds.minX + 1
    local newHeight = newBounds.maxY - newBounds.minY + 1
    local newDepth = newBounds.maxZ - newBounds.minZ + 1
    
    -- Create mapping by layer
    local voxelsByLayer = {}
    for _, voxel in ipairs(newVoxels) do
      local z = voxel.z - newBounds.minZ + 1
      if not voxelsByLayer[z] then voxelsByLayer[z] = {} end
      table.insert(voxelsByLayer[z], voxel)
    end
    
    -- Update sprite with transformed voxels
    app.transaction(function()
      -- Remove existing layers
      for i = #sprite.layers, 1, -1 do
        local layer = sprite.layers[i]
        if not layer.isGroup and layer.isVisible then
          sprite:deleteLayer(layer)
        end
      end
      
      -- Create new layers
      for z = 1, newDepth do
        local layer = sprite:newLayer()
        layer.name = "Layer " .. z
        
        local imageW = math.max(newWidth, sprite.width)
        local imageH = math.max(newHeight, sprite.height)
        local image = Image(imageW, imageH, ColorMode.RGB)
        image:clear(Color(0, 0, 0, 0))
        
        local layerVoxels = voxelsByLayer[z] or {}
        for _, voxel in ipairs(layerVoxels) do
          local pixelX = voxel.x - newBounds.minX
          local pixelY = voxel.y - newBounds.minY
          if pixelX >= 0 and pixelX < imageW and pixelY >= 0 and pixelY < imageH then
            local pixelColor = Color(voxel.color.r, voxel.color.g, voxel.color.b, voxel.color.a or 255)
            image:putPixel(pixelX, pixelY, pixelColor)
          end
        end
        
        local frame = app.activeFrame and app.activeFrame.frameNumber or 1
        sprite:newCel(layer, frame, image)
      end
    end)
    
    -- Refresh preview
    schedulePreview(true, "immediate")
    
    -- Show success
    app.alert("Model rotated " .. direction .. " by 90°\n" ..
              "Old dimensions: " .. width .. "×" .. height .. "×" .. depth .. "\n" ..
              "New dimensions: " .. newWidth .. "×" .. newHeight .. "×" .. newDepth)
  end

  -- Helper: draw light cone overlay (debug visualization)
  local function drawLightConeOverlay(overlayImg, previewImage, voxelModel, modelDimensions, viewParams, isRotating)
    if not overlayImg or not previewImage or not voxelModel or not modelDimensions then return end
    local L = viewParams.lighting or {}
    
    -- Fixed debug constants
    local dbgLength = 1.5
    local dbgSamples = 24

    -- Compute model geometry
    local mw = modelDimensions.sizeX
    local mh = modelDimensions.sizeY
    local md = modelDimensions.sizeZ
    local maxDimension = math.max(mw, mh, md)
    local diag = math.sqrt(mw*mw + mh*mh + md*md)
    local modelRadius = 0.5 * diag
    local middlePointLocal = { 
      x = modelDimensions.x or 0, 
      y = modelDimensions.y or 0, 
      z = modelDimensions.z or 0 
    }

    -- Recompute voxel size & camera position
    local width = overlayImg.width
    local height = overlayImg.height
    local baseUnitSize = 1
    local voxelSize = math.max(1, baseUnitSize * (viewParams.scaleLevel or 1))
    local maxAllowed = math.min(width, height) * 0.9
    if voxelSize * maxDimension > maxAllowed and maxDimension > 0 then
      voxelSize = voxelSize * (maxAllowed / (voxelSize * maxDimension))
    end
    local centerX = width / 2
    local centerY = height / 2
    local cameraDistance = maxDimension * 5
    local cameraPos = {
      x = middlePointLocal.x,
      y = middlePointLocal.y,
      z = middlePointLocal.z + cameraDistance
    }

    -- Build depth map from voxels
    local depthMap = {}
    for i, v in ipairs(voxelModel) do
      local t = rotation.transformVoxel(v, {
        middlePoint = middlePointLocal,
        xRotation = viewParams.xRotation,
        yRotation = viewParams.yRotation,
        zRotation = viewParams.zRotation
      })
      local sx = math.floor(centerX + (t.x - middlePointLocal.x) * voxelSize + 0.5)
      local sy = math.floor(centerY + (t.y - middlePointLocal.y) * voxelSize + 0.5)
      if sx >= 0 and sx < width and sy >= 0 and sy < height then
        local dx = t.x - cameraPos.x
        local dy = t.y - cameraPos.y
        local dz = t.z - cameraPos.z
        local dd = dx*dx + dy*dy + dz*dz
        local key = sy * width + sx
        if not depthMap[key] or dd < depthMap[key] then depthMap[key] = dd end
      end
    end

    -- Light geometry computation
    local function computeLightDir(yaw, pitch)
      local yawRad = math.rad(yaw or 25)
      local pitchRad = math.rad(pitch or 25)
      local cosYaw = math.cos(yawRad)
      local sinYaw = math.sin(yawRad)
      local cosPitch = math.cos(pitchRad)
      local sinPitch = math.sin(pitchRad)
      return { x = cosYaw * cosPitch, y = sinPitch, z = sinYaw * cosPitch }
    end

    local camLight = computeLightDir(L.yaw or 25, L.pitch or 25)
    local camMag = math.sqrt(camLight.x*camLight.x + camLight.y*camLight.y + camLight.z*camLight.z)
    if camMag > 1e-6 then 
      camLight.x, camLight.y, camLight.z = camLight.x/camMag, camLight.y/camMag, camLight.z/camMag 
    end

    -- Map to model space
    local rotM = mathUtils.createRotationMatrix(viewParams.xRotation or 0, viewParams.yRotation or 0, viewParams.zRotation or 0)
    local invRot = mathUtils.transposeMatrix(rotM)
    local lightModel = {
      x = invRot[1][1] * camLight.x + invRot[1][2] * camLight.y + invRot[1][3] * camLight.z,
      y = invRot[2][1] * camLight.x + invRot[2][2] * camLight.y + invRot[2][3] * camLight.z,
      z = invRot[3][1] * camLight.x + invRot[3][2] * camLight.y + invRot[3][3] * camLight.z
    }
    local lm = math.sqrt(lightModel.x*lightModel.x + lightModel.y*lightModel.y + lightModel.z*lightModel.z)
    if lm > 1e-6 then 
      lightModel.x, lightModel.y, lightModel.z = lightModel.x/lm, lightModel.y/lm, lightModel.z/lm 
    end

    -- Cone geometry
    local diaPct = (L.diameter or 100) / 100
    local baseRadius = math.max(0, diaPct * modelRadius)
    local S = modelRadius
    local rimDistFromCenter = 0
    if baseRadius >= S then
      rimDistFromCenter = 0
      baseRadius = math.min(baseRadius, S * 0.999)
    else
      rimDistFromCenter = math.sqrt(math.max(0, S*S - baseRadius*baseRadius))
    end

    local baseCenter = {
      x = middlePointLocal.x + lightModel.x * rimDistFromCenter,
      y = middlePointLocal.y + lightModel.y * rimDistFromCenter,
      z = middlePointLocal.z + lightModel.z * rimDistFromCenter
    }

    local desiredApexDist = dbgLength * modelRadius
    local apexDist = math.max(desiredApexDist, rimDistFromCenter + 1e-3)
    local apexWorld = {
      x = middlePointLocal.x + lightModel.x * apexDist,
      y = middlePointLocal.y + lightModel.y * apexDist,
      z = middlePointLocal.z + lightModel.z * apexDist
    }

    -- Rim points
    local N = dbgSamples
    local rimWorld = {}
    for i = 0, N-1 do
      local theta = (i / N) * (2 * math.pi)
      local axis = { x = -lightModel.x, y = -lightModel.y, z = -lightModel.z }
      local up = math.abs(axis.y) < 0.99 and {x=0,y=1,z=0} or {x=1,y=0,z=0}
      local ux = up.y * axis.z - up.z * axis.y
      local uy = up.z * axis.x - up.x * axis.z
      local uz = up.x * axis.y - up.y * axis.x
      local umag = math.sqrt(ux*ux + uy*uy + uz*uz)
      if umag < 1e-6 then umag = 1 end
      ux, uy, uz = ux/umag, uy/umag, uz/umag
      local vx = axis.y * uz - axis.z * uy
      local vy = axis.z * ux - axis.x * uz
      local vz = axis.x * uy - axis.y * ux
      local rwx = baseCenter.x + baseRadius * (math.cos(theta) * ux + math.sin(theta) * vx)
      local rwy = baseCenter.y + baseRadius * (math.cos(theta) * uy + math.sin(theta) * vy)
      local rwz = baseCenter.z + baseRadius * (math.cos(theta) * uz + math.sin(theta) * vz)
      rimWorld[#rimWorld+1] = { x = rwx, y = rwy, z = rwz }
    end

    -- Project apex & rim
    local apexProj = {}
    local axT = rotation.transformVoxel({ x = apexWorld.x, y = apexWorld.y, z = apexWorld.z }, {
      middlePoint = middlePointLocal,
      xRotation = viewParams.xRotation, yRotation = viewParams.yRotation, zRotation = viewParams.zRotation
    })
    apexProj.x = math.floor(centerX + (axT.x - middlePointLocal.x) * voxelSize + 0.5)
    apexProj.y = math.floor(centerY + (axT.y - middlePointLocal.y) * voxelSize + 0.5)
    local adx = axT.x - cameraPos.x; local ady = axT.y - cameraPos.y; local adz = axT.z - cameraPos.z
    local apexDepth = adx*adx + ady*ady + adz*adz

    local rimProj = {}
    for i, rw in ipairs(rimWorld) do
      local rt = rotation.transformVoxel({ x = rw.x, y = rw.y, z = rw.z }, {
        middlePoint = middlePointLocal,
        xRotation = viewParams.xRotation, yRotation = viewParams.yRotation, zRotation = viewParams.zRotation
      })
      local sx = math.floor(centerX + (rt.x - middlePointLocal.x) * voxelSize + 0.5)
      local sy = math.floor(centerY + (rt.y - middlePointLocal.y) * voxelSize + 0.5)
      local dx = rt.x - cameraPos.x; local dy = rt.y - cameraPos.y; local dz = rt.z - cameraPos.z
      local dd = dx*dx + dy*dy + dz*dz
      rimProj[#rimProj+1] = { x = sx, y = sy, depth = dd }
    end

    -- Draw cone wireframe
    local lc = L.lightColor or Color(255,255,255)
    local lightCol = { r = lc.red or lc.r or 255, g = lc.green or lc.g or 255, b = lc.blue or lc.b or 255 }
    local rimColor = Color(lightCol.r, lightCol.g, lightCol.b, 255)
    local genLineColor = Color(lightCol.r, lightCol.g, lightCol.b, 255)

    -- Helper: depth-aware line drawing
    local function drawLineDepth(img, x0, y0, d0, x1, y1, d1, color, depthMap)
      local dx = x1 - x0
      local dy = y1 - y0
      local steps = math.max(math.abs(dx), math.abs(dy))
      if steps == 0 then
        local sx = math.floor(x0 + 0.5)
        local sy = math.floor(y0 + 0.5)
        if sx >= 0 and sx < img.width and sy >= 0 and sy < img.height then
          local key = sy * img.width + sx
          local modelDepth = depthMap[key] or math.huge
          if d0 < modelDepth then img:putPixel(sx, sy, color) end
        end
        return
      end
      for i = 0, steps do
        local t = i / steps
        local sx = math.floor(x0 + dx * t + 0.5)
        local sy = math.floor(y0 + dy * t + 0.5)
        local sd = (1 - t) * d0 + t * d1
        if sx >= 0 and sx < img.width and sy >= 0 and sy < img.height then
          local key = sy * img.width + sx
          local modelDepth = depthMap[key] or math.huge
          if sd < modelDepth then img:putPixel(sx, sy, color) end
        end
      end
    end

    -- Draw rim edges
    for i = 1, #rimProj do
      local a = rimProj[i]
      local b = rimProj[(i % #rimProj) + 1]
      drawLineDepth(overlayImg, a.x, a.y, a.depth, b.x, b.y, b.depth, rimColor, depthMap)
    end
    
    -- Draw generating lines
    for i = 1, #rimProj do
      local p = rimProj[i]
      drawLineDepth(overlayImg, apexProj.x, apexProj.y, apexDepth, p.x, p.y, p.depth, genLineColor, depthMap)
    end
    
    -- Draw apex point
    local sx, sy = apexProj.x, apexProj.y
    if sx >= 0 and sx < width and sy >= 0 and sy < height then
      local key = sy * width + sx
      local modelDepth = depthMap[key] or math.huge
      if apexDepth < modelDepth then
        overlayImg:putPixel(sx, sy, Color(lightCol.r, lightCol.g, lightCol.b, 255))
      end
    end
  end

  -- Schedule preview update (implementation)
  schedulePreview = function(resetPan, source)
    viewerCore.requestPreview(
      dialogueManager.mainDialog,
      viewParams,
      dialogueManager.controlsDialog,
      source or "ui",
      function(result)
        if result then
          previewState.voxelModel = result.model
          previewState.image = result.image
          previewState.modelDimensions = result.dimensions
          previewState.resetPan = resetPan
          previewState.viewParams = viewParams
          
          -- Update UI with result
          local mainDlg = dialogueManager.mainDialog
          local previewDlg = dialogueManager.previewDialog
          viewerState.applyRenderResult(result, mainDlg, previewDlg, previewState)
        end
      end
    )
  end

  -- Create main dialog
  local mainDlg = mainDialog.create(
    viewParams, 
    schedulePreview, 
    rotateModel, 
    updateLayerScrollStatusLabel, 
    previewState  -- Pass entire previewState instead of individual model/dimensions
  )
  
  -- Create preview dialog
  local previewDlg = previewDialog.create(
    viewParams, 
    previewState.canvasWidth, 
    previewState.canvasHeight, 
    schedulePreview, 
    updateLayerScrollStatusLabel, 
    drawLightConeOverlay, 
    previewState
  )

  -- Store references
  dialogueManager.mainDialog = mainDlg
  dialogueManager.previewDialog = previewDlg
  
  -- Initial preview update
  schedulePreview(true, "immediate")
  
  -- Show both dialogs
  mainDlg:show{ wait = false }
  previewDlg:show{ wait = false }

  -- Position dialogs
  local windowWidth = app.window.width
  local windowHeight = app.window.height
  app.command.Refresh()

  local mainBounds = mainDlg.bounds
  local previewBounds = previewDlg.bounds

  local totalHeight = mainBounds.height + previewBounds.height + 10
  local startY = math.max(10, (windowHeight - totalHeight) / 2)

  local centerX = (windowWidth - previewBounds.width) / 2
  previewDlg.bounds = Rectangle(centerX, startY, previewBounds.width, previewBounds.height)

  mainDlg.bounds = Rectangle(
    (windowWidth - mainBounds.width) / 2, 
    startY + previewBounds.height + 10, 
    mainBounds.width, 
    mainBounds.height
  )
  
  initialPositioningDone = true
end

return viewer
