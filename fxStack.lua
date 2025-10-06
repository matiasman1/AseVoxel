-- fxStack.lua (updated per new spec)

local fxStack = {}

fxStack.TOP_THRESHOLD = 0.25
fxStack.FACE_ORDER = { "top","bottom","front","back","left","right" }

-- For UI horizontal FaceShade layout desired order:
fxStack.FACESHADE_DISPLAY_ORDER = { "top","bottom","left","right","front","back" }

fxStack.LOCAL_NORMALS = {
  -- NOTE (Phase 4 fix):
  -- In prior builds the semantic labels “top” and “bottom” appeared inverted in shading.
  -- We flip the underlying Y direction and compensate in FaceShade application so the
  -- user’s “Top” color now correctly affects the upward-facing face.
  top    = {0,  -1,  0},
  bottom = {0,   1,  0},
  front  = {0,   0, -1},
  back   = {0,   0,  1},
  left   = {-1,  0,  0},
  right  = {1,   0,  0},
}

fxStack.DEFAULT_ISO_ALPHA = {
  shape = "Iso",
  type = "alpha",
  scope = "full",
  colors = {
    {r=255,g=255,b=255,a=255},
    {r=235,g=235,b=235,a=230},
    {r=210,g=210,b=210,a=210},
  },
  tintAlpha = false
}

fxStack.DEFAULT_FACESHADE_ALPHA = {
  shape = "FaceShade",
  type = "alpha",
  scope = "full",
  colors = {
    {r=255,g=255,b=255,a=255}, -- Top
    {r=255,g=255,b=255,a=180}, -- Bottom
    {r=255,g=255,b=255,a=255}, -- Front
    {r=255,g=255,b=255,a=220}, -- Back
    {r=255,g=255,b=255,a=210}, -- Left
    {r=255,g=255,b=255,a=230}, -- Right
  },
  tintAlpha = false
}

local function clone(t)
  if type(t) ~= "table" then return t end
  local r = {}
  for k,v in pairs(t) do r[k] = clone(v) end
  return r
end

function fxStack.makeDefaultStack()
  return {
    modules = {
      clone(fxStack.DEFAULT_ISO_ALPHA),
      clone(fxStack.DEFAULT_FACESHADE_ALPHA)
    }
  }
end

function fxStack.migrateIfNeeded(viewParams)
  if viewParams.fxStack and viewParams._fxStack_migrated then return end
  if not viewParams.fxStack then
    viewParams.fxStack = fxStack.makeDefaultStack()
  end
  local migrated=false
  if viewParams.isoColors then
    local c = viewParams.isoColors
    table.insert(viewParams.fxStack.modules, 1, {
      shape="Iso", type="literal", scope="full", tintAlpha=false,
      colors={
        {r=c.top.r,g=c.top.g,b=c.top.b,a=c.top.a or 255},
        {r=c.left.r,g=c.left.g,b=c.left.b,a=c.left.a or 255},
        {r=c.right.r,g=c.right.g,b=c.right.b,a=c.right.a or 255}
      }
    })
    migrated=true
  end
  if viewParams.faceShaders and viewParams.faceShaders.colors then
    local fs=viewParams.faceShaders
    local function toC(t) return {r=t.r or 255,g=t.g or 255,b=t.b or 255,a=t.a or 255} end
    table.insert(viewParams.fxStack.modules,{
      shape="FaceShade",
      type= fs.mode=="literal" and "literal" or "alpha",
      scope="full",
      tintAlpha=false,
      colors={
        toC(fs.colors.top or {}),
        toC(fs.colors.bottom or {}),
        toC(fs.colors.front or {}),
        toC(fs.colors.back or {}),
        toC(fs.colors.left or {}),
        toC(fs.colors.right or {})
      }
    })
    migrated=true
  end
  viewParams._fxStack_migrated = migrated or true
end

local function rotateVec(v,M)
  return {
    M[1][1]*v[1]+M[1][2]*v[2]+M[1][3]*v[3],
    M[2][1]*v[1]+M[2][2]*v[2]+M[2][3]*v[3],
    M[3][1]*v[1]+M[3][2]*v[2]+M[3][3]*v[3]
  }
end
local function norm(v)
  local m=math.sqrt(v[1]*v[1]+v[2]*v[2]+v[3]*v[3])
  if m<1e-9 then return {0,0,0} end
  return {v[1]/m,v[2]/m,v[3]/m}
end

function fxStack.computeRotatedNormals(R, viewDir)
  local o={}
  for face,n in pairs(fxStack.LOCAL_NORMALS) do
    local nr = rotateVec(n,R)
    local nn = norm(nr)
    local d = nn[1]*viewDir[1]+nn[2]*viewDir[2]+nn[3]*viewDir[3]
    o[face]={normal=nn,dot=d}
  end
  return o
end

