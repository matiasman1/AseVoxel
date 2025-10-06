-- fxStackDialog.lua (updated layout to horizontal rows)

local fxStack = require("fxStack")
local fxStackDialog = {}

local function cloneColor(c) return {r=c.r or 255,g=c.g or 255,b=c.b or 255,a=c.a or 255} end

local function ensureStack(vp)
  if not vp.fxStack or not vp.fxStack.modules then vp.fxStack = fxStack.makeDefaultStack() end
  for _,m in ipairs(vp.fxStack.modules) do if m.tintAlpha==nil then m.tintAlpha=false end end
end

local function moduleLabel(i,m)
  return string.format("#%d %s %s %s", i, m.shape, m.type, m.scope=="material" and "mat" or "full")
end

local function addModule(vp, dup)
  ensureStack(vp)
  local mods=vp.fxStack.modules
  if dup and #mods>0 then
    local last=mods[#mods]
    local copy={}
    for k,v in pairs(last) do
      if k=="colors" then
        copy.colors={}
        for i,c in ipairs(last.colors) do copy.colors[i]=cloneColor(c) end
      else copy[k]=v end
    end
    copy.id=tostring(os.clock()).."-"..math.random(1,999999)
    table.insert(mods, copy)
  else
    local base=fxStack.DEFAULT_ISO_ALPHA
    local copy={}
    for k,v in pairs(base) do
      if k=="colors" then
        copy.colors={}
        for i,c in ipairs(base.colors) do copy.colors[i]=cloneColor(c) end
      else copy[k]=v end
    end
    copy.id=tostring(os.clock()).."-"..math.random(1,999999)
    table.insert(mods, copy)
  end
end

local function resetStack(vp)
  vp.fxStack = fxStack.makeDefaultStack()
end

local function rebuild(vp)
  ensureStack(vp)
  if fxStackDialog._dlg then pcall(function() fxStackDialog._dlg:close() end) end
  local dlg = Dialog("FX Stack")
  fxStackDialog._dlg = dlg

  dlg:separator{text="FX Stack Modules"}

  local mods=vp.fxStack.modules
  for i,m in ipairs(mods) do
    dlg:separator{text=moduleLabel(i,m)}

    dlg:combobox{
      id="shape_"..i,label="Shape:",option=m.shape,options={"Iso","FaceShade"},
      onchange=function()
        m.shape=dlg.data["shape_"..i]
        if m.shape=="Iso" and #m.colors~=3 then
          m.colors={
            m.colors[1] or {r=255,g=255,b=255,a=255},
            m.colors[2] or {r=235,g=235,b=235,a=230},
            m.colors[3] or {r=210,g=210,b=210,a=210},
          }
        elseif m.shape=="FaceShade" and #m.colors~=6 then
          local new={}
          for j=1,6 do new[j]=m.colors[j] or {r=255,g=255,b=255,a=255} end
          m.colors=new
        end
        rebuild(vp)
      end
    }
    dlg:combobox{
      id="type_"..i,label="Type:",option=m.type,options={"alpha","literal"},
      onchange=function() m.type=dlg.data["type_"..i]; rebuild(vp) end
    }
    dlg:combobox{
      id="scope_"..i,label="Scope:",option=m.scope,options={"full","material"},
      onchange=function() m.scope=dlg.data["scope_"..i]; rebuild(vp) end
    }

    if m.scope=="material" then
      dlg:color{
        id="mat_"..i,label="Material:",
        color = m.materialColor and Color(m.materialColor.r,m.materialColor.g,m.materialColor.b,m.materialColor.a) or Color(255,255,255),
        onchange=function()
          local c=dlg.data["mat_"..i]
          m.materialColor={r=c.red,g=c.green,b=c.blue,a=c.alpha}
        end
      }
    end

    if m.type=="alpha" then
      dlg:check{
        id="tint_"..i,
        text="Tint",
        selected=m.tintAlpha,
        onclick=function() m.tintAlpha=dlg.data["tint_"..i] end
      }
    end

    -- Horizontal face layout
    if m.shape=="Iso" then
      -- Corrected ordering: Top, Left, Right
      dlg:newrow()
      dlg:label{text="Top"}; dlg:label{text="Left"}; dlg:label{text="Right"}
      dlg:newrow()
      local order = { {idx=1,label="Top"}, {idx=2,label="Left"}, {idx=3,label="Right"} }
      for _,info in ipairs(order) do
        local c = m.colors[info.idx]
        dlg:color{
          id="iso_"..i.."_"..info.idx,
          color=Color(c.r,c.g,c.b,c.a),
          onchange=function()
            local cc=dlg.data["iso_"..i.."_"..info.idx]
            m.colors[info.idx]={r=cc.red,g=cc.green,b=cc.blue,a=cc.alpha}
          end
        }
      end
    else
      dlg:newrow()
      -- Display order: top bottom left right front back (labels)
      local disp = {"Top","Bottom","Left","Right","Front","Back"}
      for _,lab in ipairs(disp) do dlg:label{text=lab} end
      dlg:newrow()
      -- Map display order to internal indices
      local map = {Top=1,Bottom=2,Front=3,Back=4,Left=5,Right=6}
      for _,lab in ipairs(disp) do
        local idx=map[lab]
        local c=m.colors[idx]
        dlg:color{
          id="fs_"..i.."_"..lab,
          color=Color(c.r,c.g,c.b,c.a),
          onchange=function()
            local cc=dlg.data["fs_"..i.."_"..lab]
            m.colors[idx]={r=cc.red,g=cc.green,b=cc.blue,a=cc.alpha}
          end
        }
      end
    end

    dlg:newrow()
    dlg:button{id="def_"..i,text="Defaults",onclick=function()
      if m.shape=="Iso" then
        local d=fxStack.DEFAULT_ISO_ALPHA
        m.type="alpha"; m.scope="full"; m.tintAlpha=false
        m.colors={cloneColor(d.colors[1]),cloneColor(d.colors[2]),cloneColor(d.colors[3])}
      else
        local d=fxStack.DEFAULT_FACESHADE_ALPHA
        m.type="alpha"; m.scope="full"; m.tintAlpha=false
        m.colors={}
        for k,c in ipairs(d.colors) do m.colors[k]=cloneColor(c) end
      end
      rebuild(vp)
    end}
    dlg:button{id="up_"..i,text="↑",onclick=function()
      if i>1 then mods[i],mods[i-1]=mods[i-1],mods[i]; rebuild(vp) end
    end}
    dlg:button{id="dn_"..i,text="↓",onclick=function()
      if i<#mods then mods[i],mods[i+1]=mods[i+1],mods[i]; rebuild(vp) end
    end}
    dlg:button{id="del_"..i,text="✕",onclick=function()
      table.remove(mods,i); rebuild(vp)
    end}
  end

  dlg:separator()
  dlg:button{id="add",text="+ Add Module",onclick=function() addModule(vp,true); rebuild(vp) end}
  dlg:button{id="reset",text="Reset Stack",onclick=function() resetStack(vp); rebuild(vp) end}
  dlg:button{id="close",text="Close",onclick=function() dlg:close() end}

  dlg:show{wait=false}
end

function fxStackDialog.open(vp)
  ensureStack(vp)
  fxStack.migrateIfNeeded(vp)
  rebuild(vp)
end

return fxStackDialog