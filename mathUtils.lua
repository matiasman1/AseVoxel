-- mathUtils.lua
local mathUtils = {}

--------------------------------------------------------------------------------
-- Custom math functions for compatibility
--------------------------------------------------------------------------------
-- Custom atan2 implementation for environments where math.atan2 is not available
function mathUtils.atan2(y, x)
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

--------------------------------------------------------------------------------
-- Matrix utility functions for 3D rotations
--------------------------------------------------------------------------------
-- Create identity matrix
function mathUtils.identity()
    return {
        {1, 0, 0},
        {0, 1, 0},
        {0, 0, 1}
    }
end

-- Matrix multiplication (3x3 matrices)
function mathUtils.multiplyMatrices(a, b)
    local result = { {0,0,0}, {0,0,0}, {0,0,0} }
    
    for i = 1, 3 do
        for j = 1, 3 do
            local sum = 0
            for k = 1, 3 do
                sum = sum + a[i][k] * b[k][j]
            end
            result[i][j] = sum
        end
    end
    
    return result
end

-- Create rotation matrix from Euler angles (in degrees)
-- This is the main function that creates co-dependent rotations
function mathUtils.createRotationMatrix(xDeg, yDeg, zDeg)
    -- Normalize angles to 0-359 range
    xDeg = (xDeg % 360 + 360) % 360
    yDeg = (yDeg % 360 + 360) % 360
    zDeg = (zDeg % 360 + 360) % 360
    
    -- Convert to radians
    local xRad = math.rad(xDeg)
    local yRad = math.rad(yDeg)
    local zRad = math.rad(zDeg)
    
    -- Calculate sines and cosines
    local cx, sx = math.cos(xRad), math.sin(xRad)
    local cy, sy = math.cos(yRad), math.sin(yRad)
    local cz, sz = math.cos(zRad), math.sin(zRad)
    
    -- Create individual rotation matrices
    local xMatrix = {
        {1, 0, 0},
        {0, cx, -sx},
        {0, sx, cx}
    }
    
    local yMatrix = {
        {cy, 0, sy},
        {0, 1, 0},
        {-sy, 0, cy}
    }
    
    local zMatrix = {
        {cz, -sz, 0},
        {sz, cz, 0},
        {0, 0, 1}
    }
    
    -- Combine rotations: Z * Y * X (this order creates co-dependent behavior)
    local temp = mathUtils.multiplyMatrices(yMatrix, xMatrix)
    return mathUtils.multiplyMatrices(zMatrix, temp)
end

-- Extract Euler angles from rotation matrix (co-dependent extraction)
function mathUtils.matrixToEuler(matrix)
    local m = matrix
    
    -- Extract angles using proper mathematical extraction
    -- This ensures co-dependent behavior
    local sy = math.sqrt(m[1][1] * m[1][1] + m[2][1] * m[2][1])
    
    local singular = sy < 1e-6 -- Gimbal lock threshold
    
    local x, y, z
    
    if not singular then
        x = mathUtils.atan2(m[3][2], m[3][3])
        y = mathUtils.atan2(-m[3][1], sy)
        z = mathUtils.atan2(m[2][1], m[1][1])
    else
        x = mathUtils.atan2(-m[2][3], m[2][2])
        y = mathUtils.atan2(-m[3][1], sy)
        z = 0
    end
    
    -- Convert to degrees and normalize
    x = math.deg(x)
    y = math.deg(y)
    z = math.deg(z)
    
    -- Normalize to [0, 360) range
    x = (x % 360 + 360) % 360
    y = (y % 360 + 360) % 360
    z = (z % 360 + 360) % 360
    
    return {x = x, y = y, z = z}
end

