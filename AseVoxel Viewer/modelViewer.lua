-- modelViewer.lua
local mathUtils = require("mathUtils")
local viewerCore = require("viewerCore")
local dialogueManager = require("dialogueManager")
local imageUtils = require("imageUtils")
local rotation = require("rotation")
local previewRenderer = require("previewRenderer")
local fxStackDialog = require("fxStackDialog")
local fxStack = require("fxStack")
local dialogUtils = require("dialogUtils")
local spriteWatcher = require("spriteWatcher") -- ADDED
local nativeBridge_ok, nativeBridge = pcall(require, "nativeBridge")


-- PATCH: shared (module-level) viewParams used by new simplified openModelViewer
local viewParams = {
  xRotation=315, yRotation=324, zRotation=29,
  eulerX=315, eulerY=324, eulerZ=29,
  depthPerspective=50,
  orthogonalView=false,
  scaleLevel=1.0,
  canvasSize=200,
  fxStack=nil,        -- will be auto-migrated/created elsewhere if needed
  shadingMode="Stack"
}

-- Ensure table for new API
local modelViewer = {}

-- RENAMED legacy function to preserve original implementation
local function openModelViewer()
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

  -- Create both dialogs
  local mainDlg = Dialog("AseVoxel - Controls")
  local previewDlg = Dialog("AseVoxel - Preview")

  -- Store reference to main dialog in the global state
  dialogueManager.mainDialog = mainDlg
  dialogueManager.previewDialog = previewDlg
  
  local previewImage = nil -- Store the dynamically updated image
  local voxelModel = nil -- Store the generated voxel model
  local modelDimensions = nil -- Store model size for adaptive display
  local defaultScaleLevel = 3 -- Default scale level at 300%
  
  -- Preview window state - will be calculated based on model size
  local previewCanvasWidth = 200  -- Initial default size
  local previewCanvasHeight = 200 -- Initial default size
  
  -- Flag to track whether initial positioning has been done
  local initialPositioningDone = false
  
  -- View parameters
  local viewParams = {
    xRotation = 315,
    yRotation = 324,
    zRotation = 29,
    -- Add canonical Euler angles as the master rotation source
    eulerX = 315,
    eulerY = 324,
    eulerZ = 29,
    depthPerspective = 50, -- legacy kept
    fovDegrees = 5 + (75-5)*(50/100), -- initialize new FOV
    orthogonalView = false,
    backgroundColor = Color(128, 128, 128), -- Will be calculated based on model
    scaleLevel = defaultScaleLevel,
    relativeX = 0,
    relativeY = 0,
    relativeZ = 0,
    
    -- Outline parameters
    enableOutline = false,
    outlineColor = Color(0, 0, 0), -- Black outline by default
    outlinePattern = "circle", -- Default outline pattern
    fxStack = fxStack and fxStack.makeDefaultStack() or { modules = {} },
    shadingMode = "Basic",         -- DEFAULT NOW BASIC
    basicShadeIntensity = 50,
    basicLightIntensity = 50,
    -- Dynamic lighting parameters
    lighting = {
      -- Patch 3.75.x defaults: head‑on light (pitch 0, yaw 90) & rim off
      pitch = 0,
      yaw = 90,
      diffuse = 60,
      diameter = 100,
      ambient = 30,
      lightColor = Color(255, 255, 255), -- white
      rimEnabled = false,
      previewRotateEnabled = false
    },
    -- Light cone (debug) UI removed by Patch 1 (fixed constants used internally)
  }
  
  -- Initialize the rotation matrix from Euler angles
  dialogueManager.currentRotationMatrix = mathUtils.createRotationMatrix(
    viewParams.eulerX, viewParams.eulerY, viewParams.eulerZ
  )
  
  -- Mouse interaction variables
  local isDragging = false
  local isRotating = false
  local lastX = 0
  local lastY = 0
  local mouseSensitivity = 1.0
  local previewOffsetX = 0
  local previewOffsetY = 0
  -- Patch 3.75.1: accumulators & clamping to reduce mouse event spam during interactive drags
  -- Improves both light-preview rotation and model rotation responsiveness by quantizing input.
  local accumLightYaw = 0.0
  local accumLightPitch = 0.0
  local accumModelYaw = 0.0
  local accumModelPitch = 0.0
  local maxMouseDelta = 5      -- clamp per-event mouse delta (pixels)
  local applyThreshold = 0.5   -- degrees: apply accumulated rotation when exceeded

  -- Lazy remote renderer (prevents auto websocket prompt)
  local remoteRenderer
  local function getRemote()
    if remoteRenderer ~= nil then return remoteRenderer end
    local ok, mod = pcall(require, "remoteRenderer")
    if ok then remoteRenderer = mod end
    return remoteRenderer
  end

  local function remoteStatusText()
    local rr = getRemote()
    if not rr then return "Remote: helper not loaded" end
    local st = rr.getStatus()
    local enabled = st.enabled and "ON" or "OFF"
    local connected = st.connected and "connected" or "disconnected"
    return string.format("Remote: %s (%s) %s", enabled, connected, st.url or "")
  end

  -- Calculate the background size based on model dimensions
  local function calculateBackgroundSize(dimensions)
    if not dimensions then
      return previewCanvasWidth, previewCanvasHeight  -- Default fallback
    end
    
    -- Apply the formula: 5*sqrt(x^2+y^2+z^2)*1.5 rounded
    local diagonal = math.sqrt(
      dimensions.sizeX^2 + 
      dimensions.sizeY^2 + 
      dimensions.sizeZ^2
    )
    
    -- Calculate size without enforcing a minimum
    local size = math.floor(5 * diagonal * 1.5 + 0.5)
    
    -- No minimum size constraint
    return size, size  -- Square background
  end
  
  -- Helper functions for the main dialog
  local function applyRenderResult(result, resetPan)
    if not result then return end
    voxelModel = result.model
    previewImage = result.image
    modelDimensions = result.dimensions
    local fovText = "Ortho"
    if viewParams and not viewParams.orthogonalView and viewParams.fovDegrees then
      fovText = string.format("FOV: %.0f°", viewParams.fovDegrees)
    end
    pcall(function()
      if mainDlg then
        mainDlg:modify{ id = "fovInfo", text = fovText }
      end
    end)
    local lastPerf = result.metrics or viewerCore._lastMetrics
    local adaptive = viewerCore.getAdaptiveStats()

    -- recalc bg size:
    local bgWidth, bgHeight = calculateBackgroundSize(modelDimensions)
    if previewCanvasWidth ~= bgWidth or previewCanvasHeight ~= bgHeight then
      previewCanvasWidth, previewCanvasHeight = bgWidth, bgHeight
      previewDlg:modify{
        id="previewCanvas",
        width=previewCanvasWidth,
        height=previewCanvasHeight
      }
      if resetPan then
        previewOffsetX = 0
        previewOffsetY = 0
      end
    end
    previewDlg:repaint()

    -- Live-update main dialog model info labels (voxel count, dimensions, scale)
    pcall(function()
      if mainDlg then
        local count = 0
        if voxelModel then count = #voxelModel end
        mainDlg:modify{
          id = "modelInfo_count",
          text = "Voxel count: " .. tostring(count)
        }
        local dims = modelDimensions or { sizeX = 0, sizeY = 0, sizeZ = 0 }
        mainDlg:modify{
          id = "modelInfo_dims",
          text = string.format("Model size: %d×%d×%d voxels", dims.sizeX, dims.sizeY, dims.sizeZ)
        }
        mainDlg:modify{
          id = "modelInfo_scale",
          text = string.format("Scale: %.0f%%", (viewParams.scaleLevel or 1) * 100)
        }
        -- Update performance labels if present
        local m = lastPerf or {}
        local lastMs = (m.t_total_ms and math.floor(m.t_total_ms+0.5)) or nil
        local p75 = (adaptive.p75 and math.floor(adaptive.p75+0.5)) or nil
        local interval = adaptive.interval
        pcall(function()
          mainDlg:modify{
            id = "perf_last",
            text = string.format("Last render: %s",
              lastMs and (tostring(lastMs).." ms") or "n/a")
          }
          mainDlg:modify{
            id = "perf_throttle",
            text = string.format("Adaptive throttle: %d ms (p75=%s)",
              interval or 0,
              p75 and (tostring(p75).." ms") or "n/a")
          }
          mainDlg:modify{
            id = "perf_counts",
            text = string.format("Voxels=%d Faces: drawn=%d, backface=%d, adj-cull=%d",
              m.voxels or 0, m.facesDrawn or 0, m.facesBackfaced or 0, m.facesCulledAdj or 0)
          }
        end)
      end
    end)
  end

  -- Helper: draw single-pixel line on an Image using Bresenham
  local function drawLineOnImage(img, x0, y0, x1, y1, color)
    local dx = math.abs(x1 - x0)
    local sx = x0 < x1 and 1 or -1
    local dy = -math.abs(y1 - y0)
    local sy = y0 < y1 and 1 or -1
    local err = dx + dy
    while true do
      if x0 >= 0 and x0 < img.width and y0 >= 0 and y0 < img.height then
        img:putPixel(x0, y0, color)
      end
      if x0 == x1 and y0 == y1 then break end
      local e2 = 2 * err
      if e2 >= dy then err = err + dy; x0 = x0 + sx end
      if e2 <= dx then err = err + dx; y0 = y0 + sy end
    end
  end
  -- Depth-aware line rasterizer: interpolates depth and respects model depth map
  local function drawLineDepth(img, x0, y0, d0, x1, y1, d1, color, depthMap)
    -- Bresenham-like interpolation using step count = max(|dx|,|dy|)
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

  -- Compute light direction matching previewRenderer.computeLightDirection
  local function computeLightDir(yaw, pitch)
    local yawRad = math.rad(yaw or 25)
    local pitchRad = math.rad(pitch or 25)
    local cosYaw = math.cos(yawRad)
    local sinYaw = math.sin(yawRad)
    local cosPitch = math.cos(pitchRad)
    local sinPitch = math.sin(pitchRad)
    return { x = cosYaw * cosPitch, y = sinPitch, z = sinYaw * cosPitch }
  end

  -- Draw debug light cone into an overlay Image that matches previewImage size.
  -- Uses approximate per-pixel occlusion by comparing interpolated cone depth to a model depth map.
  local function drawLightConeOverlay(overlayImg)
    if not overlayImg or not previewImage or not voxelModel or not modelDimensions then return end
    local L = viewParams.lighting or {}
    -- Fixed constants (was debugCone)
    local dbgLength = 1.5
    local dbgSamples = 24

    -- Compute model geometry
    local mw = modelDimensions.sizeX
    local mh = modelDimensions.sizeY
    local md = modelDimensions.sizeZ
    local maxDimension = math.max(mw, mh, md)
    local diag = math.sqrt(mw*mw + mh*mh + md*md)
    local modelRadius = 0.5 * diag
    local middlePointLocal = { x = modelDimensions.x or 0, y = modelDimensions.y or 0, z = modelDimensions.z or 0 }

    -- Recompute voxelSize & camera pos consistent with previewRenderer.renderPreview logic for this preview image
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

    -- Build a depth map from model voxels: minimal squared distance to camera per screen pixel
    local depthMap = {} -- key = y*width + x -> depth (squared dist)
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

    -- Light geometry: camera-space light mapped into model/world space so cone stays camera-fixed
    local camLight = computeLightDir(L.yaw or 25, L.pitch or 25)
    local camMag = math.sqrt(camLight.x*camLight.x + camLight.y*camLight.y + camLight.z*camLight.z)
    if camMag > 1e-6 then camLight.x, camLight.y, camLight.z = camLight.x/camMag, camLight.y/camMag, camLight.z/camMag end

    -- Map camera-space light into model-space using current view rotation
    local rotM = mathUtils.createRotationMatrix(viewParams.xRotation or 0, viewParams.yRotation or 0, viewParams.zRotation or 0)
    local invRot = mathUtils.transposeMatrix(rotM)
    local lightModel = {
      x = invRot[1][1] * camLight.x + invRot[1][2] * camLight.y + invRot[1][3] * camLight.z,
      y = invRot[2][1] * camLight.x + invRot[2][2] * camLight.y + invRot[2][3] * camLight.z,
      z = invRot[3][1] * camLight.x + invRot[3][2] * camLight.y + invRot[3][3] * camLight.z
    }
    local lm = math.sqrt(lightModel.x*lightModel.x + lightModel.y*lightModel.y + lightModel.z*lightModel.z)
    if lm > 1e-6 then lightModel.x, lightModel.y, lightModel.z = lightModel.x/lm, lightModel.y/lm, lightModel.z/lm end

    -- Base radius per Q4:A: diameter % of modelRadius
    local diaPct = (L.diameter or 100) / 100
    local baseRadius = math.max(0, diaPct * modelRadius)

    -- Compute rim distance from center so rim is tangent to bounding sphere
    local S = modelRadius
    local rimDistFromCenter = 0
    if baseRadius >= S then
      rimDistFromCenter = 0
      baseRadius = math.min(baseRadius, S * 0.999)
    else
      rimDistFromCenter = math.sqrt(math.max(0, S*S - baseRadius*baseRadius))
    end

    -- Base center on axis from center toward the lightModel direction
    local baseCenter = {
      x = middlePointLocal.x + lightModel.x * rimDistFromCenter,
      y = middlePointLocal.y + lightModel.y * rimDistFromCenter,
      z = middlePointLocal.z + lightModel.z * rimDistFromCenter
    }

    -- Apex placement (distance from center = modelRadius * length multiplier, ensure beyond base)
    local desiredApexDist = dbgLength * modelRadius
    local apexDist = math.max(desiredApexDist, rimDistFromCenter + 1e-3)
    local apexWorld = {
      x = middlePointLocal.x + lightModel.x * apexDist,
      y = middlePointLocal.y + lightModel.y * apexDist,
      z = middlePointLocal.z + lightModel.z * apexDist
    }

    -- Axis for cone (points from apex toward model)
    local axis = { x = -lightModel.x, y = -lightModel.y, z = -lightModel.z }

    -- Rim points: sample N points around the cone rim at equal angles
    local N = dbgSamples
    local rimWorld = {}
    for i = 0, N-1 do
      local theta = (i / N) * (2 * math.pi)
      -- Build orthonormal basis (u,v) perpendicular to axis
      -- Choose arbitrary vector not parallel to axis
      local up = math.abs(axis.y) < 0.99 and {x=0,y=1,z=0} or {x=1,y=0,z=0}
      -- u = normalize(cross(up, axis))
      local ux = up.y * axis.z - up.z * axis.y
      local uy = up.z * axis.x - up.x * axis.z
      local uz = up.x * axis.y - up.y * axis.x
      local umag = math.sqrt(ux*ux + uy*uy + uz*uz)
      if umag < 1e-6 then umag = 1 end
      ux, uy, uz = ux/umag, uy/umag, uz/umag
      -- v = cross(axis, u)
      local vx = axis.y * uz - axis.z * uy
      local vy = axis.z * ux - axis.x * uz
      local vz = axis.x * uy - axis.y * ux
      -- rim point
     local rwx = baseCenter.x + baseRadius * (math.cos(theta) * ux + math.sin(theta) * vx)
     local rwy = baseCenter.y + baseRadius * (math.cos(theta) * uy + math.sin(theta) * vy)
     local rwz = baseCenter.z + baseRadius * (math.cos(theta) * uz + math.sin(theta) * vz)
      rimWorld[#rimWorld+1] = { x = rwx, y = rwy, z = rwz }
    end

    -- Project apex & rim to screen and compute depths
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

    -- Colors
    local lc = L.lightColor or Color(255,255,255)
    local lightCol = { r = lc.red or lc.r or 255, g = lc.green or lc.g or 255, b = lc.blue or lc.b or 255 }
    local rimColor = Color(lightCol.r, lightCol.g, lightCol.b, 255)
    local genLineColor = Color(lightCol.r, lightCol.g, lightCol.b, 255)
    local fillAlpha = 0.5

    -- Draw rim edges (depth-tested)
    for i = 1, #rimProj do
      local a = rimProj[i]
      local b = rimProj[(i % #rimProj) + 1]
      drawLineDepth(overlayImg, a.x, a.y, a.depth, b.x, b.y, b.depth, rimColor, depthMap)
    end
    -- Draw generating lines (apex -> rim samples), depth-tested
    for i = 1, #rimProj do
      local p = rimProj[i]
      drawLineDepth(overlayImg, apexProj.x, apexProj.y, apexDepth, p.x, p.y, p.depth, genLineColor, depthMap)
    end
    -- Draw apex point (depth-tested)
    do
      local sx, sy = apexProj.x, apexProj.y
      if sx >= 0 and sx < width and sy >= 0 and sy < height then
        local key = sy * width + sx
        local modelDepth = depthMap[key] or math.huge
        if apexDepth < modelDepth then
          overlayImg:putPixel(sx, sy, Color(lightCol.r, lightCol.g, lightCol.b, 255))
        end
      end
    end

    -- Patch 3.75.3: Skip interior fill while user is actively rotating (model OR light)
    local interactive = isRotating -- middle-button drag active
    if interactive then return end
    -- (Non-interactive) Fill interior using simple nearest-rim interpolation for depth estimation
    -- Build polygon points for point-in-polygon tests
    local poly = {}
    for i, p in ipairs(rimProj) do poly[#poly+1] = { x = p.x + 0.5, y = p.y + 0.5 } end
    -- Bounding box
    local minX, minY, maxX, maxY = math.huge, math.huge, -math.huge, -math.huge
    for _, p in ipairs(rimProj) do
      if p.x < minX then minX = p.x end
      if p.y < minY then minY = p.y end
      if p.x > maxX then maxX = p.x end
      if p.y > maxY then maxY = p.y end
    end
    minX = math.max(0, math.floor(minX)); minY = math.max(0, math.floor(minY))
    maxX = math.min(width-1, math.ceil(maxX)); maxY = math.min(height-1, math.ceil(maxY))

    for y = minY, maxY do
      for x = minX, maxX do
        if previewRenderer.isPointInPolygon(x + 0.5, y + 0.5, poly) then
          -- find nearest rim sample in screen space
          local bestIdx = 1; local bestD = math.huge
          for i, rp in ipairs(rimProj) do
            local dx = (rp.x - x)
            local dy = (rp.y - y)
            local d = dx*dx + dy*dy
            if d < bestD then bestD = d; bestIdx = i end
          end
          local rp = rimProj[bestIdx]
          local rimDist = math.sqrt((rp.x - apexProj.x)^2 + (rp.y - apexProj.y)^2)
          local pixDist = math.sqrt((x - apexProj.x)^2 + (y - apexProj.y)^2)
          local t = 0
          if rimDist > 1e-6 then t = math.max(0, math.min(1, pixDist / rimDist)) end
          local coneDepth = (1 - t) * apexDepth + t * rp.depth
          local key = y * width + x
          local modelDepth = depthMap[key] or math.huge
          if coneDepth < modelDepth then
            -- Blend overlay 50% over preview pixel (fill interior)
            local srcPix = previewImage:getPixel(x, y)
            local sr = app.pixelColor.rgbaR(srcPix)
            local sg = app.pixelColor.rgbaG(srcPix)
            local sb = app.pixelColor.rgbaB(srcPix)
            local fr = math.floor((1 - fillAlpha) * sr + fillAlpha * lightCol.r + 0.5)
            local fg = math.floor((1 - fillAlpha) * sg + fillAlpha * lightCol.g + 0.5)
            local fb = math.floor((1 - fillAlpha) * sb + fillAlpha * lightCol.b + 0.5)
            overlayImg:putPixel(x, y, Color(fr, fg, fb, 255))
          end
        end
      end
    end
  end
  
  local function schedulePreview(resetPan, source)
    viewerCore.requestPreview(
      mainDlg, -- keep main dialog as primary for repaint hooks
      viewParams,
      dialogueManager.controlsDialog,
      source or "ui",
      function(result) applyRenderResult(result, resetPan) end
    )
  end
  
  local function updateBackgroundColor()
    -- Safely recalculate contrast color
    pcall(function()
      if voxelModel and #voxelModel > 0 then
        viewParams.backgroundColor = viewerCore.calculateContrastColor(voxelModel)
        schedulePreview(false, "ui")
      end
    end)
  end
  
  -- Rotate the voxel model by 90 degrees in the specified direction
  -- This transforms the actual sprite layers
  -- IMPORTANT: This function must be defined BEFORE the buttons that use it
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
    
    -- Ensure sprite canvas is at least cubic with side = max(width,height,depth)
    -- (Resize -> then Trim behavior): expand to cube, then rotate, then trim
    local maxDim = math.max(width, height, depth)
    if sprite.width < maxDim or sprite.height < maxDim then
      pcall(function()
        -- Use CanvasSize with bounds to set new canvas size without showing UI.
        -- Keep origin (x,y) the same and only change width/height to at least maxDim.
        local b = sprite.bounds
        local newBounds = Rectangle(b.x, b.y, math.max(b.width, maxDim), math.max(b.height, maxDim))
        -- app.command.CanvasSize accepts a Rectangle in 'bounds'
        pcall(function() app.command.CanvasSize{ ui = false, bounds = newBounds } end)
      end)
    end

    -- Transform voxel coordinates based on rotation direction
    local newVoxels = {}
    for _, voxel in ipairs(voxelModel) do
      -- First adjust to origin by subtracting minimums
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
    
    -- Create a mapping of voxels by layer (Z coordinate)
    local voxelsByLayer = {}
    for _, voxel in ipairs(newVoxels) do
      local z = voxel.z - newBounds.minZ + 1
      if not voxelsByLayer[z] then voxelsByLayer[z] = {} end
      table.insert(voxelsByLayer[z], voxel)
    end
    
    -- Update the sprite with the transformed voxels
    app.transaction(function()
      -- Remove all existing non-group layers
      for i = #sprite.layers, 1, -1 do
        local layer = sprite.layers[i]
        if not layer.isGroup and layer.isVisible then
          sprite:deleteLayer(layer)
        end
      end
      
      -- Create new layers for each Z level
      for z = 1, newDepth do
        local layer = sprite:newLayer()
        layer.name = "Layer " .. z
        
        -- Create an image sized to at least the current sprite canvas to avoid clipping
        local imageW = math.max(newWidth, sprite.width)
        local imageH = math.max(newHeight, sprite.height)
        local image = Image(imageW, imageH, ColorMode.RGB)
        image:clear(Color(0, 0, 0, 0))
        
        -- Draw voxels for this layer
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
    
    -- Refresh the preview
    schedulePreview(true, "immediate")
    
    -- Show success message with new dimensions
    app.alert("Model rotated " .. direction .. " by 90°\n" ..
              "Old dimensions: " .. width .. "×" .. height .. "×" .. depth .. "\n" ..
              "New dimensions: " .. newWidth .. "×" .. newHeight .. "×" .. newDepth)
    
    -- After rotation, trim the sprite canvas to the minimal bounding rect that contains pixels.
    pcall(function()
      local minXpix, minYpix = math.huge, math.huge
      local maxXpix, maxYpix = -math.huge, -math.huge
      local frame = app.activeFrame and app.activeFrame.frameNumber or 1
      for _, layer in ipairs(sprite.layers) do
        if not layer.isGroup then
          local cel = layer:cel(frame)
          if cel and cel.image then
            local img = cel.image
            local offX, offY = cel.position.x, cel.position.y
            for y = 0, img.height - 1 do
              for x = 0, img.width - 1 do
                if app.pixelColor.rgbaA(img:getPixel(x, y)) > 0 then
                  local gx = x + offX
                  local gy = y + offY
                  if gx < minXpix then minXpix = gx end
                  if gy < minYpix then minYpix = gy end
                  if gx > maxXpix then maxXpix = gx end
                  if gy > maxYpix then maxYpix = gy end
                end
              end
            end
          end
        end
      end
      if minXpix == math.huge then return end -- nothing to trim
      local trimW = maxXpix - minXpix + 1
      local trimH = maxYpix - minYpix + 1
      -- Use CanvasSize bounds to crop to the computed rectangle (no UI)
      local cropBounds = Rectangle(minXpix, minYpix, trimW, trimH)
      pcall(function() app.command.CanvasSize{ ui = false, bounds = cropBounds, trimOutside = true } end)
    end)
  end
  
  -- Create the main controls dialog with tabs
  
  -- Create the Info tab
  mainDlg:tab{
    id = "infoTab",
    text = "Info"
  }
  
  -- Info Tab Content
  mainDlg:separator{ text = "Model Information" }
  
  -- Model info section - separate labels instead of single multiline text
  mainDlg:label{
    id = "modelInfo_count",
    text = "Voxel count: 0"
  }
  mainDlg:newrow()
  mainDlg:label{
    id = "modelInfo_dims",
    text = "Model size: 0×0×0 voxels"
  }
  mainDlg:newrow()
  mainDlg:label{
    id = "modelInfo_scale",
    text = "Scale: 300%"
  }
  
  -- Add rotation display
  mainDlg:label{
    id = "rotationInfo",
    text = "Euler Space: X=315° Y=324° Z=29°"
  }
  mainDlg:newrow()
  mainDlg:label{
    id = "fovInfo",
    text = (viewParams.orthogonalView and "Ortho") or string.format("FOV: %.0f°", viewParams.fovDegrees or 45)
  }

  -- Performance / Metrics
  mainDlg:separator{ text = "Performance" }
  mainDlg:label{
    id = "perf_last",
    text = "Last render: n/a"
  }
  mainDlg:newrow()
  mainDlg:label{
    id = "perf_throttle",
    text = "Adaptive throttle: n/a"
  }
  mainDlg:newrow()
  mainDlg:label{
    id = "perf_counts",
    text = "Voxels=0 Faces: drawn=0, backface=0, adj-cull=0"
  }

  -- Added control/preview buttons back into Info tab
  mainDlg:separator{ text = "Windows" }
  mainDlg:button{
    id = "openControlsBtn",
    text = "Open Controls Dialog",
    onclick = function()
      if not dialogueManager.controlsDialog then
        dialogueManager.controlsDialog =
          dialogueManager.openControlsDialog(viewParams, viewParams.scaleLevel, function()
            schedulePreview(false, "controls")
          end)
      else
        pcall(function() dialogueManager.controlsDialog:show{ wait=false } end)
      end
    end
  }
  mainDlg:button{
    id = "openPreviewBtn",
    text = "Open Preview Window",
    onclick = function()
      if dialogueManager.previewDialog and dialogueManager.previewDialog.bounds then
        pcall(function() dialogueManager.previewDialog:show{ wait=false } end)
        return
      end
      -- Recreate minimal preview dialog if it was closed
      local newPreview = Dialog("AseVoxel - Preview")
      dialogueManager.previewDialog = newPreview
      previewDlg = newPreview -- reuse local for schedulePreview()
      newPreview:canvas{
        id = "previewCanvas",
        width = previewCanvasWidth,
        height = previewCanvasHeight,
        onpaint = function(ev)
          local ctx = ev.context
          local w,h = ctx.width, ctx.height
          ctx:beginPath()
          ctx:rect(Rectangle(0,0,w,h))
            ctx.color = viewParams.backgroundColor or Color(240,240,240)
          ctx:fill()
          if previewImage then
            local baseOffsetX = math.floor((w - previewImage.width)/2)
            local baseOffsetY = math.floor((h - previewImage.height)/2)
            ctx:drawImage(previewImage, baseOffsetX + previewOffsetX, baseOffsetY + previewOffsetY)
          else
            ctx.color = Color(100,100,100)
            local txt = "Preview will appear here"
            local tw = ctx:measureText(txt).width
            ctx:fillText(txt, (w - tw)/2, h/2)
          end
        end,
        onwheel = function(ev)
          local st = previewRenderer.getLayerScrollState()
          if st.enabled then
            local sprite = app.activeSprite
            if ev.deltaY > 0 then previewRenderer.shiftLayerFocus(1, sprite)
            else previewRenderer.shiftLayerFocus(-1, sprite) end
            schedulePreview(true, "immediate")
            return
          end
          local step = 0.25
          if ev.deltaY > 0 then
            viewParams.scaleLevel = math.max(0.5, viewParams.scaleLevel - step)
          else
            viewParams.scaleLevel = math.min(5.0, viewParams.scaleLevel + step)
          end
          previewOffsetX, previewOffsetY = 0,0
          schedulePreview(true, "immediate")
        end
      }
      newPreview:button{
        id = "closePreviewButton",
        text = "Close Preview",
        onclick = function()
          dialogueManager.previewDialog = nil
          newPreview:close()
        end
      }
      newPreview:show{ wait=false }
      schedulePreview(false, "reopenPreview")
    end
  }
  mainDlg:button{
    id = "refreshPreviewBtn",
    text = "Refresh Preview",
    onclick = function()
      schedulePreview(false, "manual")
    end
  }
  
  -- Create the Export tab
  mainDlg:tab{
    id = "exportTab",
    text = "Export"
  }
  
  -- Export Tab Content
  mainDlg:separator{ text = "Export Options" }
  
  mainDlg:button{
    id = "exportButton",
    text = "Export Model...",
    onclick = function()
      if voxelModel and #voxelModel > 0 then
        dialogueManager.openExportDialog(voxelModel)
      else
        app.alert("No model to export!")
      end
    end
  }
  
  mainDlg:button{
    id = "animateButton",
    text = "Create Animation...",
    onclick = function()
      if voxelModel and #voxelModel > 0 then
        dialogueManager.openAnimationDialog(viewParams, voxelModel, modelDimensions)
      else
        app.alert("No model to animate!")
      end
    end
  }

  -- Ensure viewParams.lighting always exists before animation dialog
  if not viewParams.lighting then
    viewParams.lighting = {
      pitch = 25, yaw = 25, diffuse = 60, diameter = 100,
      ambient = 30, lightColor = Color(255,255,255),
      rimEnabled = true, previewRotateEnabled = false
    }
  end
  
  -- Create the Modeler tab
  mainDlg:tab{
    id = "modelerTab",
    text = "Modeler"
  }
  
  -- Modeler Tab Content
  mainDlg:separator{ text = "Model Transformation" }

  mainDlg:label{ text = "Rotate Model 90°:" }

  mainDlg:newrow()
  mainDlg:button{
    id = "rotateLeft",
    text = "← Left",
    onclick = function()
      local st = previewRenderer.getLayerScrollState()
      if st.enabled then
        mainDlg:modify{ id="layerScrollEnable", selected=false }
        previewRenderer.enableLayerScrollMode(false)
        rotateModel("left")
        local sprite = app.activeSprite
        if sprite then
          previewRenderer.enableLayerScrollMode(true, sprite, st.focusIndex)
        end
        mainDlg:modify{ id="layerScrollEnable", selected=true }
        schedulePreview(true, "immediate")
      else
        rotateModel("left")
      end
    end
  }
  mainDlg:button{
    id = "rotateRight",
    text = "Right →",
    onclick = function()
      local st = previewRenderer.getLayerScrollState()
      if st.enabled then
        mainDlg:modify{ id="layerScrollEnable", selected=false }
        previewRenderer.enableLayerScrollMode(false)
        rotateModel("right")
        local sprite = app.activeSprite
        if sprite then
          previewRenderer.enableLayerScrollMode(true, sprite, st.focusIndex)
        end
        mainDlg:modify{ id="layerScrollEnable", selected=true }
        schedulePreview(true, "immediate")
      else
        rotateModel("right")
      end
    end
  }
  mainDlg:button{
    id = "rotateUp",
    text = "↑ Up",
    onclick = function()
      local st = previewRenderer.getLayerScrollState()
      if st.enabled then
        mainDlg:modify{ id="layerScrollEnable", selected=false }
        previewRenderer.enableLayerScrollMode(false)
        rotateModel("up")
        local sprite = app.activeSprite
        if sprite then
          previewRenderer.enableLayerScrollMode(true, sprite, st.focusIndex)
        end
        mainDlg:modify{ id="layerScrollEnable", selected=true }
        schedulePreview(true, "immediate")
      else
        rotateModel("up")
      end
    end
  }
  mainDlg:button{
    id = "rotateDown",
    text = "Down ↓",
    onclick = function()
      local st = previewRenderer.getLayerScrollState()
      if st.enabled then
        mainDlg:modify{ id="layerScrollEnable", selected=false }
        previewRenderer.enableLayerScrollMode(false)
        rotateModel("down")
        local sprite = app.activeSprite
        if sprite then
          previewRenderer.enableLayerScrollMode(true, sprite, st.focusIndex)
        end
        mainDlg:modify{ id="layerScrollEnable", selected=true }
        schedulePreview(true, "immediate")
      else
        rotateModel("down")
      end
    end
  }

  mainDlg:separator()
  mainDlg:label{ text = "These buttons transform the actual sprite layers," }
  mainDlg:newrow()
  mainDlg:label{ text = "rotating the entire voxel model in 90° increments." }

  --------------------------------------------------------------------------
  -- NEW: Layer Scroll Mode Section
  --------------------------------------------------------------------------
  local function updateLayerScrollStatusLabel()
    local st = previewRenderer.getLayerScrollState()
    local txt
    if not st.enabled then
      txt = "Layer Scroll: OFF"
    else
      txt = string.format("Layer Scroll: Layer %d/%d (Behind=%d, Front=%d)",
        st.focusIndex, st.total, st.behind, st.front)
    end
    mainDlg:modify{ id="layerScrollStatus", text = txt }
  end

  local function refreshPreviewForLayerScroll(resetPan)
    schedulePreview(resetPan, "immediate")
    updateLayerScrollStatusLabel()
  end

  mainDlg:separator{ text="Layer Scroll Mode" }
  mainDlg:check{
    id = "layerScrollEnable",
    text = "Enable Layer Scroll Mode",
    selected = false,
    onclick = function()
      local sprite = app.activeSprite
      if not sprite then
        mainDlg:modify{ id="layerScrollEnable", selected=false }
        return
      end
      if mainDlg.data.layerScrollEnable then
        previewRenderer.enableLayerScrollMode(true, sprite, nil)
      else
        previewRenderer.enableLayerScrollMode(false)
      end
      refreshPreviewForLayerScroll(true)
    end
  }
  mainDlg:label{
    id = "layerScrollStatus",
    text = "Layer Scroll: OFF"
  }
  mainDlg:number{
    id = "layersBehind",
    label = "Behind:",
    text = "0",
    decimals = 0,
    onchange = function()
      local st = previewRenderer.getLayerScrollState()
      if st.enabled then
        previewRenderer.setLayerScrollWindow(mainDlg.data.layersBehind, mainDlg.data.layersInFront or 0)
        refreshPreviewForLayerScroll(false)
      end
    end
  }
  mainDlg:number{
    id = "layersInFront",
    label = "In Front:",
    text = "0",
    decimals = 0,
    onchange = function()
      local st = previewRenderer.getLayerScrollState()
      if st.enabled then
        previewRenderer.setLayerScrollWindow(mainDlg.data.layersBehind or 0, mainDlg.data.layersInFront)
        refreshPreviewForLayerScroll(false)
      end
    end
  }
  mainDlg:button{
    id = "focusActiveLayer",
    text = "Focus Active Layer",
    onclick = function()
      local st = previewRenderer.getLayerScrollState()
      if not st.enabled then return end
      local sprite = app.activeSprite
      if not sprite or not app.activeLayer then return end
      local activeLayer = app.activeLayer
      local ls = {}
      for _, layer in ipairs(sprite.layers) do
        if not layer.isGroup then ls[#ls+1] = layer end
      end
      local idx = 1
      for i,l in ipairs(ls) do if l == activeLayer then idx = i break end end
      previewRenderer.enableLayerScrollMode(true, sprite, idx)
      refreshPreviewForLayerScroll(false)
    end
  }
  mainDlg:label{
    text = "Mouse wheel scroll now changes focus layer"
  }
  mainDlg:newrow()
  mainDlg:label{
    text = "(instead of scale) when enabled."
  }

  --]]
  -- NEW DEBUG TAB (replaces Server tab)
  --------------------------------------------------------------------------
  mainDlg:tab{
    id = "debugTab",
    text = "Debug"
  }
  mainDlg:separator{ text = "Debug Toggles" }
  mainDlg:check{
    id = "debugRainbow",
    text = "Rainbow Shading (debug)",
    selected = viewParams.debugRainbow or false,
    onclick = function()
      viewParams.debugRainbow = mainDlg.data.debugRainbow
      schedulePreview(false, "ui")
    end
  }

  mainDlg:check{
    id = "disableNativeAccel",
    text = "Disable Native Acceleration",
    selected = false,
    onclick = function()
      if nativeBridge_ok and nativeBridge and nativeBridge.setForceDisabled then
        nativeBridge.setForceDisabled(mainDlg.data.disableNativeAccel)
        schedulePreview(true, "immediate")
      end
    end
  }

  -- NEW: Mesh mode toggle placed next to native toggle in Debug tab
  mainDlg:check{
    id = "enableMeshMode",
    text = "Enable Mesh Mode",
    selected = viewParams.meshMode or false,
    onclick = function()
      viewParams.meshMode = mainDlg.data.enableMeshMode
      -- Trigger immediate preview so user sees mesh-mode result
      schedulePreview(true, "immediate")
    end
  }

  mainDlg:separator{ text = "Runtime Info" }
  mainDlg:label{ id = "debugThrottle", text = "Throttle: n/a" }
  mainDlg:newrow()
  mainDlg:label{ id = "debugNative", text = "Native: n/a" }
  mainDlg:newrow()
  mainDlg:label{ id = "debugBackend", text = "Last backend: n/a" }
  mainDlg:newrow()
  mainDlg:label{ id = "debugLastRender", text = "Last render: n/a" }
  mainDlg:newrow()
  mainDlg:label{ id = "debugExport", text = "Last export: n/a" }
  mainDlg:newrow()
  mainDlg:button{
    id = "refreshDebug",
    text = "Refresh Debug Info",
    onclick = function()
      local stats = viewerCore.getAdaptiveStats()
      local throttleTxt = string.format("Throttle: %d ms (p75=%s)", stats.interval or 0,
        (stats.p75 and (math.floor(stats.p75+0.5).." ms") or "n/a"))
      pcall(function() mainDlg:modify{ id="debugThrottle", text = throttleTxt } end)
      local nativeTxt = "Native: not loaded"
      if nativeBridge_ok and nativeBridge and nativeBridge.getStatus then
        local st = nativeBridge.getStatus()
        if st.loadedPath then
          nativeTxt = string.format("Native: %s (%s)%s",
            app.fs.fileName(st.loadedPath),
            st.platform or "?", st.forcedDisabled and " [FORCED OFF]" or "")
        elseif st.forcedDisabled then
          nativeTxt = "Native: forced disabled (not loaded)"
        elseif st.attempted and not st.available then
          nativeTxt = "Native: load failed"
        end
      end
      pcall(function() mainDlg:modify{ id="debugNative", text = nativeTxt } end)
      local backend = "n/a"
      local lm = viewerCore._lastMetrics
      if lm and lm.backend then backend = lm.backend end
      pcall(function() mainDlg:modify{ id="debugBackend", text = "Last backend: "..backend } end)
      if lm and lm.t_total_ms then
        pcall(function()
          mainDlg:modify{ id="debugLastRender", text = ("Last render: "..math.floor(lm.t_total_ms+0.5).." ms") }
        end)
      end
      pcall(function()
        mainDlg:modify{ id="debugExport", text = "Last export: (tracking not enabled)" }
      end)
    end
  }
  -- Auto-initialize debug info once
  pcall(function() mainDlg.data.refreshDebug:onClick() end)
  
  -- Create the FX tab
  mainDlg:tab{
    id = "fxTab",
    text = "FX"
  }

  mainDlg:separator{ text="Shading / FX" }

  -- Migration logic for legacy shading modes and parameters
  local function migrateViewParams()
    -- Migrate Simple -> Basic
    if viewParams.shadingMode == "Simple" then
      viewParams.shadingMode = "Basic"
    end
    -- Migrate Complete -> Dynamic
    if viewParams.shadingMode == "Complete" then
      viewParams.shadingMode = "Dynamic"
    end
    
    -- Migrate intensity parameter names
    if viewParams.simpleShadeIntensity then
      viewParams.basicShadeIntensity = viewParams.simpleShadeIntensity
      viewParams.simpleShadeIntensity = nil
    end
    if viewParams.simpleLightIntensity then
      viewParams.basicLightIntensity = viewParams.simpleLightIntensity
      viewParams.simpleLightIntensity = nil
    end
    
    -- Remove legacy rainbowShading parameter
    viewParams.rainbowShading = nil
    
    -- Initialize lighting table if missing
    if not viewParams.lighting then
      viewParams.lighting = {
        pitch = 25,
        yaw = 25,
        diffuse = 60,
        diameter = 100,
        ambient = 30,
        lightColor = Color(255, 255, 255),
        rimEnabled = true,
        previewRotateEnabled = false
      }
    end
    
    -- Strip deprecated fields
    if viewParams.lighting then
      viewParams.lighting.directionality = nil
      viewParams.lighting.rimStrength = nil
    end
  end
  
  -- Apply migration
  migrateViewParams()

  -- Modified shadingMode combobox with proper value handling
  mainDlg:combobox{
    id="shadingMode",
    label="Mode:",
    option=viewParams.shadingMode,
    options={"Basic","Dynamic","Stack"},
    onchange=function()
      viewParams.shadingMode = mainDlg.data.shadingMode
      
      -- Show/hide controls based on mode
      local showBasicControls = viewParams.shadingMode == "Basic"
      local showDynamicControls = viewParams.shadingMode == "Dynamic"
      local showStackControls = viewParams.shadingMode == "Stack"

      -- Basic controls
      mainDlg:modify{id="basicControlsLabel", visible=showBasicControls}
      mainDlg:modify{id="shadeIntensity", visible=showBasicControls}
      mainDlg:modify{id="lightIntensity", visible=showBasicControls}

      -- Stack controls
      mainDlg:modify{id="openFXStack", visible=showStackControls}

      -- Dynamic controls
      mainDlg:modify{id="dynamicControlsLabel", visible=showDynamicControls}
      mainDlg:modify{id="pitchSlider", visible=showDynamicControls}
      mainDlg:modify{id="yawSlider", visible=showDynamicControls}
      mainDlg:modify{id="diffuseSlider", visible=showDynamicControls}
      mainDlg:modify{id="diameterSlider", visible=showDynamicControls}
      mainDlg:modify{id="ambientSlider", visible=showDynamicControls}
      mainDlg:modify{id="lightColorPicker", visible=showDynamicControls}
      mainDlg:modify{id="rimEnabledCheck", visible=showDynamicControls}
      mainDlg:modify{id="previewRotateCheck", visible=showDynamicControls}
      mainDlg:modify{id="resetLightButton", visible=showDynamicControls}
      -- Removed: directionalitySlider, rimStrengthSlider, showLightCone, coneLength, coneSamples, coneHint

      -- Initialize values if needed for Basic mode
      if viewParams.shadingMode == "Basic" then
        -- Important: Make sure viewParams values are initialized properly
        if viewParams.basicShadeIntensity == nil then viewParams.basicShadeIntensity = 50 end
        if viewParams.basicLightIntensity == nil then viewParams.basicLightIntensity = 50 end
        
        -- Update slider values
        mainDlg:modify{id="shadeIntensity", value=viewParams.basicShadeIntensity}
        mainDlg:modify{id="lightIntensity", value=viewParams.basicLightIntensity}
      end
      
      viewerCore.requestPreview(mainDlg, viewParams, dialogueManager.controlsDialog, "ui")
    end
  }
  
  -- Basic controls
  mainDlg:separator{
    id = "basicControlsLabel",
    text = "Basic Shading Controls",
    visible = (viewParams.shadingMode == "Basic")
  }
  
  mainDlg:slider{
    id = "shadeIntensity",
    label = "Shading Intensity",
    min = 1,
    max = 100,
    value = viewParams.basicShadeIntensity or 50,
    visible = (viewParams.shadingMode == "Basic"),
    onchange = function()
      viewParams.basicShadeIntensity = mainDlg.data.shadeIntensity
      viewerCore.requestPreview(mainDlg, viewParams, dialogueManager.controlsDialog, "ui")
    end
  }
  
  mainDlg:slider{
    id = "lightIntensity",
    label = "Light Intensity",
    min = 0,
    max = 100,
    value = viewParams.basicLightIntensity or 50,
    visible = (viewParams.shadingMode == "Basic"),
    onchange = function()
      viewParams.basicLightIntensity = mainDlg.data.lightIntensity
      viewerCore.requestPreview(mainDlg, viewParams, dialogueManager.controlsDialog, "ui")
    end
  }
  
  -- Patch 3.75.2: change percent inputs to live sliders (throttled by viewerCore)
  mainDlg:slider{
    id = "diffuseSlider",
    label = "Diffuse %",
    min = 0, max = 100,
    value = viewParams.lighting.diffuse,
    visible = (viewParams.shadingMode == "Dynamic"),
    onchange = function()
      viewParams.lighting.diffuse = mainDlg.data.diffuseSlider
      viewerCore.requestPreview(mainDlg, viewParams, dialogueManager.controlsDialog, "controls")
    end
  }
  mainDlg:slider{
    id = "diameterSlider",
    label = "Diameter %",
    min = 0, max = 100,
    value = viewParams.lighting.diameter,
    visible = (viewParams.shadingMode == "Dynamic"),
    onchange = function()
      viewParams.lighting.diameter = mainDlg.data.diameterSlider
      viewerCore.requestPreview(mainDlg, viewParams, dialogueManager.controlsDialog, "controls")
    end
  }
  mainDlg:slider{
    id = "ambientSlider",
    label = "Ambient %",
    min = 0, max = 100,
    value = viewParams.lighting.ambient,
    visible = (viewParams.shadingMode == "Dynamic"),
    onchange = function()
      viewParams.lighting.ambient = mainDlg.data.ambientSlider
      viewerCore.requestPreview(mainDlg, viewParams, dialogueManager.controlsDialog, "controls")
    end
  }
  
  -- Dynamic controls
  mainDlg:separator{
    id = "dynamicControlsLabel",
    text = "Dynamic Lighting Controls",
    visible = (viewParams.shadingMode == "Dynamic")
  }
  
  mainDlg:slider{
    id = "pitchSlider",
    label = "Pitch",
    min = 0,
    max = 359,
    value = viewParams.lighting.pitch,
    visible = (viewParams.shadingMode == "Dynamic"),
    onchange = function()
      viewParams.lighting.pitch = mainDlg.data.pitchSlider
      viewParams._lastPitchYawChangeTime = os.clock()
      viewerCore.requestPreview(mainDlg, viewParams, dialogueManager.controlsDialog, "ui")
    end
  }
  
  mainDlg:slider{
    id = "yawSlider", 
    label = "Yaw",
    min = 0,
    max = 359,
    value = viewParams.lighting.yaw,
    visible = (viewParams.shadingMode == "Dynamic"),
    onchange = function()
      viewParams.lighting.yaw = mainDlg.data.yawSlider
      viewParams._lastPitchYawChangeTime = os.clock()
      viewerCore.requestPreview(mainDlg, viewParams, dialogueManager.controlsDialog, "ui")
    end
  }
  
  mainDlg:slider{
    id = "diffuseSlider",
    label = "Diffuse %",
    min = 0, max = 100,
    value = viewParams.lighting.diffuse,
    visible = (viewParams.shadingMode == "Dynamic"),
    onchange = function()
      viewParams.lighting.diffuse = mainDlg.data.diffuseSlider
      viewerCore.requestPreview(mainDlg, viewParams, dialogueManager.controlsDialog, "controls")
    end
  }
  
  mainDlg:slider{
    id = "diameterSlider",
    label = "Diameter %",
    min = 0, max = 100,
    value = viewParams.lighting.diameter,
    visible = (viewParams.shadingMode == "Dynamic"),
    onchange = function()
      viewParams.lighting.diameter = mainDlg.data.diameterSlider
      viewerCore.requestPreview(mainDlg, viewParams, dialogueManager.controlsDialog, "controls")
    end
  }
  
  mainDlg:slider{
    id = "ambientSlider",
    label = "Ambient %",
    min = 0, max = 100,
    value = viewParams.lighting.ambient,
    visible = (viewParams.shadingMode == "Dynamic"),
    onchange = function()
      viewParams.lighting.ambient = mainDlg.data.ambientSlider
      viewerCore.requestPreview(mainDlg, viewParams, dialogueManager.controlsDialog, "controls")
    end
  }
  
  mainDlg:color{
    id = "lightColorPicker",
    label = "Light Color",
    color = viewParams.lighting.lightColor,
    visible = (viewParams.shadingMode == "Dynamic"),
    onchange = function()
      viewParams.lighting.lightColor = mainDlg.data.lightColorPicker
      viewerCore.requestPreview(mainDlg, viewParams, dialogueManager.controlsDialog, "ui")
    end
  }
  
  mainDlg:check{
    id = "rimEnabledCheck",
    label = "Rim Lighting",
    selected = viewParams.lighting.rimEnabled,
    visible = (viewParams.shadingMode == "Dynamic"),
    onclick = function()
      viewParams.lighting.rimEnabled = mainDlg.data.rimEnabledCheck
      viewerCore.requestPreview(mainDlg, viewParams, dialogueManager.controlsDialog, "ui")
    end
  }
  
  mainDlg:check{
    id = "previewRotateCheck",
    label = "Preview Lighting Rotation",
    selected = viewParams.lighting.previewRotateEnabled,
    visible = (viewParams.shadingMode == "Dynamic"),
    onclick = function()
      viewParams.lighting.previewRotateEnabled = mainDlg.data.previewRotateCheck
    end
  }

  mainDlg:button{
    id="openFXStack",
    text="Open FX Stack…",
    visible = (viewParams.shadingMode == "Stack"),
    onclick=function()
      if fxStackDialog then
        -- migrate if needed before open
        if fxStack then fxStack.migrateIfNeeded(viewParams) end
        fxStackDialog.open(viewParams)
      else
        app.alert("FX Stack dialog module not available (fxStackDialog.lua missing).")
      end
    end
  }

  -- Debug: Show Light Cone (Patch 3.5)
  mainDlg:check{
    id = "showLightCone",
    label = "Show Light Cone (debug)",
    selected = viewParams.debugCone and viewParams.debugCone.enabled or false,
    visible = (viewParams.shadingMode == "Dynamic"),
    onclick = function()
      viewParams.debugCone.enabled = mainDlg.data.showLightCone
      -- Repaint preview only (no model re-render required)
      if previewDlg then pcall(function() previewDlg:repaint() end) end
    end
  }
  mainDlg:newrow()
  mainDlg:number{
    id = "coneLength",
    label = "Cone Length (multiplier)",
    text = tostring(viewParams.debugCone and viewParams.debugCone.length or 1.5),
    decimals = 2,
    visible = (viewParams.shadingMode == "Dynamic"),
    onchange = function()
      local v = tonumber(mainDlg.data.coneLength) or viewParams.debugCone.length
      viewParams.debugCone.length = math.max(0.1, v)
      if previewDlg then pcall(function() previewDlg:repaint() end) end
    end
  }
  mainDlg:slider{
    id = "coneSamples",
    label = "Cone Samples",
    min = 8,
    max = 64,
    value = viewParams.debugCone and viewParams.debugCone.samples or 24,
    visible = (viewParams.shadingMode == "Dynamic"),
    onchange = function()
      viewParams.debugCone.samples = math.max(8, math.min(64, math.floor(mainDlg.data.coneSamples)))
      if previewDlg then pcall(function() previewDlg:repaint() end) end
    end
  }
  mainDlg:label{
    id = "coneHint",
    text = "Debug cone: visualizes light position, directionality & diameter.",
    visible = (viewParams.shadingMode == "Dynamic")
  }

  mainDlg:button{
    id = "resetLightButton",
    text = "Reset Light",
    visible = (viewParams.shadingMode == "Dynamic"),
    onclick = function()
      viewParams.lighting = {
        pitch = 0,
        yaw = 90,
        diffuse = 60,
        diameter = 100,
        ambient = 30,
        lightColor = Color(255, 255, 255),
        rimEnabled = false,
        previewRotateEnabled = false
      }
      viewParams._lastPitchYawChangeTime = os.clock()
      mainDlg:modify{id="pitchSlider", value=0}
      mainDlg:modify{id="yawSlider", value=90}
      mainDlg:modify{id="diffuseSlider", value=60}
      mainDlg:modify{id="diameterSlider", value=100}
      mainDlg:modify{id="ambientSlider", value=30}
      mainDlg:modify{id="lightColorPicker", color=Color(255, 255, 255)}
      mainDlg:modify{id="rimEnabledCheck", selected=false}
      mainDlg:modify{id="previewRotateCheck", selected=false}
      viewerCore.requestPreview(mainDlg, viewParams, dialogueManager.controlsDialog, "ui")
    end
  }
  
  -- End tab group (removed tab-change alerts)
  mainDlg:endtabs{
    id = "mainTabs",
    selected = "infoTab"
  }
  
  -- Shared button at the bottom for all tabs
  mainDlg:separator()
  mainDlg:button{
    id = "closeButton",
    text = "Close All",
    onclick = function()
      -- Close child dialogs properly when main dialog is closed
      if dialogueManager.controlsDialog then
        pcall(function()
          dialogueManager.controlsDialog:close()
          dialogueManager.controlsDialog = nil
        end)
      end
      
      if dialogueManager.previewDialog then
        pcall(function()
          dialogueManager.previewDialog:close()
          dialogueManager.previewDialog = nil
        end)
      end
      
      -- Clear the main dialog reference
      dialogueManager.mainDialog = nil
      mainDlg:close()
    end
  }
  
  -- Create the preview dialog
  previewDlg:canvas{
    id = "previewCanvas",
    width = previewCanvasWidth,
    height = previewCanvasHeight,
    onpaint = function(ev)
      local ctx = ev.context
      local currentWidth = ctx.width
      local currentHeight = ctx.height
      
      -- Update canvas size variables when window is resized
      previewCanvasWidth = currentWidth
      previewCanvasHeight = currentHeight
      
      -- First, clear the entire canvas with the background color
      ctx:beginPath()
      ctx:rect(Rectangle(0, 0, currentWidth, currentHeight))
      ctx.color = viewParams.backgroundColor or Color(240, 240, 240)
      ctx:fill()
      
      -- Then, if we have a model preview image, draw it on top
      if previewImage then
        -- Calculate center position and apply pan offset
        local baseOffsetX = math.floor((currentWidth - previewImage.width) / 2)
        local baseOffsetY = math.floor((currentHeight - previewImage.height) / 2)
        
        -- Apply pan offset only to the model, not to the background
        local finalOffsetX = baseOffsetX + previewOffsetX
        local finalOffsetY = baseOffsetY + previewOffsetY
        
        -- Draw the preview image with adjusted position
        ctx:drawImage(previewImage, finalOffsetX, finalOffsetY)
        -- Optionally render debug light cone overlay (pure-pixel, not part of voxel model)
        local showCone = false
        if viewParams and viewParams.shadingMode == "Dynamic" and viewParams.lighting then
          local recent = false
          if viewParams._lastPitchYawChangeTime then
            recent = (os.clock() - viewParams._lastPitchYawChangeTime) < 0.6
          end
          showCone = (viewParams.lighting.previewRotateEnabled or recent)
        end
        if showCone and modelDimensions and voxelModel then
          -- Build overlay image same size as previewImage
          local ok, overlay = pcall(function() return Image(previewImage.width, previewImage.height, previewImage.colorMode) end)
          if ok and overlay then
            overlay:clear(Color(0,0,0,0))
            pcall(function() drawLightConeOverlay(overlay) end)
            ctx:drawImage(overlay, finalOffsetX, finalOffsetY)
          end
        end
      else
        -- Draw placeholder text if no model is available
        ctx.color = Color(100, 100, 100)
        local text = "Preview will appear here"
        local textWidth = ctx:measureText(text).width
        ctx:fillText(text, (currentWidth - textWidth) / 2, currentHeight / 2)
      end
    end,
    onmousedown = function(ev)
      if ev.button == MouseButton.LEFT then
        isDragging = true
        lastX = ev.x
        lastY = ev.y
      elseif ev.button == MouseButton.MIDDLE then
        isRotating = true
        lastX = ev.x
        lastY = ev.y
      end
    end,
    onmousemove = function(ev)
      if isDragging and ev.button == MouseButton.LEFT then
        -- Pan the preview image (not the background)
        if lastX and lastY then
          local deltaX = ev.x - lastX
          local deltaY = ev.y - lastY
          
          previewOffsetX = previewOffsetX + deltaX
          previewOffsetY = previewOffsetY + deltaY
          
          lastX = ev.x
          lastY = ev.y
          
          previewDlg:repaint()
        end
      elseif isRotating and ev.button == MouseButton.MIDDLE then
        -- Calculate delta from last position
        if lastX ~= nil and lastY ~= nil then
          local deltaX = ev.x - lastX
          local deltaY = ev.y - lastY
          
          -- Skip if movement is too small
          if math.abs(deltaX) < 0.1 and math.abs(deltaY) < 0.1 then
            lastX = ev.x
            lastY = ev.y
            return
          end
          
          -- Check if we should rotate light instead of model
          if viewParams.shadingMode == "Dynamic" and viewParams.lighting.previewRotateEnabled then
            -- Patch 3.75.1: clamp per-event deltas, accumulate, and apply only when threshold reached.
            local function clamp(v, m) if v > m then return m elseif v < -m then return -m else return v end end
            local cdx = clamp(deltaX, maxMouseDelta)
            local cdy = clamp(deltaY, maxMouseDelta)
            -- Patch 3.75.2: invert light preview rotation mapping (user request)
            -- yaw responds opposite to X movement; pitch responds opposite to Y movement
            accumLightYaw = accumLightYaw + (-cdx * 0.5)
            accumLightPitch = accumLightPitch + (cdy * 0.5)
        
            if math.abs(accumLightYaw) >= applyThreshold or math.abs(accumLightPitch) >= applyThreshold then
              viewParams.lighting.yaw = (viewParams.lighting.yaw + accumLightYaw) % 360
              viewParams.lighting.pitch = (viewParams.lighting.pitch + accumLightPitch) % 360
              viewParams._lastPitchYawChangeTime = os.clock()
              -- reset accumulators after applying
              accumLightYaw = 0.0
              accumLightPitch = 0.0
              schedulePreview(false, "mouseMove")
            end
        
            -- Always update last position so deltas are relative to latest mouse
            lastX = ev.x
            lastY = ev.y
          else
            -- Patch 3.75.1: accumulate model rotation deltas and apply only when threshold reached.
            local function clamp(v, m) if v > m then return m elseif v < -m then return -m else return v end end
            local cdx = clamp(deltaX, maxMouseDelta)
            local cdy = clamp(deltaY, maxMouseDelta)
            -- same scale factor as original
            accumModelYaw = accumModelYaw + (cdx * mouseSensitivity * 0.5)
            accumModelPitch = accumModelPitch + ((-cdy) * mouseSensitivity * 0.5)
        
            if math.abs(accumModelYaw) >= applyThreshold or math.abs(accumModelPitch) >= applyThreshold then
              -- Apply accumulated camera-relative rotation
              local newMatrix = rotation.applyRelativeRotation(
                dialogueManager.currentRotationMatrix,
                accumModelPitch, -- pitch
                accumModelYaw,   -- yaw
                0                -- roll
              )
        
              -- Extract Euler angles and update state
              local euler = mathUtils.matrixToEuler(newMatrix)
              viewParams.eulerX = euler.x
              viewParams.eulerY = euler.y
              viewParams.eulerZ = euler.z
              viewParams.xRotation = viewParams.eulerX
              viewParams.yRotation = viewParams.eulerY
              viewParams.zRotation = viewParams.eulerZ
              dialogueManager.currentRotationMatrix = newMatrix
        
              -- Update rotation display and controls
              pcall(function()
                mainDlg:modify{
                  id = "rotationInfo",
                  text = string.format("Euler Space: X=%.0f° Y=%.0f° Z=%.0f°", 
                         viewParams.eulerX, viewParams.eulerY, viewParams.eulerZ)
                }
              end)
              if dialogueManager.controlsDialog then
                pcall(function()
                  dialogueManager.isUpdatingControls = true
                  dialogueManager.controlsDialog:modify{id="absoluteX", value=math.floor(viewParams.xRotation)}
                  dialogueManager.controlsDialog:modify{id="absoluteY", value=math.floor(viewParams.yRotation)}
                  dialogueManager.controlsDialog:modify{id="absoluteZ", value=math.floor(viewParams.zRotation)}
                  dialogueManager.isUpdatingControls = false
                end)
              end
        
              -- reset accumulators after applying
              accumModelYaw = 0.0
              accumModelPitch = 0.0
        
              -- Request preview update (viewerCore will coalesce)
              schedulePreview(false, "mouseMove")
            end
        
            -- Update last position always
            lastX = ev.x
            lastY = ev.y
          end
        end
        
        lastX = ev.x
        lastY = ev.y
      end
    end,
    onmouseup = function(ev)
      isDragging = false
      isRotating = false
      lastX = nil
      lastY = nil
      -- Clear accumulators to avoid stale deltas after mouse release
      accumLightYaw = 0.0
      accumLightPitch = 0.0
      accumModelYaw = 0.0
      accumModelPitch = 0.0
      viewerCore.flush()
    end,
    onwheel = function(ev)
      local st = previewRenderer.getLayerScrollState()
      if st.enabled then
        local sprite = app.activeSprite
        if ev.deltaY > 0 then
          previewRenderer.shiftLayerFocus(1, sprite)
        else
          previewRenderer.shiftLayerFocus(-1, sprite)
        end
        schedulePreview(true, "immediate")
        updateLayerScrollStatusLabel()
        return
      end
      -- Original scale handling
      local scaleStep = 0.25
      if ev.deltaY > 0 then
        viewParams.scaleLevel = math.max(0.5, viewParams.scaleLevel - scaleStep)
      else
        viewParams.scaleLevel = math.min(5.0, viewParams.scaleLevel + scaleStep)
      end
      if dialogueManager.controlsDialog then
        dialogueManager.controlsDialog:modify{
          id = "scaleSlider",
          value = viewParams.scaleLevel * 2
        }
        dialogueManager.controlsDialog:modify{
          id = "scaleLabel",
          text = "Scale: " .. string.format("%.0f%%", viewParams.scaleLevel * 100)
        }
      end
      previewOffsetX, previewOffsetY = 0, 0
      schedulePreview(true, "immediate")
    end,
    onresize = function() previewDlg:repaint() end
  }

  -- Add a close button to the preview window
  previewDlg:button{
    id = "closePreviewButton",
    text = "Close Preview",
    onclick = function()
      dialogueManager.previewDialog = nil
      previewDlg:close()
    end
  }
  
  -- Initial preview update
  schedulePreview(true, "immediate")
  
  -- Show both dialogs (don't wait)
  mainDlg:show{ wait = false }
  previewDlg:
show{ wait = false }

  -- Get Aseprite window dimensions
  local windowWidth = app.window.width

  local windowHeight = app.window.height

  -- Wait briefly for dialogs to render their content
  app.command.Refresh()

  -- Get current bounds
  local mainBounds = mainDlg.bounds
  local previewBounds = previewDlg.bounds

  -- Calculate new positions to stack them vertically and center horizontally
  local totalHeight = mainBounds.height + previewBounds.height + 10 -- 10px gap
  local startY = math.max(10, (windowHeight - totalHeight) / 2)

  -- Position preview dialog on top
  local centerX = (windowWidth - previewBounds.width) / 2
  previewDlg.bounds = Rectangle(centerX, startY, previewBounds.width, previewBounds.height)

  -- Position main dialog below preview
  mainDlg.bounds = Rectangle(
    (windowWidth - mainBounds.width) / 2, 
    startY + previewBounds.height + 10, 
    mainBounds.width, 
    mainBounds.height
  )
  
  -- Set flag to indicate positioning has been done
  initialPositioningDone = true
end

-- EXPORT both: new simplified (openModelViewer) and legacy (openModelViewerFull)
return {
  openModelViewer = openModelViewer
}