-- ISO selection per new spec: top = MOST NEGATIVE Y among front-facing (dot>0),
-- remaining two faces become left/right by sign of normal.x (neg=left,pos=right).
function fxStack.selectIsoFaces(rotInfo)
  if not rotInfo then return { isoFaces={top=nil,left=nil,right=nil}, order={} } end

  -- 1) Pick TOP strictly from physical top/bottom
  local dTop    = (rotInfo.top    and rotInfo.top.dot)    or -math.huge
  local dBottom = (rotInfo.bottom and rotInfo.bottom.dot) or -math.huge
  local topName = (dTop >= dBottom) and "top" or "bottom"

  -- 2) Collect side candidates (front/back/left/right) with visibility (dot>0 preferred)
  local sideNames = { "front","back","left","right" }
  local sides = {}
  for _,name in ipairs(sideNames) do
    local info = rotInfo[name]
    if info then
      sides[#sides+1] = { face=name, dot = info.dot or -math.huge, nx = (info.normal and info.normal[1]) or 0 }
    end
  end
  -- Prefer only visible faces (dot>0). If fewer than 2 visible, fall back to best by dot.
  local visibles = {}
  for _,s in ipairs(sides) do if s.dot and s.dot > 0 then visibles[#visibles+1] = s end end
  local pool = (#visibles >= 2) and visibles or sides
  table.sort(pool, function(a,b) return (a.dot or -1e9) > (b.dot or -1e9) end)
  local s1 = pool[1]
  local s2 = pool[2]
  if not s1 or not s2 then
    -- Degenerate case
    return { isoFaces = { top = topName, left = s1 and s1.face or nil, right = s2 and s2.face or nil }, order = { "top","left","right" } }
  end

  -- 3) Assign LEFT/RIGHT by normal.x. Larger +nx => RIGHT; smaller (or negative) => LEFT
  local leftName, rightName
  if (s1.nx or 0) == (s2.nx or 0) then
    -- Tie: designate the one with larger nx as right
    if (s1.nx or 0) >= (s2.nx or 0) then rightName = s1.face; leftName = s2.face
    else rightName = s2.face; leftName = s1.face end
  else
    if (s1.nx or 0) > (s2.nx or 0) then rightName = s1.face; leftName = s2.face
    else rightName = s2.face; leftName = s1.face end
  end

  local mapping = { top = topName, left = leftName, right = rightName }
  local ordered = {}
  if mapping.top   then ordered[#ordered+1] = "top" end
  if mapping.left  then ordered[#ordered+1] = "left" end
  if mapping.right then ordered[#ordered+1] = "right" end
  return { isoFaces = mapping, order = ordered }
end

-- Mapping for FaceShade internal indices
local faceToIndex = {
  -- Canonical storage order retained; swap handled at apply time.
  top=1,bottom=2,front=3,back=4,left=5,right=6
}

-- Helper: determine ordered side pair for ISO literal mode based on spec:
-- Visible adjacent ordered pairs:
-- (front,right) (right,back) (back,left) (left,front)
-- RIGHT color applies to the FIRST face of the matched pair
-- LEFT  color applies to the SECOND face of the matched pair
local function computeIsoLiteralSidePair(rotInfo)
  local visibles = {}
  for name,info in pairs(rotInfo) do
    if info.dot and info.dot>0 then visibles[name]=true end
  end
  local pairsOrdered = {
    {"front","right"},
    {"right","back"},
    {"back","left"},
    {"left","front"}
  }
  local best,nilScore = nil,-1
  for _,pr in ipairs(pairsOrdered) do
    local a,b = pr[1],pr[2]
    if visibles[a] and visibles[b] then
      local score = (rotInfo[a].dot or 0)+(rotInfo[b].dot or 0)
      if score>nilScore then
        nilScore=score
        best={first=a,second=b}
      end
    end
  end
  return best
end

-- Apply one module
local function applyModule(module, faceName, faceRoleIso, baseColor, voxelColorOriginal)
  -- Material scope check (original color)
  if module.scope=="material" and module.materialColor then
    local mc=module.materialColor
    local r,g,b,a = voxelColorOriginal.r, voxelColorOriginal.g, voxelColorOriginal.b, voxelColorOriginal.a or 255
    if not (r==mc.r and g==mc.g and b==mc.b and a==(mc.a or 255)) then
      return baseColor
    end
  end

  local idx
  if module.shape=="FaceShade" then
    idx = faceToIndex[faceName]
    -- Phase 4 FIX: historical inversion correction (swap top/bottom color slots on apply)
    if faceName == "top" then
      idx = faceToIndex.bottom
    elseif faceName == "bottom" then
      idx = faceToIndex.top
    end
  elseif module.shape=="Iso" then
    if faceRoleIso=="top" then idx=1
    elseif faceRoleIso=="left" then idx=2
    elseif faceRoleIso=="right" then idx=3 end
  end
  if not idx or not module.colors[idx] then return baseColor end

  local mcol = module.colors[idx]
  local out = {r=baseColor.r,g=baseColor.g,b=baseColor.b,a=baseColor.a}

  if module.type=="literal" then
    -- Literal: direct RGB replace (keep alpha)
    out.r,out.g,out.b = mcol.r,mcol.g,mcol.b
  else
    -- Alpha (brightness/tint)
    local alphaNorm = (mcol.a or 255)/255
    local minB=0.2
    local brightness = minB + (1-minB)*alphaNorm
    out.r = math.floor(out.r * brightness + 0.5)
    out.g = math.floor(out.g * brightness + 0.5)
    out.b = math.floor(out.b * brightness + 0.5)
    if module.tintAlpha then
      out.r = math.floor(out.r * (mcol.r/255) + 0.5)
      out.g = math.floor(out.g * (mcol.g/255) + 0.5)
      out.b = math.floor(out.b * (mcol.b/255) + 0.5)
    end
  end
  return out
end

function fxStack.shadeFace(params, faceName, voxelColor)
  local stack = params.fxStack and params.fxStack.modules
  if not stack or #stack==0 then return voxelColor end

  if not params._frameIsoCache then
    local vd = params.viewDir or {0,0,1}
    local mag=math.sqrt(vd.x*vd.x+vd.y*vd.y+vd.z*vd.z)
    if mag>1e-6 then vd={x=vd.x/mag,y=vd.y/mag,z=vd.z/mag} else vd={x=0,y=0,z=1} end
    local rotInfo = fxStack.computeRotatedNormals(params.rotationMatrix, {vd.x,vd.y,vd.z})
    local isoSel = fxStack.selectIsoFaces(rotInfo)         -- legacy alpha roles
    local sidePair = computeIsoLiteralSidePair(rotInfo)    -- new literal roles

    -- Precompute literal role mapping (implements new rule):
    -- 1) top color -> top & bottom
    -- 2) sidePair.first -> right color, sidePair.second -> left color
    -- 3) If a physical left/right face uses RIGHT color, front & back use LEFT color
    --    If a physical left/right face uses LEFT  color, front & back use RIGHT color
    local literalRoles = { top="top", bottom="top" }
    if sidePair then
      literalRoles[sidePair.first] = "right"
      literalRoles[sidePair.second] = "left"
      local leftIsRight  = literalRoles.left  == "right"
      local rightIsRight = literalRoles.right == "right"
      local leftIsLeft   = literalRoles.left  == "left"
      local rightIsLeft  = literalRoles.right == "left"
      if leftIsRight or rightIsRight then
        literalRoles.front = "left"
        literalRoles.back  = "left"
      elseif leftIsLeft or rightIsLeft then
        literalRoles.front = "right"
        literalRoles.back  = "right"
      end
    end

    -- Also, for ALPHA Iso modules, map both top and bottom faces to "top" role.
    -- This ensures both topmost and bottommost facing faces use the TOP color.
    local alphaRoles = {}
    if isoSel and isoSel.isoFaces then
      local isoTop, isoLeft, isoRight = isoSel.isoFaces.top, isoSel.isoFaces.left, isoSel.isoFaces.right
      if isoTop then alphaRoles[isoTop] = "top" end
      if isoLeft then alphaRoles[isoLeft] = "left" end
      if isoRight then alphaRoles[isoRight] = "right" end
      -- Find the physical opposite of isoTop for the current frame (for all faces: top <-> bottom, left <-> right, front <-> back)
      local opposite = { top="bottom", bottom="top", left="right", right="left", front="back", back="front" }
      if isoTop and opposite[isoTop] then alphaRoles[opposite[isoTop]] = "top" end
    end

    params._frameIsoCache = {
      rotInfo=rotInfo,
      isoSelection=isoSel,
      sidePair=sidePair,
      literalRoles=literalRoles,
      alphaRoles=alphaRoles
    }
  end
  local cache = params._frameIsoCache
  local isoMap = cache.isoSelection.isoFaces

  -- Roles for alpha ISO modules (legacy brightness selection)
  -- Now: both "top" and its opposite are mapped to "top"
  local roleIsoAlpha = cache.alphaRoles and cache.alphaRoles[faceName] or nil
  -- Roles for literal ISO modules (from precomputed mapping + new rule)
  local roleIsoLiteral = cache.literalRoles and cache.literalRoles[faceName] or nil

  local working = {r=voxelColor.r,g=voxelColor.g,b=voxelColor.b,a=voxelColor.a}
  for _,mod in ipairs(stack) do
    local roleForModule
    if mod.shape=="Iso" then
      roleForModule = (mod.type=="literal") and roleIsoLiteral or roleIsoAlpha
    end
    working = applyModule(mod, faceName, roleForModule, working, voxelColor)
  end
  return working
end

return fxStack