-- Create camera-relative rotation matrices
function mathUtils.createRelativeRotationMatrix(pitchDelta, yawDelta, rollDelta)
    -- Convert deltas to radians
    local pitchRad = math.rad(pitchDelta)
    local yawRad = math.rad(yawDelta)
    local rollRad = math.rad(rollDelta)
    
    -- Create rotation matrices for each camera-relative axis
    -- Pitch: rotation around the camera's right axis (X-axis in view space)
    local pitchMatrix = {
        {1, 0, 0},
        {0, math.cos(pitchRad), -math.sin(pitchRad)},
        {0, math.sin(pitchRad), math.cos(pitchRad)}
    }
    
    -- Yaw: rotation around the camera's up axis (Y-axis in view space)
    local yawMatrix = {
        {math.cos(yawRad), 0, math.sin(yawRad)},
        {0, 1, 0},
        {-math.sin(yawRad), 0, math.cos(yawRad)}
    }
    
    -- Roll: rotation around the camera's forward axis (Z-axis in view space)
    local rollMatrix = {
        {math.cos(rollRad), -math.sin(rollRad), 0},
        {math.sin(rollRad), math.cos(rollRad), 0},
        {0, 0, 1}
    }
    
    -- Apply in order: Yaw, then Pitch, then Roll (this feels most natural)
    local temp = mathUtils.multiplyMatrices(pitchMatrix, yawMatrix)
    return mathUtils.multiplyMatrices(rollMatrix, temp)
end

-- Apply camera-relative rotation to existing model rotation
function mathUtils.applyRelativeRotation(currentMatrix, pitchDelta, yawDelta, rollDelta)
    local cameraRotation = mathUtils.createRelativeRotationMatrix(pitchDelta, yawDelta, rollDelta)
    
    -- Apply camera rotation BEFORE the current model orientation
    -- This ensures the rotation happens in camera space, not model space
    return mathUtils.multiplyMatrices(cameraRotation, currentMatrix)
end

-- Apply absolute rotation change to a specific axis while maintaining co-dependence
function mathUtils.setAxisRotation(currentMatrix, axis, newAngleDeg)
    -- Extract current Euler angles
    local currentEuler = mathUtils.matrixToEuler(currentMatrix)
    
    -- Update the specified axis
    if axis == "x" then
        currentEuler.x = newAngleDeg
    elseif axis == "y" then
        currentEuler.y = newAngleDeg
    elseif axis == "z" then
        currentEuler.z = newAngleDeg
    end
    
    -- Create new matrix from updated Euler angles
    -- This automatically makes all axes co-dependent
    return mathUtils.createRotationMatrix(currentEuler.x, currentEuler.y, currentEuler.z)
end

-- Normalize an angle to the range [0, 360)
function mathUtils.normalizeAngle(angle)
    local normalized = (angle % 360 + 360) % 360
    
    -- Handle numerical precision issues at boundaries
    if math.abs(normalized - 360) < 0.001 then
        normalized = 0
    end
    
    return normalized
end

-- Check if a matrix is orthogonal (valid rotation matrix)
function mathUtils.isOrthogonal(matrix)
    -- Calculate determinant - should be close to 1
    local det = matrix[1][1] * (matrix[2][2] * matrix[3][3] - matrix[2][3] * matrix[3][2])
              - matrix[1][2] * (matrix[2][1] * matrix[3][3] - matrix[2][3] * matrix[3][1])
              + matrix[1][3] * (matrix[2][1] * matrix[3][2] - matrix[2][2] * matrix[3][1])
    
    return math.abs(det - 1.0) < 0.001
end

-- Convert mouse movement to trackball rotation
function mathUtils.mouseToTrackball(startX, startY, endX, endY, width, height)
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
function mathUtils.createAxisAngleMatrix(axisX, axisY, axisZ, angleDeg)
    local angleRad = math.rad(angleDeg)
    local c = math.cos(angleRad)
    local s = math.sin(angleRad)
    local t = 1 - c
    
    -- Normalize axis
    local length = math.sqrt(axisX * axisX + axisY * axisY + axisZ * axisZ)
    if length < 0.000001 then
        return mathUtils.identity()
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

-- Transpose a 3x3 matrix (used for rotation matrices)
function mathUtils.transposeMatrix(matrix)
  return {
    {matrix[1][1], matrix[2][1], matrix[3][1]},
    {matrix[1][2], matrix[2][2], matrix[3][2]},
    {matrix[1][3], matrix[2][3], matrix[3][3]}
  }
end

return mathUtils
