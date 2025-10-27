-- fxStackDialog.lua (UPDATED: removed dlg:clear() usage which is not supported by Aseprite Dialog API)
-- Unified FX Stack dialog for Iso + FaceShade modules.
-- Rebuild now closes and recreates the dialog instead of calling a non-existent :clear()

local fxStack = require("fxStack")

local fxStackDialog = {}

local function colorClone(c)
  return { r=c.r or 255, g=c.g or 255, b=c.b or 255, a=c.a or 255 }
end

local function ensureStack(viewParams)
  if not viewParams.fxStack or not viewParams.fxStack.modules then
    viewParams.fxStack = fxStack.makeDefaultStack()
  end
end

local function moduleLabel(idx, m)
  return string.format("#%d %s %s %s",
    idx,
    m.shape,
    m.type,
    (m.scope == "material") and "mat" or "full"
  )
end

local function addModule(viewParams, duplicateLast)
  ensureStack(viewParams)
  local mods = viewParams.fxStack.modules
  if duplicateLast and #mods > 0 then
    local last = mods[#mods]
    local copy = {}
    for k,v in pairs(last) do
      if k == "colors" then
        copy.colors = {}
        for i,c in ipairs(last.colors) do copy.colors[i] = colorClone(c) end
      else
        copy[k] = v
      end
    end
    copy.id = tostring(os.clock()) .. "_" .. tostring(math.random(1,999999))
    table.insert(mods, copy)
  else
    local base = fxStack.DEFAULT_ISO_ALPHA
    local copy = {}
    for k,v in pairs(base) do
      if k=="colors" then
        copy.colors={}
        for i,c in ipairs(base.colors) do copy.colors[i]=colorClone(c) end
      else
        copy[k]=v
      end
    end
    copy.id = tostring(os.clock()) .. "_" .. tostring(math.random(1,999999))
    table.insert(mods, copy)
  end
end

local function resetStack(viewParams)
  viewParams.fxStack = fxStack.makeDefaultStack()
end

-- We recreate the entire dialog when rebuilding (Aseprite API lacks a generic clear()).
local function buildDialog(viewParams, preserveBounds)
  ensureStack(viewParams)
  fxStack.migrateIfNeeded(viewParams)

  local oldDlg = fxStackDialog._dlg
  local oldBounds = (oldDlg and oldDlg.bounds) or nil
  if oldDlg then pcall(function() oldDlg:close() end) end

  local dlg = Dialog("FX Stack")
  fxStackDialog._dlg = dlg

  local mods = viewParams.fxStack.modules

  -- Forward declaration so callbacks can call it
  local function rebuild()
    buildDialog(viewParams, true)
  end

  dlg:separator{ text="FX Stack Modules" }

  for i, m in ipairs(mods) do
    dlg:separator{ text=moduleLabel(i,m) }

    dlg:combobox{
      id="shape_"..i,
      label="Shape:",
      option=m.shape,
      options={"Iso","FaceShade"},
      onchange=function()
        m.shape = dlg.data["shape_"..i]
        if m.shape == "Iso" and #m.colors ~= 3 then
          m.colors = {
            m.colors[1] or {r=255,g=255,b=255,a=255},
            m.colors[2] or {r=235,g=235,b=235,a=230},
            m.colors[3] or {r=210,g=210,b=210,a=210},
          }
        elseif m.shape == "FaceShade" and #m.colors ~= 6 then
          local new = {}
          for j=1,6 do
            new[j] = m.colors[j] or {r=255,g=255,b=255,a=255}
          end
            m.colors = new
        end
        rebuild()
      end
    }

    dlg:combobox{
      id="type_"..i,
      label="Type:",
      option=m.type,
      options={"alpha","literal"},
      onchange=function()
        m.type = dlg.data["type_"..i]
      end
    }

    dlg:combobox{
      id="scope_"..i,
      label="Scope:",
      option=m.scope,
      options={"full","material"},
      onchange=function()
        m.scope = dlg.data["scope_"..i]
        rebuild()
      end
    }

    if m.scope == "material" then
      dlg:color{
        id="matColor_"..i,
        label="Material:",
        color = m.materialColor and Color(m.materialColor.r, m.materialColor.g, m.materialColor.b, m.materialColor.a or 255) or Color(255,255,255),
        onchange=function()
          local c = dlg.data["matColor_"..i]
          m.materialColor = { r=c.red, g=c.green, b=c.blue, a=c.alpha }
        end
      }
    end

    if m.shape == "Iso" then
      local labels = {"Iso Top","Iso Left","Iso Right"}
      for j=1,3 do
        local c = m.colors[j]
        dlg:color{
          id="c_"..i.."_"..j,
          label=labels[j]..":",
          color=Color(c.r,c.g,c.b,c.a),
          onchange=function()
            local cc = dlg.data["c_"..i.."_"..j]
            m.colors[j] = { r=cc.red,g=cc.green,b=cc.blue,a=cc.alpha }
          end
        }
      end
    else
      local labels = {"Top","Bottom","Front","Back","Left","Right"}
      for j=1,6 do
        local c = m.colors[j]
        dlg:color{
          id="c_"..i.."_"..j,
          label=labels[j]..":",
          color=Color(c.r,c.g,c.b,c.a),
          onchange=function()
            local cc = dlg.data["c_"..i.."_"..j]
            m.colors[j] = { r=cc.red,g=cc.green,b=cc.blue,a=cc.alpha }
          end
        }
        if j==3 then dlg:newrow() end
      end
    end

    dlg:newrow()
    dlg:button{
      id="defaults_"..i,
      text="Defaults",
      onclick=function()
        if m.shape == "Iso" then
          local d = fxStack.DEFAULT_ISO_ALPHA
          m.type = "alpha"
          m.scope = "full"
          m.colors = {}
          for k,c in ipairs(d.colors) do m.colors[k] = colorClone(c) end
        else
          local d = fxStack.DEFAULT_FACESHADE_ALPHA
          m.type = "alpha"
          m.scope = "full"
          m.colors = {}
          for k,c in ipairs(d.colors) do m.colors[k] = colorClone(c) end
        end
        rebuild()
      end
    }
    dlg:button{
      id="up_"..i,
      text="↑",
      onclick=function()
        if i>1 then
          mods[i],mods[i-1] = mods[i-1],mods[i]
          rebuild()
        end
      end
    }
    dlg:button{
      id="down_"..i,
      text="↓",
      onclick=function()
        if i < #mods then
          mods[i],mods[i+1] = mods[i+1],mods[i]
          rebuild()
        end
      end
    }
    dlg:button{
      id="del_"..i,
      text="✕",
      onclick=function()
        table.remove(mods, i)
        rebuild()
      end
    }
  end

  dlg:separator()
  dlg:button{
    id="addModule",
    text="+ Add Module",
    onclick=function()
      addModule(viewParams, true)
      buildDialog(viewParams, true)
    end
  }
  dlg:button{
    id="resetStack",
    text="Reset Stack",
    onclick=function()
      resetStack(viewParams)
      buildDialog(viewParams, true)
    end
  }
  dlg:button{
    id="closeFXStack",
    text="Close",
    onclick=function()
      dlg:close()
    end
  }

  dlg:show{ wait=false }
  if preserveBounds and oldBounds then
    pcall(function() dlg.bounds = oldBounds end)
  end
end

function fxStackDialog.open(viewParams)
  buildDialog(viewParams, false)
end

return fxStackDialog