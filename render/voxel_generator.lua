-- voxel_generator.lua
-- Generates voxel models from Aseprite sprite layers
-- Supports layer scrolling mode for focused layer viewing

local voxelGenerator = {}

-- Layer scrolling state
voxelGenerator.layerScrollMode = {
  enabled = false,
  focusIndex = 1,
  behind = 0,
  front = 0,
  layerList = {},
  cache = {},
  spriteId = nil,
  originalVisibility = {}
}

local function _activeFrameNumber()
  return (app.activeFrame and app.activeFrame.frameNumber) or 1
end

local function _rebuildLayerList(sprite)
  local ls = {}
  for _, layer in ipairs(sprite.layers) do
    if not layer.isGroup then ls[#ls+1] = layer end
  end
  voxelGenerator.layerScrollMode.layerList = ls
end

local function _cloneCelImage(cel)
  if not cel or not cel.image then return nil end
  local ok, clone = pcall(function() return cel.image:clone() end)
  return ok and clone or nil
end

local function _refreshCacheForRange(sprite, startIdx, endIdx, frame)
  local mode = voxelGenerator.layerScrollMode
  for i = startIdx, endIdx do
    local layer = mode.layerList[i]
    local cel = layer and layer:cel(frame)
    local img = _cloneCelImage(cel)
    if img then
      mode.cache[i] = {
        image = img,
        pos = { x = cel.position.x, y = cel.position.y },
        layer = layer,
        frame = frame
      }
    end
  end
end

function voxelGenerator.enableLayerScrollMode(enable, sprite, focusIndex)
  local mode = voxelGenerator.layerScrollMode
  if enable == mode.enabled then return end
  if enable then
    if not sprite then return end
    _rebuildLayerList(sprite)
    if #mode.layerList == 0 then return end
    local idx = focusIndex
    if not idx and app.activeLayer then
      for i,l in ipairs(mode.layerList) do
        if l == app.activeLayer then idx = i break end
      end
    end
    idx = idx or 1
    idx = math.max(1, math.min(#mode.layerList, idx))
    mode.focusIndex = idx
    mode.originalVisibility = {}
    for _, l in ipairs(mode.layerList) do
      mode.originalVisibility[l] = l.isVisible
      l.isVisible = false
    end
    mode.layerList[idx].isVisible = true
    mode.spriteId = sprite
    mode.cache = {}
    mode.enabled = true
    _refreshCacheForRange(sprite, idx, idx, _activeFrameNumber())
  else
    if mode.originalVisibility then
      for layer, vis in pairs(mode.originalVisibility) do
        pcall(function() layer.isVisible = vis end)
      end
    end
    mode.enabled = false
    mode.originalVisibility = nil
    mode.cache = {}
    mode.layerList = {}
    mode.spriteId = nil
  end
end

function voxelGenerator.setLayerScrollWindow(behind, front)
  local m = voxelGenerator.layerScrollMode
  m.behind = math.max(0, tonumber(behind) or 0)
  m.front  = math.max(0, tonumber(front) or 0)
end

function voxelGenerator.shiftLayerFocus(delta, sprite)
  local m = voxelGenerator.layerScrollMode
  if not m.enabled then return end
  if sprite ~= m.spriteId then
    voxelGenerator.enableLayerScrollMode(false)
    return
  end
  if #m.layerList == 0 then _rebuildLayerList(sprite) end
  local newIndex = m.focusIndex + delta
  if newIndex < 1 or newIndex > #m.layerList then return end
  local oldLayer = m.layerList[m.focusIndex]
  local newLayer = m.layerList[newIndex]
  if oldLayer then oldLayer.isVisible = false end
  if newLayer then newLayer.isVisible = true end
  m.focusIndex = newIndex
  _refreshCacheForRange(sprite, newIndex, newIndex, _activeFrameNumber())
end

function voxelGenerator.getLayerScrollState()
  local m = voxelGenerator.layerScrollMode
  return {
    enabled = m.enabled,
    focusIndex = m.focusIndex,
    behind = m.behind,
    front = m.front,
    total = #m.layerList
  }
end

--------------------------------------------------------------------------------
-- Voxel Model Generation
--------------------------------------------------------------------------------
function voxelGenerator.generateVoxelModel(sprite)
  if not sprite then return {} end
  local mode = voxelGenerator.layerScrollMode
  if mode.enabled and mode.spriteId ~= sprite then
    voxelGenerator.enableLayerScrollMode(false)
  end

  -- Layer Scroll Mode path
  if mode.enabled then
    local flatCount = 0
    for _, layer in ipairs(sprite.layers) do
      if not layer.isGroup then flatCount = flatCount + 1 end
    end
    if flatCount ~= #mode.layerList then
      _rebuildLayerList(sprite)
      mode.focusIndex = math.min(mode.focusIndex, #mode.layerList)
    end
    if #mode.layerList == 0 then return {} end
    mode.focusIndex = math.min(math.max(1, mode.focusIndex), #mode.layerList)

    local startIdx = math.max(1, mode.focusIndex - mode.behind)
    local endIdx   = math.min(#mode.layerList, mode.focusIndex + mode.front)
    local frame = _activeFrameNumber()
    _refreshCacheForRange(sprite, startIdx, endIdx, frame)

    local model = {}
    local zCounter = 0
    for i = startIdx, endIdx do
      zCounter = zCounter + 1
      local entry = mode.cache[i]
      if entry and entry.image then
        local img = entry.image
        for y = 0, img.height - 1 do
          for x = 0, img.width - 1 do
            local px = img:getPixel(x, y)
            local a = app.pixelColor.rgbaA(px)
            if a > 0 then
              model[#model+1] = {
                x = x + entry.pos.x,
                y = y + entry.pos.y,
                z = zCounter,
                color = {
                  r = app.pixelColor.rgbaR(px),
                  g = app.pixelColor.rgbaG(px),
                  b = app.pixelColor.rgbaB(px),
                  a = a
                }
              }
            end
          end
        end
      end
    end
    return model
  end

  -- Standard path
  local model = {}
  local visibleLayers = {}
  for _, layer in ipairs(sprite.layers) do
    if not layer.isGroup and layer.isVisible then
      visibleLayers[#visibleLayers+1] = layer
    end
  end
  local frameIndex = _activeFrameNumber()
  for i, layer in ipairs(visibleLayers) do
    local z = i
    local cel = layer:cel(frameIndex)
    if cel and cel.image then
      local image = cel.image
      for y = 0, image.height - 1 do
        for x = 0, image.width - 1 do
          local px = image:getPixel(x, y)
            if app.pixelColor.rgbaA(px) > 0 then
            model[#model+1] = {
              x = x + cel.position.x,
              y = y + cel.position.y,
              z = z,
              color = {
                r = app.pixelColor.rgbaR(px),
                g = app.pixelColor.rgbaG(px),
                b = app.pixelColor.rgbaB(px),
                a = app.pixelColor.rgbaA(px)
              }
            }
          end
        end
      end
    end
  end
  return model
end

function voxelGenerator.calculateModelBounds(model)
  if #model == 0 then
    return {minX=0, maxX=0, minY=0, maxY=0, minZ=0, maxZ=0}
  end
  local minX, maxX = model[1].x, model[1].x
  local minY, maxY = model[1].y, model[1].y
  local minZ, maxZ = model[1].z, model[1].z
  for _, v in ipairs(model) do
    if v.x < minX then minX = v.x end
    if v.x > maxX then maxX = v.x end
    if v.y < minY then minY = v.y end
    if v.y > maxY then maxY = v.y end
    if v.z < minZ then minZ = v.z end
    if v.z > maxZ then maxZ = v.z end
  end
  return {
    minX=minX, maxX=maxX,
    minY=minY, maxY=maxY,
    minZ=minZ, maxZ=maxZ
  }
end

function voxelGenerator.calculateMiddlePoint(model)
  local bounds = voxelGenerator.calculateModelBounds(model)
  return {
    x = (bounds.minX + bounds.maxX) / 2,
    y = (bounds.minY + bounds.maxY) / 2,
    z = (bounds.minZ + bounds.maxZ) / 2,
    sizeX = bounds.maxX - bounds.minX + 1,
    sizeY = bounds.maxY - bounds.minY + 1,
    sizeZ = bounds.maxZ - bounds.minZ + 1
  }
end

return voxelGenerator
