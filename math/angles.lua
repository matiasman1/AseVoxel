-- angles.lua
-- Angle utilities and normalization

local angles = {}

--------------------------------------------------------------------------------
-- Custom atan2 implementation for compatibility
--------------------------------------------------------------------------------
-- Custom atan2 implementation for environments where math.atan2 is not available
function angles.atan2(y, x)
    -- Check if built-in atan2 is available
    if math.atan2 then
        return math.atan2(y, x)
    end
    
    -- Custom implementation
    if x > 0 then
        return math.atan(y / x)
    elseif x < 0 and y >= 0 then
        return math.atan(y / x) + math.pi
    elseif x < 0 and y < 0 then
        return math.atan(y / x) - math.pi
    elseif x == 0 and y > 0 then
        return math.pi / 2
    elseif x == 0 and y < 0 then
        return -math.pi / 2
    else -- x == 0 and y == 0
        return 0  -- Undefined, but return 0 as a convention
    end
end

-- Normalize an angle to the range [0, 360)
function angles.normalizeAngle(angle)
    local normalized = (angle % 360 + 360) % 360
    
    -- Handle numerical precision issues at boundaries
    if math.abs(normalized - 360) < 0.001 then
        normalized = 0
    end
    
    return normalized
end

-- Helper function to wrap an angle into [-180, +180] degree range
-- Used to find the smallest rotation path between two angles
function angles.wrapAngle(angle)
  local wrapped = angle % 360
  if wrapped > 180 then 
    wrapped = wrapped - 360
  end
  return wrapped
end

return angles
