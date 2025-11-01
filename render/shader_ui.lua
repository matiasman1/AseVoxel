-- Auto-generate UI from shader parameter schemas

local shaderUI = {}

-- Widget builders for each parameter type
shaderUI.widgets = {
  slider = function(dlg, param, value, onChange)
    dlg:slider{
      id = param.name,
      label = param.label or param.name,
      min = param.min or 0,
      max = param.max or 100,
      value = value or param.default,
      onchange = function() onChange(param.name, dlg.data[param.name]) end
    }
    if param.tooltip then
      dlg:label{
        text = param.tooltip
      }
    end
  end,
  
  color = function(dlg, param, value, onChange)
    local c = value or param.default or {r=255, g=255, b=255}
    dlg:color{
      id = param.name,
      label = param.label or param.name,
      color = Color(c.r, c.g, c.b),
      onchange = function()
        local col = dlg.data[param.name]
        onChange(param.name, {r=col.red, g=col.green, b=col.blue})
      end
    }
    if param.tooltip then
      dlg:label{
        text = param.tooltip
      }
    end
  end,
  
  bool = function(dlg, param, value, onChange)
    dlg:check{
      id = param.name,
      label = param.label or param.name,
      selected = value or param.default or false,
      onchange = function() onChange(param.name, dlg.data[param.name]) end
    }
    if param.tooltip then
      dlg:label{
        text = param.tooltip
      }
    end
  end,
  
  vector = function(dlg, param, value, onChange)
    -- Pitch + Yaw sliders with optional cone preview
    local v = value or param.default or {pitch=0, yaw=0}
    dlg:slider{
      id = param.name .. "_pitch",
      label = (param.label or param.name) .. " Pitch",
      min = param.pitchMin or -90,
      max = param.pitchMax or 90,
      value = v.pitch,
      onchange = function()
        onChange(param.name, {
          pitch = dlg.data[param.name .. "_pitch"],
          yaw = dlg.data[param.name .. "_yaw"]
        })
      end
    }
    dlg:slider{
      id = param.name .. "_yaw",
      label = (param.label or param.name) .. " Yaw",
      min = param.yawMin or 0,
      max = param.yawMax or 360,
      value = v.yaw,
      onchange = function()
        onChange(param.name, {
          pitch = dlg.data[param.name .. "_pitch"],
          yaw = dlg.data[param.name .. "_yaw"]
        })
      end
    }
    if param.tooltip then
      dlg:label{
        text = param.tooltip
      }
    end
  end,
  
  material = function(dlg, param, value, onChange)
    -- Color picker + material selector (opaque/glass/metal/etc)
    local v = value or param.default or {r=255, g=255, b=255, type="opaque"}
    dlg:color{
      id = param.name .. "_color",
      label = param.label or param.name,
      color = Color(v.r, v.g, v.b),
      onchange = function()
        local col = dlg.data[param.name .. "_color"]
        onChange(param.name, {
          r = col.red, g = col.green, b = col.blue,
          type = dlg.data[param.name .. "_type"]
        })
      end
    }
    dlg:combobox{
      id = param.name .. "_type",
      option = v.type,
      options = {"opaque", "glass", "metal", "emissive", "dither"},
      onchange = function()
        local col = dlg.data[param.name .. "_color"]
        onChange(param.name, {
          r = col.red, g = col.green, b = col.blue,
          type = dlg.data[param.name .. "_type"]
        })
      end
    }
    if param.tooltip then
      dlg:label{
        text = param.tooltip
      }
    end
  end,
  
  choice = function(dlg, param, value, onChange)
    dlg:combobox{
      id = param.name,
      label = param.label or param.name,
      option = value or param.default,
      options = param.options or {"option1", "option2"},
      onchange = function() onChange(param.name, dlg.data[param.name]) end
    }
    if param.tooltip then
      dlg:label{
        text = param.tooltip
      }
    end
  end
}

-- Build UI for shader (auto-generated or custom)
function shaderUI.buildShaderUI(dlg, shader, params, onChange)
  if shader.buildUI then
    -- Custom UI provided by shader
    shader.buildUI(dlg, params, onChange)
  else
    -- Auto-generate from param schema
    for _, paramDef in ipairs(shader.paramSchema or {}) do
      local widgetBuilder = shaderUI.widgets[paramDef.type]
      if widgetBuilder then
        widgetBuilder(dlg, paramDef, params[paramDef.name], onChange)
      else
        print("[AseVoxel] Unknown param type: " .. tostring(paramDef.type))
      end
    end
  end
end

-- Create a collapsible shader entry in the UI
function shaderUI.createShaderEntry(dlg, shader, params, callbacks)
  -- callbacks = {
  --   onChange = function(paramName, newValue) end,
  --   onMoveUp = function() end,
  --   onMoveDown = function() end,
  --   onRemove = function() end,
  --   onToggle = function(enabled) end
  -- }
  
  -- Create collapsible header
  dlg:separator{ text = shader.info.name }
  
  -- Controls row
  dlg:check{
    id = shader.info.id .. "_enabled",
    text = "Enabled",
    selected = params.enabled or true,
    onclick = function()
      if callbacks.onToggle then
        callbacks.onToggle(dlg.data[shader.info.id .. "_enabled"])
      end
    end
  }
  
  dlg:button{
    id = shader.info.id .. "_up",
    text = "↑",
    onclick = function()
      if callbacks.onMoveUp then callbacks.onMoveUp() end
    end
  }
  
  dlg:button{
    id = shader.info.id .. "_down",
    text = "↓",
    onclick = function()
      if callbacks.onMoveDown then callbacks.onMoveDown() end
    end
  }
  
  dlg:button{
    id = shader.info.id .. "_remove",
    text = "✕",
    onclick = function()
      if callbacks.onRemove then callbacks.onRemove() end
    end
  }
  
  -- Build parameter UI
  shaderUI.buildShaderUI(dlg, shader, params, callbacks.onChange)
end

return shaderUI
