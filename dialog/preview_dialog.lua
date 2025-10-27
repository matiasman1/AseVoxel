-- preview_dialog.lua
-- Preview canvas dialog with mouse interaction (pan/rotate/zoom)
-- Dependencies: Loaded via AseVoxel namespace

local previewDialog = {}

-- Access dependencies through global namespace
local function getDialogManager()
  return AseVoxel.dialog.dialog_manager
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

local function getViewerCore()
  return AseVoxel.viewerCore
end

-- Create preview dialog with canvas and mouse interaction
function previewDialog.create(viewParams, previewCanvasWidth, previewCanvasHeight, schedulePreview, updateLayerScrollStatusLabel, drawLightConeOverlay, previewState)
  local previewDlg = Dialog("AseVoxel - Preview")
  local dialogueManager = getDialogManager()
  local previewRenderer = getPreviewRenderer()
  local mathUtils = getMathUtils()
  local rotation = getRotation()
  local viewerCore = getViewerCore()
  
  -- Mouse interaction variables
  local isDragging = false
  local isRotating = false
  local lastX = 0
  local lastY = 0
  local mouseSensitivity = 1.0
  local previewOffsetX = 0
  local previewOffsetY = 0
  
  -- Patch 3.75.1: accumulators & clamping to reduce mouse event spam
  local accumLightYaw = 0.0
  local accumLightPitch = 0.0
  local accumModelYaw = 0.0
  local accumModelPitch = 0.0
  local maxMouseDelta = 5      -- clamp per-event mouse delta (pixels)
  local applyThreshold = 0.5   -- degrees: apply accumulated rotation when exceeded
  
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
      previewState.canvasWidth = currentWidth
      previewState.canvasHeight = currentHeight
      
      -- First, clear the entire canvas with the background color
      ctx:beginPath()
      ctx:rect(Rectangle(0, 0, currentWidth, currentHeight))
      ctx.color = viewParams.backgroundColor or Color(240, 240, 240)
      ctx:fill()
      
      -- Check rendering mode
      local useDirectCanvas = (viewParams.renderMode == "DirectCanvas")
      
      if useDirectCanvas and previewState.voxelModel then
        -- NEW: Direct canvas rendering using EXISTING renderer pipeline!
        -- Just passes GraphicsContext instead of Image - all culling/sorting reused
        local startTime = os.clock() * 1000  -- Record start time for adaptive throttling
        local success, err = pcall(function()
          local renderParams = {
            width = currentWidth,
            height = currentHeight,
            xRotation = viewParams.xRotation or viewParams.eulerX,
            yRotation = viewParams.yRotation or viewParams.eulerY,
            zRotation = viewParams.zRotation or viewParams.eulerZ,
            scale = viewParams.scaleLevel or 1.0,
            orthogonal = viewParams.orthogonalView,
            fovDegrees = viewParams.fovDegrees,
            offsetX = previewOffsetX,
            offsetY = previewOffsetY,
            enableAntialiasing = viewParams.enableAntialiasing,
            shadingMode = viewParams.shadingMode,
            fxStack = viewParams.fxStack,
            lighting = viewParams.lighting,
            enableOutline = viewParams.enableOutline,
            outlineColor = viewParams.outlineColor,
            outlineWidth = 1,
            basicShadeIntensity = viewParams.basicShadeIntensity,
            basicLightIntensity = viewParams.basicLightIntensity,
            enableProfiling = viewParams.enableProfiling,  -- NEW: Enable profiling if requested
          }
          
          local previewRenderer = AseVoxel.render.preview_renderer
          if previewRenderer and previewRenderer.renderVoxelModelDirect then
            local result = previewRenderer.renderVoxelModelDirect(ctx, previewState.voxelModel, renderParams)
            if not result.success and result.error then
              print("[AseVoxel] Direct canvas render error: " .. result.error)
            end
          end
        end)
        
        -- Record render time for adaptive throttling (same as OffscreenImage mode)
        local renderTime = (os.clock() * 1000) - startTime
        if viewerCore and viewerCore._sched then
          local s = viewerCore._sched
          if s.dynamicEnabled and renderTime > 0 then
            local rt = s.renderTimes
            rt[#rt+1] = renderTime
            if #rt > s.maxSamples then
              table.remove(rt, 1)
            end
            -- Update adaptive interval using 75th percentile
            local tmp = {}
            for i,v in ipairs(rt) do tmp[i] = v end
            table.sort(tmp)
            local n = #tmp
            if n > 0 then
              local qIndexFloat = 0.75 * (n - 1) + 1
              local qLow = math.floor(qIndexFloat)
              local qHigh = math.min(n, qLow + 1)
              local frac = qIndexFloat - qLow
              local qVal
              if qLow == qHigh then
                qVal = tmp[qLow]
              else
                qVal = tmp[qLow] + (tmp[qHigh] - tmp[qLow]) * frac
              end
              local desired = qVal * s.dynamicMultiplier
              if desired < s.dynamicMinMs then desired = s.dynamicMinMs end
              if desired > s.dynamicMaxMs then desired = s.dynamicMaxMs end
              s.sampleIntervalMs = math.floor(desired + 0.5)
            end
          end
        end
        
        if not success then
          print("[AseVoxel] DirectCanvas pcall failed: " .. tostring(err))
          -- Draw error message on canvas
          ctx.color = Color(255, 0, 0)
          ctx:fillText("DirectCanvas Error: " .. tostring(err), 10, 10)
        end
      elseif previewState.image then
        -- Original: Offscreen Image rendering (blit to canvas)
        -- Calculate center position and apply pan offset
        local baseOffsetX = math.floor((currentWidth - previewState.image.width) / 2)
        local baseOffsetY = math.floor((currentHeight - previewState.image.height) / 2)
        
        -- Apply pan offset only to the model, not to the background
        local finalOffsetX = baseOffsetX + previewOffsetX
        local finalOffsetY = baseOffsetY + previewOffsetY
        
        -- Draw the preview image with adjusted position
        ctx:drawImage(previewState.image, finalOffsetX, finalOffsetY)
        
        -- Optionally render debug light cone overlay (pure-pixel, not part of voxel model)
        local showCone = false
        if viewParams and viewParams.shadingMode == "Dynamic" and viewParams.lighting then
          local recent = false
          if viewParams._lastPitchYawChangeTime then
            recent = (os.clock() - viewParams._lastPitchYawChangeTime) < 0.6
          end
          showCone = (viewParams.lighting.previewRotateEnabled or recent)
        end
        if showCone and previewState.modelDimensions and previewState.voxelModel and drawLightConeOverlay then
          -- Build overlay image same size as previewImage
          local ok, overlay = pcall(function() return Image(previewState.image.width, previewState.image.height, previewState.image.colorMode) end)
          if ok and overlay then
            overlay:clear(Color(0,0,0,0))
            pcall(function() drawLightConeOverlay(overlay, previewState.image, previewState.voxelModel, previewState.modelDimensions, viewParams, isRotating) end)
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
              
              -- Request preview update - use throttled scheduling for both modes
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
              local mainDlg = dialogueManager.mainDialog
              if mainDlg then
                pcall(function()
                  mainDlg:modify{
                    id = "rotationInfo",
                    text = string.format("Euler Space: X=%.0f° Y=%.0f° Z=%.0f°", 
                           viewParams.eulerX, viewParams.eulerY, viewParams.eulerZ)
                  }
                end)
              end
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
        
              -- Request preview update - use throttled scheduling for both modes
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
        if updateLayerScrollStatusLabel then updateLayerScrollStatusLabel() end
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
  
  return previewDlg
end

return previewDialog
