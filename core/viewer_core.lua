-- viewerCore.lua
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

local viewerCore = {}

viewerCore._sched = {
  renderingInProgress = false,
  pendingParams = nil,
  pendingDlg = nil,
  pendingControls = nil,
  pendingIsMouse = false,
  pendingIsControls = false,          -- NEW
  pendingCallback = nil,
  lastMouseSampleTime = 0,
  lastControlSampleTime = 0,          -- NEW
  sampleIntervalMs = 100,             -- adaptive interval (ms)

  -- Adaptive timing
  renderTimes = {},        -- recent render durations (ms)
  maxSamples = 50,
  dynamicEnabled = true,
  dynamicMinMs = 40,       -- lower clamp
  dynamicMaxMs = 440,      -- upper clamp
  dynamicMultiplier = 3    -- Patch 3.75.2: raise multiplier (Option 2A)
}

-- Last render metrics snapshot
viewerCore._lastMetrics = nil

-- Helper: insert render duration & update adaptive interval
local function _recordRenderTime(ms)
  local s = viewerCore._sched
  if not s.dynamicEnabled or ms <= 0 then return end
  local rt = s.renderTimes
  rt[#rt+1] = ms
  if #rt > s.maxSamples then
    table.remove(rt, 1)
  end
  -- Patch 3.75.2: use 75th percentile instead of median (Option 2B)
  local tmp = {}
  for i,v in ipairs(rt) do tmp[i] = v end
  table.sort(tmp)
  local n = #tmp
  local qIndexFloat = 0.75 * (n - 1) + 1     -- linear index (1-based)
  local qLow = math.floor(qIndexFloat)
  local qHigh = math.min(n, qLow + 1)
  local frac = qIndexFloat - qLow
  local qVal
  if n == 0 then
    qVal = ms
  elseif qLow == qHigh then
    qVal = tmp[qLow]
  else
    qVal = tmp[qLow] + (tmp[qHigh] - tmp[qLow]) * frac
  end
  local desired = qVal * s.dynamicMultiplier
  if desired < s.dynamicMinMs then desired = s.dynamicMinMs end
  if desired > s.dynamicMaxMs then desired = s.dynamicMaxMs end
  s.sampleIntervalMs = math.floor(desired + 0.5)
end

function viewerCore.setAdaptiveThrottle(opts)
  local s = viewerCore._sched
  if opts.enabled ~= nil then s.dynamicEnabled = opts.enabled end
  if opts.minMs then s.dynamicMinMs = opts.minMs end
  if opts.maxMs then s.dynamicMaxMs = opts.maxMs end
  if opts.multiplier then s.dynamicMultiplier = opts.multiplier end
end

function viewerCore.getAdaptiveStats()
  local s = viewerCore._sched
  local count = #s.renderTimes
  if count == 0 then return {count=0, median=nil, p75=nil, interval=s.sampleIntervalMs} end
  local tmp = {}
  for i,v in ipairs(s.renderTimes) do tmp[i]=v end
  table.sort(tmp)
  local n = #tmp
  local median = (n % 2 == 1) and tmp[(n+1)/2] or (tmp[n/2] + tmp[n/2+1]) / 2
  local qIndexFloat = 0.75 * (n - 1) + 1
  local qLow = math.floor(qIndexFloat)
  local qHigh = math.min(n, qLow + 1)
  local frac = qIndexFloat - qLow
  local qVal
  if qLow == qHigh then qVal = tmp[qLow]
  else qVal = tmp[qLow] + (tmp[qHigh] - tmp[qLow]) * frac end
  return {count=count, median=median, p75=qVal, interval=s.sampleIntervalMs}
end

local function nowMs() return os.clock() * 1000 end

local function _onRenderComplete()
  local s = viewerCore._sched
  s.renderingInProgress = false
  local p = s.pendingParams
  if not p then return end
  if s.pendingIsMouse then
    local elapsed = nowMs() - s.lastMouseSampleTime
    if elapsed < s.sampleIntervalMs then return end
    s.lastMouseSampleTime = nowMs()
  elseif s.pendingIsControls then
    local elapsed = nowMs() - s.lastControlSampleTime
    if elapsed < s.sampleIntervalMs then return end
    s.lastControlSampleTime = nowMs()
  end
  local dlg = s.pendingDlg
  local controls = s.pendingControls
  local cb = s.pendingCallback
  s.pendingParams = nil
  s.pendingDlg = nil
  s.pendingControls = nil
  s.pendingIsMouse = false
  s.pendingIsControls = false
  s.pendingCallback = nil
  s.renderingInProgress = true
  viewerCore.updatePreview(dlg, p, controls, cb)
end

function viewerCore.requestPreview(dlg, params, controlsDialog, source, callback)
  local s = viewerCore._sched
  -- Treat mouseMove and (future) interactive drags uniformly; add controls sampling
  local isMouse = (source == "mouseMove")
  local isControls = (source == "controls")
  local t = nowMs()

  if isMouse and (t - s.lastMouseSampleTime) < s.sampleIntervalMs then
    s.pendingParams = params
    s.pendingDlg = dlg
    s.pendingControls = controlsDialog
    s.pendingIsMouse = true
    s.pendingIsControls = false
    s.pendingCallback = callback
    return
  end
  if isControls and (t - s.lastControlSampleTime) < s.sampleIntervalMs then
    s.pendingParams = params
    s.pendingDlg = dlg
    s.pendingControls = controlsDialog
    s.pendingIsMouse = false
    s.pendingIsControls = true
    s.pendingCallback = callback
    return
  end

  if s.renderingInProgress then
    s.pendingParams = params
    s.pendingDlg = dlg
    s.pendingControls = controlsDialog
    s.pendingIsMouse = isMouse
    s.pendingIsControls = isControls
    s.pendingCallback = callback
    return
  end

  if isMouse then
    s.lastMouseSampleTime = t
  elseif isControls then
    s.lastControlSampleTime = t
  end
  s.renderingInProgress = true
  viewerCore.updatePreview(dlg, params, controlsDialog, callback)
end

function viewerCore.flush()
  local s = viewerCore._sched
  if s.renderingInProgress then return end
  _onRenderComplete()
end

function viewerCore.updatePreview(dlg, params, controlsDialog, callback)
  local startTime = nowMs()
  local function finish(result, counted)
    if counted then
      _recordRenderTime(nowMs() - startTime)
    end
    if callback then pcall(function() callback(result) end) end
    _onRenderComplete()
    return result
  end

  -- Lazy dialogueManager (may be nil if not yet fully loaded)
  local dialogueManager = package.loaded["dialogueManager"]

  if dialogueManager and dialogueManager.updateLock then
    return finish(nil, false)
  end
  local sprite = app.activeSprite
  if not sprite then
    return finish(nil, false)
  end
  local ok, resultOrErr = pcall(function()
    local previewRenderer = getPreviewRenderer()
    local voxelModel = previewRenderer.generateVoxelModel(sprite)
    if #voxelModel == 0 then return nil end
    local middlePoint = previewRenderer.calculateMiddlePoint(voxelModel)

    local renderParams = {
      x = params.xRotation,
      y = params.yRotation,
      z = params.zRotation,
      -- Keep depthPerspective for backward compatibility if passed, but prefer explicit fovDegrees
      fovDegrees = params.fovDegrees or params.fov or (params.depthPerspective and (5 + (75-5)*(params.depthPerspective/100))) or 45,
      orthogonal = params.orthogonalView, -- no automatic orthographic when FOV small
      perspectiveScaleRef = params.perspectiveScaleRef or "middle",
      enableOutline = params.enableOutline,
      outlineColor = params.outlineColor,
      outlinePattern = params.outlinePattern,
      scaleLevel = params.scaleLevel,
      rotationMatrix = params.rotationMatrix 
        or (dialogueManager and dialogueManager.currentRotationMatrix),
      fxStack = params.fxStack,
      -- NEW: Forward shader stack configuration to renderer
      shaderStack = params.shaderStack,
      -- Forward mesh-mode toggle so previewRenderer / native can choose mesh pipeline
      mesh = params.mesh or params.meshMode,
      meshMode = params.meshMode or params.mesh,
      shadingMode = params.shadingMode or "Stack",
      lighting = params.lighting and {
        pitch = params.lighting.pitch or 25,
        yaw = params.lighting.yaw or 25,
        diffuse = params.lighting.diffuse or 60,
        diameter = params.lighting.diameter or 100,
        ambient = params.lighting.ambient or 30,
        lightColor = params.lighting.lightColor or Color(255,255,255),
        rimEnabled = (params.lighting.rimEnabled ~= false),
        previewRotateEnabled = params.lighting.previewRotateEnabled or false
      } or nil,
      basicShadeIntensity = params.basicShadeIntensity,
      basicLightIntensity = params.basicLightIntensity,
      metrics = {
        startTime = startTime,
        params = params,
        controlsDialog = controlsDialog
      }
     }

    local previewImage = previewRenderer.renderVoxelModel(voxelModel, renderParams)
    pcall(function() dlg:repaint() end)

    -- Optional control dialog UI sync
    if controlsDialog and dialogueManager 
       and (not dialogueManager.isUpdatingControls and not dialogueManager.updateLock) then
      pcall(function()
        dialogueManager.isUpdatingControls = true
        controlsDialog:modify{
          id="scaleLabel",
          text="Scale: " .. string.format("%.0f%%", params.scaleLevel * 100)
        }
        dialogueManager.isUpdatingControls = false
      end)
    end

    -- NEW: snapshot metrics after render
    -- The renderer populates/updates renderParams.metrics. Use that same table as the canonical snapshot.
    local metrics = renderParams.metrics or {}
    -- Ensure a total render time is available (fallback to wall time)
    metrics.renderTime = metrics.renderTime or (nowMs() - startTime)
    metrics.t_total_ms = metrics.t_total_ms or metrics.renderTime
    viewerCore._lastMetrics = metrics

    return {
      image = previewImage,
      model = voxelModel,
      dimensions = middlePoint,
      -- NEW: include metrics in return
      metrics = metrics
    }
  end)
  if not ok then
    print("viewerCore.updatePreview error: " .. tostring(resultOrErr))
    return finish(nil, false)
  end
  return finish(resultOrErr, true)
end

function viewerCore.calculateContrastColor(voxelModel)
  if not voxelModel or #voxelModel == 0 then
    return Color(128,128,128)
  end
  local totalR,totalG,totalB,count = 0,0,0,0
  for _,v in ipairs(voxelModel) do
    local c = v.color
    if c then
      totalR = totalR + (c.r or 0)
      totalG = totalG + (c.g or 0)
      totalB = totalB + (c.b or 0)
      count = count + 1
    end
  end
  if count == 0 then return Color(128,128,128) end
  local avgR,avgG,avgB = totalR/count,totalG/count,totalB/count
  local brightness = (avgR*0.299 + avgG*0.587 + avgB*0.114)/255
  return brightness > 0.5 and Color(48,48,48) or Color(200,200,200)
end

-- Tuned adaptive throttle for more responsive interactive slider drags
viewerCore.setAdaptiveThrottle{
  -- Use consistent multiplier regardless of native module availability
  -- DirectCanvas doesn't benefit from native anyway, so no need to vary this
  multiplier = 2.5,
  minMs = 30,
  maxMs = 5000
}

return viewerCore
