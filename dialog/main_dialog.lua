-- main_dialog.lua
-- Main controls dialog UI for AseVoxel model viewer
-- Contains all tabs: Info, Export, Modeler, Debug, FX
-- Dependencies: Loaded via AseVoxel namespace

local mainDialog = {}

-- Access dependencies through global namespace
local function getDialogManager()
  return AseVoxel.dialog.dialog_manager
end

local function getViewerCore()
  return AseVoxel.viewerCore
end

local function getPreviewRenderer()
  return AseVoxel.render.preview_renderer
end

local function getFxStack()
  return AseVoxel.fxStack
end

local function getFxStackDialog()
  return AseVoxel.dialog.fx_stack_dialog
end

local function getMathUtils()
  return AseVoxel.mathUtils
end

local function getRotation()
  return AseVoxel.math.rotation
end

-- Create main controls dialog
function mainDialog.create(viewParams, schedulePreview, rotateModel, updateLayerScrollStatusLabel, previewState)
  local mainDlg = Dialog("AseVoxel - Model Viewer")
  local dialogueManager = getDialogManager()
  local viewerCore = getViewerCore()
  local previewRenderer = getPreviewRenderer()
  local fxStack = getFxStack()
  local fxStackDialog = getFxStackDialog()
  
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

  -- Rendering Mode Selection
  mainDlg:separator{ text = "Rendering" }
  mainDlg:check{
    id = "directCanvasRendering",
    text = "Direct Canvas Rendering (experimental)",
    selected = (viewParams.renderMode == "DirectCanvas"),
    onclick = function()
      viewParams.renderMode = mainDlg.data.directCanvasRendering 
        and "DirectCanvas" 
        or "OffscreenImage"
      
      -- Update antialiasing toggle state
      mainDlg:modify{
        id = "enableAntialiasing",
        enabled = mainDlg.data.directCanvasRendering
      }
      
      schedulePreview(false, "renderMode")
    end
  }
  mainDlg:newrow()
  mainDlg:check{
    id = "enableAntialiasing",
    text = "Enable Antialiasing",
    selected = viewParams.enableAntialiasing,
    enabled = (viewParams.renderMode == "DirectCanvas"),
    onclick = function()
      if mainDlg.data.directCanvasRendering then
        viewParams.enableAntialiasing = mainDlg.data.enableAntialiasing
        schedulePreview(false, "antialiasing")
      end
    end
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
      local previewDlg = newPreview -- reuse local for schedulePreview()
      local previewCanvasWidth = 400
      local previewCanvasHeight = 400
      local previewOffsetX = 0
      local previewOffsetY = 0
      local previewImage = nil
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
      if previewState.voxelModel and #previewState.voxelModel > 0 then
        dialogueManager.openExportDialog(previewState.voxelModel)
      else
        app.alert("No model to export!")
      end
    end
  }
  
  mainDlg:button{
    id = "animateButton",
    text = "Create Animation...",
    onclick = function()
      if previewState.voxelModel and #previewState.voxelModel > 0 then
        dialogueManager.openAnimationDialog(viewParams, previewState.voxelModel, previewState.modelDimensions)
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
      local nativeBridge = AseVoxel.nativeBridge
      if nativeBridge and nativeBridge.setForceDisabled then
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
      local nativeBridge = AseVoxel.nativeBridge
      local nativeTxt = "Native: not loaded"
      if nativeBridge and nativeBridge.getStatus then
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
  
  -- Performance Profiling Section
  mainDlg:separator{ text = "Performance Profiling" }
  mainDlg:check{
    id = "enableProfiling",
    text = "Enable Profiling",
    selected = viewParams.enableProfiling or false,
    onclick = function()
      viewParams.enableProfiling = mainDlg.data.enableProfiling
    end
  }
  mainDlg:newrow()
  mainDlg:button{
    id = "showProfilingReport",
    text = "Show Profiling Report",
    onclick = function()
      local profiler = AseVoxel.utils.performance_profiler
      if not profiler then
        app.alert("Profiler not available")
        return
      end
      
      local report = profiler.generateReport("renderPreview")
      if not report or report == "" then
        app.alert("No profiling data collected yet.\n\nEnable profiling and rotate the model to collect data.")
        return
      end
      
      -- Display in alert or create a new dialog
      local dlg = Dialog("Performance Report")
      dlg:label{ text = "Rendering Performance (50 samples max):" }
      dlg:newrow()
      
      -- Show report in a text area (multiline label)
      local lines = {}
      for line in report:gmatch("[^\r\n]+") do
        table.insert(lines, line)
      end
      
      for _, line in ipairs(lines) do
        dlg:label{ text = line }
        dlg:newrow()
      end
      
      dlg:button{
        text = "Copy to Clipboard",
        onclick = function()
          app.clipboard = report
          app.alert("Report copied to clipboard!")
        end
      }
      dlg:button{ text = "Close" }
      dlg:show()
    end
  }
  mainDlg:button{
    id = "clearProfilingData",
    text = "Clear Samples",
    onclick = function()
      local profiler = AseVoxel.utils.performance_profiler
      if profiler then
        profiler.clearProfile("renderPreview")
        app.alert("Profiling data cleared")
      end
    end
  }
  mainDlg:newrow()
  
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
    options={"None","Basic","Dynamic","Stack"},
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
      if dialogueManager.previewDialog then pcall(function() dialogueManager.previewDialog:repaint() end) end
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
      if dialogueManager.previewDialog then pcall(function() dialogueManager.previewDialog:repaint() end) end
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
      if dialogueManager.previewDialog then pcall(function() dialogueManager.previewDialog:repaint() end) end
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
  
  return mainDlg
end

return mainDialog
