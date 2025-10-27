-- viewer_state.lua
-- Shared view parameters and state management for model viewer

local viewerState = {}

-- Lazy loaders
local function getFxStack()
  return AseVoxel.fxStack
end

-- Default view parameters
function viewerState.createDefaultParams()
  local fxStack = getFxStack()
  
  return {
    xRotation = 315,
    yRotation = 324,
    zRotation = 29,
    -- Canonical Euler angles as master rotation source
    eulerX = 315,
    eulerY = 324,
    eulerZ = 29,
    depthPerspective = 50, -- legacy
    fovDegrees = 5 + (75-5)*(50/100), -- FOV from perspective
    orthogonalView = false,
    backgroundColor = Color(128, 128, 128), -- Will be calculated based on model
    scaleLevel = 3, -- Default 300%
    relativeX = 0,
    relativeY = 0,
    relativeZ = 0,
    
    -- Outline parameters
    enableOutline = false,
    outlineColor = Color(0, 0, 0),
    outlinePattern = "circle",
    
    -- FX Stack
    fxStack = fxStack and fxStack.makeDefaultStack() or { modules = {} },
    
    -- Shading
    shadingMode = "Basic", -- DEFAULT: Basic
    basicShadeIntensity = 50,
    basicLightIntensity = 50,
    
    -- Dynamic lighting parameters
    lighting = {
      pitch = 0,
      yaw = 90,
      diffuse = 60,
      diameter = 100,
      ambient = 30,
      lightColor = Color(255, 255, 255),
      rimEnabled = false,
      previewRotateEnabled = false
    },
    
    -- Perspective scale reference
    perspectiveScaleRef = "middle",
    
    -- Mesh mode
    meshMode = false,
    
    -- Rendering mode
    renderMode = "OffscreenImage",  -- "OffscreenImage" (default) or "DirectCanvas"
    enableAntialiasing = true       -- Antialiasing for DirectCanvas mode
  }
end

-- Calculate background size based on model dimensions
function viewerState.calculateBackgroundSize(modelDimensions)
  if not modelDimensions then
    return 200, 200 -- Default size
  end
  
  local sizeX = modelDimensions.sizeX or 1
  local sizeY = modelDimensions.sizeY or 1
  local sizeZ = modelDimensions.sizeZ or 1
  
  local diagonal = math.sqrt(
    sizeX * sizeX +
    sizeY * sizeY +
    sizeZ * sizeZ
  )
  
  -- Calculate size without enforcing a minimum
  local size = math.floor(5 * diagonal * 1.5 + 0.5)
  
  return size, size  -- Square background
end

-- Apply render result to update model, image, and dimensions
function viewerState.applyRenderResult(result, mainDlg, previewDlg, state)
  if not result then return end
  
  state.voxelModel = result.model
  state.previewImage = result.image
  state.modelDimensions = result.dimensions
  
  -- Update FOV info
  local fovText = "Ortho"
  if state.viewParams and not state.viewParams.orthogonalView and state.viewParams.fovDegrees then
    fovText = string.format("FOV: %.0f°", state.viewParams.fovDegrees)
  end
  
  pcall(function()
    if mainDlg then
      mainDlg:modify{ id = "fovInfo", text = fovText }
    end
  end)
  
  -- Get performance metrics
  local viewerCore = AseVoxel.viewerCore
  local lastPerf = result.metrics or (viewerCore and viewerCore._lastMetrics)
  local adaptive = viewerCore and viewerCore.getAdaptiveStats() or {interval=0}
  
  -- Recalculate background size
  local bgWidth, bgHeight = viewerState.calculateBackgroundSize(state.modelDimensions)
  if state.previewCanvasWidth ~= bgWidth or state.previewCanvasHeight ~= bgHeight then
    state.previewCanvasWidth = bgWidth
    state.previewCanvasHeight = bgHeight
    
    pcall(function()
      previewDlg:modify{
        id="previewCanvas",
        width=state.previewCanvasWidth,
        height=state.previewCanvasHeight
      }
    end)
    
    if state.resetPan then
      state.previewOffsetX = 0
      state.previewOffsetY = 0
    end
  end
  
  pcall(function()
    previewDlg:repaint()
  end)
  
  -- Live-update main dialog model info labels
  pcall(function()
    if mainDlg then
      local count = state.voxelModel and #state.voxelModel or 0
      mainDlg:modify{
        id = "modelInfo_count",
        text = "Voxel count: " .. tostring(count)
      }
      
      local dims = state.modelDimensions or { sizeX = 0, sizeY = 0, sizeZ = 0 }
      mainDlg:modify{
        id = "modelInfo_dims",
        text = string.format("Model size: %d×%d×%d voxels", dims.sizeX, dims.sizeY, dims.sizeZ)
      }
      
      mainDlg:modify{
        id = "modelInfo_scale",
        text = string.format("Scale: %.0f%%", (state.viewParams.scaleLevel or 1) * 100)
      }
      
      -- Update performance labels
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

return viewerState
