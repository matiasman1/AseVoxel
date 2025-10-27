-- trackball.lua
-- Mouse-to-rotation conversion using trackball metaphor
-- Requires: matrix, angles modules (loaded by loader.lua)

local trackball = {}

-- Convert mouse movement to trackball rotation
function trackball.mouseToTrackball(startX, startY, endX, endY, width, height)
    -- Convert to normalized coordinates [-1, 1]
    local function project(x, y)
        local nx = (2.0 * x / width) - 1.0
        local ny = 1.0 - (2.0 * y / height)
        local length = math.sqrt(nx * nx + ny * ny)
        
        -- Project onto sphere or hyperbolic sheet
        local nz
        if length < 0.7071 then -- sqrt(2)/2
            nz = math.sqrt(1.0 - length * length)
        else
            nz = 0.5 / length
        end
        
        return nx, ny, nz
    end
    
    local p1x, p1y, p1z = project(startX, startY)
    local p2x, p2y, p2z = project(endX, endY)
    
    -- Calculate rotation axis (cross product)
    local axisX = p1y * p2z - p1z * p2y
    local axisY = p1z * p2x - p1x * p2z
    local axisZ = p1x * p2y - p1y * p2x
    
    -- Calculate rotation angle (dot product)
    local dot = p1x * p2x + p1y * p2y + p1z * p2z
    local angle = math.acos(math.max(-1.0, math.min(1.0, dot)))
    
    return axisX, axisY, axisZ, math.deg(angle)
end

-- Create rotation matrix from axis-angle representation
-- Requires matrix module to be loaded
function trackball.createAxisAngleMatrix(axisX, axisY, axisZ, angleDeg)
    local angleRad = math.rad(angleDeg)
    local c = math.cos(angleRad)
    local s = math.sin(angleRad)
    local t = 1 - c
    
    -- Normalize axis
    local length = math.sqrt(axisX * axisX + axisY * axisY + axisZ * axisZ)
    if length < 0.000001 then
        -- Return identity if axis is zero
        return {
            {1, 0, 0},
            {0, 1, 0},
            {0, 0, 1}
        }
    end
    
    axisX = axisX / length
    axisY = axisY / length
    axisZ = axisZ / length
    
    -- Rodrigues' rotation formula in matrix form
    return {
        {t*axisX*axisX + c,      t*axisX*axisY - s*axisZ, t*axisX*axisZ + s*axisY},
        {t*axisX*axisY + s*axisZ, t*axisY*axisY + c,      t*axisY*axisZ - s*axisX},
        {t*axisX*axisZ - s*axisY, t*axisY*axisZ + s*axisX, t*axisZ*axisZ + c}
    }
end

return trackball
