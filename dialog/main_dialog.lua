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

local function getShaderStack()
  return AseVoxel.render.shader_stack
end

local function getShaderUI()
  return AseVoxel.render.shader_ui
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
  
  -- Shader Stack Testing
  mainDlg:separator{ text = "Shader Stack Testing" }
  mainDlg:button{
    id = "testShaderStack",
    text = "Test Shader Stack",
    onclick = function()
      local shaderStack = getShaderStack()
      if not shaderStack then
        app.alert("Shader stack module not loaded!")
        return
      end
      
      -- Gather test results
      local results = {}
      table.insert(results, "=== Shader Stack Test ===\n")
      
      -- Test 1: Module loaded
      table.insert(results, "✓ Shader stack module loaded")
      
      -- Test 2: List available shaders
      local availableLighting = shaderStack.listShaders("lighting")
      local availableFX = shaderStack.listShaders("fx")
      table.insert(results, string.format("✓ Found %d lighting shaders", #availableLighting))
      table.insert(results, string.format("✓ Found %d FX shaders", #availableFX))
      
      -- Test 3: Current configuration
      if viewParams.shaderStack then
        table.insert(results, string.format("✓ Current config: %d lighting, %d FX", 
          #viewParams.shaderStack.lighting, #viewParams.shaderStack.fx))
      else
        table.insert(results, "⚠ No shader stack configured")
      end
      
      -- Test 4: Try to load each shader
      local errors = {}
      for _, info in ipairs(availableLighting) do
        local shader = shaderStack.getShader(info.id)
        if shader and shader.info and shader.process then
          -- OK
        else
          table.insert(errors, "Lighting shader '" .. info.id .. "' invalid")
        end
      end
      for _, info in ipairs(availableFX) do
        local shader = shaderStack.getShader(info.id)
        if shader and shader.info and shader.process then
          -- OK
        else
          table.insert(errors, "FX shader '" .. info.id .. "' invalid")
        end
      end
      
      if #errors == 0 then
        table.insert(results, "✓ All shaders valid")
      else
        for _, err in ipairs(errors) do
          table.insert(results, "✗ " .. err)
        end
      end
      
      -- Display results
      local resultText = table.concat(results, "\n")
      local dlg = Dialog("Shader Stack Test Results")
      for line in resultText:gmatch("[^\n]+") do
        dlg:label{ text = line }
        dlg:newrow()
      end
      dlg:button{ text = "Close" }
      dlg:show()
    end
  }
  
  mainDlg:button{
    id = "testRenderingPipeline",
    text = "Test Full Pipeline",
    onclick = function()
      -- Test full rendering with current shader stack
      local sprite = app.activeSprite
      if not sprite then
        app.alert("Open a sprite first!")
        return
      end
      
      local startTime = os.clock()
      schedulePreview(true, "pipeline_test")
      local endTime = os.clock()
      
      app.alert(string.format("Pipeline test complete!\nRender time: %.0f ms", 
        (endTime - startTime) * 1000))
    end
  }
  
  mainDlg:button{
    id = "resetToDefault",
    text = "Reset to Default Shader",
    onclick = function()
      viewParams.shaderStack = {
        lighting = {
          { id = "basic", params = { lightIntensity = 50, shadeIntensity = 50 } }
        },
        fx = {}
      }
      schedulePreview(false, "reset_to_default")
      app.alert("Reset to default basicLight shader")
    end
  }
  mainDlg:newrow()
  
  -- Create the Lighting Shaders tab
  mainDlg:tab{
    id = "lightingTab",
    text = "Lighting"
  }
  
  mainDlg:separator{ text="Lighting Shaders" }
  
  -- Initialize shader stack if not present
  if not viewParams.shaderStack then
    viewParams.shaderStack = {
      lighting = {},
      fx = {}
    }
  end
  
  local shaderStack = getShaderStack()
  local shaderUI = getShaderUI()
  
  -- Refresh function to rebuild shader list
  local function refreshLightingList()
    mainDlg:modify{ id="lightingList", text=getLightingListText() }
  end
  
  -- Get lighting shader list text
  function getLightingListText()
    local text = "Lighting Shaders:\n"
    if #viewParams.shaderStack.lighting == 0 then
      text = text .. "  (none - using default)\n"
    else
      for i, shader in ipairs(viewParams.shaderStack.lighting) do
        text = text .. string.format("  %d. %s\n", i, shader.id)
      end
    end
    return text
  end
  
  mainDlg:label{
    id = "lightingList",
    text = getLightingListText()
  }
  
  mainDlg:newrow()
  mainDlg:button{
    id = "addLightingShader",
    text = "Add Lighting Shader...",
    onclick = function()
      if not shaderStack then return end
      
      -- Get available lighting shaders
      local availableShaders = shaderStack.listShaders("lighting")
      if not availableShaders or #availableShaders == 0 then
        app.alert("No lighting shaders available!")
        return
      end
      
      -- Build options list
      local options = {}
      for _, shaderInfo in ipairs(availableShaders) do
        table.insert(options, shaderInfo.info.name .. " (" .. shaderInfo.id .. ")")
      end
      
      -- Show selection dialog
      local selDlg = Dialog("Add Lighting Shader")
      selDlg:combobox{
        id = "shaderChoice",
        label = "Shader:",
        option = options[1],
        options = options
      }
      selDlg:button{
        text = "Add",
        onclick = function()
          local choice = selDlg.data.shaderChoice
          -- Extract shader ID from "Name (id)" format
          local shaderId = choice:match("%((.+)%)")
          
          if shaderId then
            -- Get shader module
            local shader = shaderStack.getShader(shaderId)
            if shader then
              -- Create default params
              local defaultParams = {}
              if shader.paramSchema then
                for _, param in ipairs(shader.paramSchema) do
                  defaultParams[param.name] = param.default
                end
              end
              
              -- Add to stack
              table.insert(viewParams.shaderStack.lighting, {
                id = shaderId,
                params = defaultParams
              })
              
              refreshLightingList()
              schedulePreview(false, "lighting_shader_added")
            end
          end
          
          selDlg:close()
        end
      }
      selDlg:button{ text = "Cancel" }
      selDlg:show()
    end
  }
  
  mainDlg:button{
    id = "configureLighting",
    text = "Configure Shaders...",
    onclick = function()
      if #viewParams.shaderStack.lighting == 0 then
        app.alert("No lighting shaders to configure!\nAdd a shader first.")
        return
      end
      
      -- Open configuration dialog
      local cfgDlg = Dialog("Configure Lighting Shaders")
      
      for i, shaderConfig in ipairs(viewParams.shaderStack.lighting) do
        local shader = shaderStack.getShader(shaderConfig.id)
        if shader then
          cfgDlg:separator{ text = string.format("%d. %s", i, shader.info.name) }
          
          -- Move up/down/remove buttons
          cfgDlg:button{
            text = "↑",
            onclick = function()
              if i > 1 then
                viewParams.shaderStack.lighting[i], viewParams.shaderStack.lighting[i-1] = 
                  viewParams.shaderStack.lighting[i-1], viewParams.shaderStack.lighting[i]
                cfgDlg:close()
                schedulePreview(false, "lighting_reorder")
                refreshLightingList()
              end
            end
          }
          cfgDlg:button{
            text = "↓",
            onclick = function()
              if i < #viewParams.shaderStack.lighting then
                viewParams.shaderStack.lighting[i], viewParams.shaderStack.lighting[i+1] = 
                  viewParams.shaderStack.lighting[i+1], viewParams.shaderStack.lighting[i]
                cfgDlg:close()
                schedulePreview(false, "lighting_reorder")
                refreshLightingList()
              end
            end
          }
          cfgDlg:button{
            text = "Remove",
            onclick = function()
              table.remove(viewParams.shaderStack.lighting, i)
              cfgDlg:close()
              schedulePreview(false, "lighting_removed")
              refreshLightingList()
            end
          }
          
          cfgDlg:newrow()
          
          -- Build parameter UI
          if shaderUI then
            shaderUI.buildShaderUI(cfgDlg, shader, shaderConfig.params, function(paramName, newValue)
              shaderConfig.params[paramName] = newValue
              schedulePreview(false, "lighting_param_change")
            end)
          end
        end
      end
      
      cfgDlg:button{ text = "Close" }
      cfgDlg:show()
    end
  }
  
  mainDlg:button{
    id = "clearLightingShaders",
    text = "Clear All",
    onclick = function()
      viewParams.shaderStack.lighting = {}
      refreshLightingList()
      schedulePreview(false, "lighting_cleared")
    end
  }
  
  -- Create the FX Shaders tab
  mainDlg:tab{
    id = "fxTab",
    text = "FX"
  }
  
  mainDlg:separator{ text="FX Shaders" }
  
  -- Refresh function for FX list
  local function refreshFXList()
    mainDlg:modify{ id="fxList", text=getFXListText() }
  end
  
  -- Get FX shader list text
  function getFXListText()
    local text = "FX Shaders:\n"
    if #viewParams.shaderStack.fx == 0 then
      text = text .. "  (none)\n"
    else
      for i, shader in ipairs(viewParams.shaderStack.fx) do
        text = text .. string.format("  %d. %s\n", i, shader.id)
      end
    end
    return text
  end
  
  mainDlg:label{
    id = "fxList",
    text = getFXListText()
  }
  
  mainDlg:newrow()
  mainDlg:button{
    id = "addFXShader",
    text = "Add FX Shader...",
    onclick = function()
      if not shaderStack then return end
      
      -- Get available FX shaders
      local availableShaders = shaderStack.listShaders("fx")
      if not availableShaders or #availableShaders == 0 then
        app.alert("No FX shaders available!")
        return
      end
      
      -- Build options list
      local options = {}
      for _, shaderInfo in ipairs(availableShaders) do
        table.insert(options, shaderInfo.info.name .. " (" .. shaderInfo.id .. ")")
      end
      
      -- Show selection dialog
      local selDlg = Dialog("Add FX Shader")
      selDlg:combobox{
        id = "shaderChoice",
        label = "Shader:",
        option = options[1],
        options = options
      }
      selDlg:button{
        text = "Add",
        onclick = function()
          local choice = selDlg.data.shaderChoice
          -- Extract shader ID from "Name (id)" format
          local shaderId = choice:match("%((.+)%)")
          
          if shaderId then
            -- Get shader module
            local shader = shaderStack.getShader(shaderId)
            if shader then
              -- Create default params
              local defaultParams = {}
              if shader.paramSchema then
                for _, param in ipairs(shader.paramSchema) do
                  defaultParams[param.name] = param.default
                end
              end
              
              -- Add to stack
              table.insert(viewParams.shaderStack.fx, {
                id = shaderId,
                params = defaultParams
              })
              
              refreshFXList()
              schedulePreview(false, "fx_shader_added")
            end
          end
          
          selDlg:close()
        end
      }
      selDlg:button{ text = "Cancel" }
      selDlg:show()
    end
  }
  
  mainDlg:button{
    id = "configureFX",
    text = "Configure Shaders...",
    onclick = function()
      if #viewParams.shaderStack.fx == 0 then
        app.alert("No FX shaders to configure!\nAdd a shader first.")
        return
      end
      
      -- Open configuration dialog
      local cfgDlg = Dialog("Configure FX Shaders")
      
      for i, shaderConfig in ipairs(viewParams.shaderStack.fx) do
        local shader = shaderStack.getShader(shaderConfig.id)
        if shader then
          cfgDlg:separator{ text = string.format("%d. %s", i, shader.info.name) }
          
          -- Move up/down/remove buttons
          cfgDlg:button{
            text = "↑",
            onclick = function()
              if i > 1 then
                viewParams.shaderStack.fx[i], viewParams.shaderStack.fx[i-1] = 
                  viewParams.shaderStack.fx[i-1], viewParams.shaderStack.fx[i]
                cfgDlg:close()
                schedulePreview(false, "fx_reorder")
                refreshFXList()
              end
            end
          }
          cfgDlg:button{
            text = "↓",
            onclick = function()
              if i < #viewParams.shaderStack.fx then
                viewParams.shaderStack.fx[i], viewParams.shaderStack.fx[i+1] = 
                  viewParams.shaderStack.fx[i+1], viewParams.shaderStack.fx[i]
                cfgDlg:close()
                schedulePreview(false, "fx_reorder")
                refreshFXList()
              end
            end
          }
          cfgDlg:button{
            text = "Remove",
            onclick = function()
              table.remove(viewParams.shaderStack.fx, i)
              cfgDlg:close()
              schedulePreview(false, "fx_removed")
              refreshFXList()
            end
          }
          
          cfgDlg:newrow()
          
          -- Build parameter UI
          if shaderUI then
            shaderUI.buildShaderUI(cfgDlg, shader, shaderConfig.params, function(paramName, newValue)
              shaderConfig.params[paramName] = newValue
              schedulePreview(false, "fx_param_change")
            end)
          end
        end
      end
      
      cfgDlg:button{ text = "Close" }
      cfgDlg:show()
    end
  }
  
  mainDlg:button{
    id = "clearFXShaders",
    text = "Clear All",
    onclick = function()
      viewParams.shaderStack.fx = {}
      refreshFXList()
      schedulePreview(false, "fx_cleared")
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
