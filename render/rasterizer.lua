-- rasterizer.lua
-- Low-level drawing primitives for polygon fill

local rasterizer = {}

--------------------------------------------------------------------------------
-- Point-in-polygon test
--------------------------------------------------------------------------------
function rasterizer.isPointInPolygon(x, y, polygon)
  local inside = false
  local j = #polygon
  for i = 1, #polygon do
    local pi, pj = polygon[i], polygon[j]
    if ((pi.y > y) ~= (pj.y > y)) and
       (x < (pj.x - pi.x) * (y - pi.y) / (pj.y - pi.y) + pi.x) then
      inside = not inside
    end
    j = i
  end
  return inside
end

--------------------------------------------------------------------------------
-- Convex quad rasterizer (fractional scale fix)
-- Replacement polygon rasterizer for voxel faces
-- Issues addressed:
--  1. Previous implementation rounded vertex positions early -> gaps at fractional voxelSize.
--  2. Even/odd test with strict < caused right/top edge drop-out (missing pixel corners).
--  3. Rounding before fill produced "chipped" top-right corners.
-- New approach: scanline fill of convex quad using float vertices, half-open rule on Y, inclusive X.
--------------------------------------------------------------------------------
local function drawConvexQuad(image, pts, color)
  if #pts ~= 4 then
    -- Fallback: simple edge plot (rare path)
    for i=1,#pts do
      local a = pts[i]
      local b = pts[(i % #pts)+1]
      local x0,y0,x1,y1 = a.x,a.y,b.x,b.y
      local dx = math.abs(x1-x0)
      local dy = math.abs(y1-y0)
      local steps = math.max(dx,dy)
      if steps < 1 then steps = 1 end
      for s=0,steps do
        local t = s/steps
        local px = x0 + (x1-x0)*t
        local py = y0 + (y1-y0)*t
        local ix = math.floor(px+0.5)
        local iy = math.floor(py+0.5)
        if ix>=0 and ix<image.width and iy>=0 and iy<image.height then
          image:putPixel(ix,iy,color)
        end
      end
    end
    return
  end

  local minY, maxY = math.huge, -math.huge
  for _,p in ipairs(pts) do
    if p.y < minY then minY = p.y end
    if p.y > maxY then maxY = p.y end
  end
  minY = math.max(0, math.floor(minY))
  maxY = math.min(image.height-1, math.ceil(maxY))

  local edges = {}
  for i=1,4 do
    local a = pts[i]
    local b = pts[(i % 4)+1]
    if a.y ~= b.y then
      if a.y < b.y then
        edges[#edges+1] = { y0=a.y, y1=b.y, x0=a.x, x1=b.x }
      else
        edges[#edges+1] = { y0=b.y, y1=a.y, x0=b.x, x1=a.x }
      end
    end
  end

  for y = minY, maxY do
    local scanY = y + 0.5
    local xInts = {}
    for _,e in ipairs(edges) do
      if scanY >= e.y0 and scanY < e.y1 then
        local t = (scanY - e.y0) / (e.y1 - e.y0)
        local x = e.x0 + (e.x1 - e.x0) * t
        xInts[#xInts+1] = x
      end
    end
    if #xInts >= 2 then
      table.sort(xInts)
      for k=1,#xInts,2 do
        local x0 = xInts[k]
        local x1 = xInts[k+1] or x0
        if x1 < x0 then x0,x1 = x1,x0 end
        local startX = math.max(0, math.floor(x0 + 0.5))
        local endX   = math.min(image.width-1, math.floor(x1 - 0.5))
        if endX < startX and (math.abs(x1 - x0) < 1.0) then endX = startX end
        for xPix = startX, endX do
          image:putPixel(xPix, y, color)
        end
      end
    end
  end
end

--------------------------------------------------------------------------------
-- Public polygon drawing function
--------------------------------------------------------------------------------
function rasterizer.drawPolygon(image, points, color, method, size)
  drawConvexQuad(image, points, color)
end

return rasterizer
