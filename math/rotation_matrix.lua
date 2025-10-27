-- rotation_matrix.lua
-- High-level rotation matrix creation and manipulation
-- Requires: matrix, angles modules (loaded by loader.lua)

local rotation_matrix = {}

-- Create rotation matrix from Euler angles (in degrees)
-- This is the main function that creates co-dependent rotations
function rotation_matrix.createRotationMatrix(xDeg, yDeg, zDeg)
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
    -- Requires matrix.multiplyMatrices to be available
    local multiplyMatrices = _G.AseVoxel and _G.AseVoxel.math and _G.AseVoxel.math.matrix and _G.AseVoxel.math.matrix.multiplyMatrices
    if not multiplyMatrices then
        error("rotation_matrix requires matrix.multiplyMatrices to be loaded first")
    end
    
    local temp = multiplyMatrices(yMatrix, xMatrix)
    return multiplyMatrices(zMatrix, temp)
end

-- Extract Euler angles from rotation matrix (co-dependent extraction)
-- Requires angles.atan2 to be available
function rotation_matrix.matrixToEuler(m)
    local atan2 = _G.AseVoxel and _G.AseVoxel.math and _G.AseVoxel.math.angles and _G.AseVoxel.math.angles.atan2
    if not atan2 then
        error("rotation_matrix requires angles.atan2 to be loaded first")
    end
    
    -- Extract angles using proper mathematical extraction
    -- This ensures co-dependent behavior
    local sy = math.sqrt(m[1][1] * m[1][1] + m[2][1] * m[2][1])
    
    local singular = sy < 1e-6 -- Gimbal lock threshold
    
    local x, y, z
    
    if not singular then
        x = atan2(m[3][2], m[3][3])
        y = atan2(-m[3][1], sy)
        z = atan2(m[2][1], m[1][1])
    else
        x = atan2(-m[2][3], m[2][2])
        y = atan2(-m[3][1], sy)
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
function rotation_matrix.createRelativeRotationMatrix(pitchDelta, yawDelta, rollDelta)
    local multiplyMatrices = _G.AseVoxel and _G.AseVoxel.math and _G.AseVoxel.math.matrix and _G.AseVoxel.math.matrix.multiplyMatrices
    if not multiplyMatrices then
        error("rotation_matrix requires matrix.multiplyMatrices to be loaded first")
    end
    
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
    local temp = multiplyMatrices(pitchMatrix, yawMatrix)
    return multiplyMatrices(rollMatrix, temp)
end

-- Apply camera-relative rotation to existing model rotation
function rotation_matrix.applyRelativeRotation(currentMatrix, pitchDelta, yawDelta, rollDelta)
    local multiplyMatrices = _G.AseVoxel and _G.AseVoxel.math and _G.AseVoxel.math.matrix and _G.AseVoxel.math.matrix.multiplyMatrices
    if not multiplyMatrices then
        error("rotation_matrix requires matrix.multiplyMatrices to be loaded first")
    end
    
    local cameraRotation = rotation_matrix.createRelativeRotationMatrix(pitchDelta, yawDelta, rollDelta)
    
    -- Apply camera rotation BEFORE the current model orientation
    -- This ensures the rotation happens in camera space, not model space
    return multiplyMatrices(cameraRotation, currentMatrix)
end

-- Apply absolute rotation change to a specific axis while maintaining co-dependence
function rotation_matrix.setAxisRotation(currentMatrix, axis, newAngleDeg)
    -- Extract current Euler angles
    local currentEuler = rotation_matrix.matrixToEuler(currentMatrix)
    
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
    return rotation_matrix.createRotationMatrix(currentEuler.x, currentEuler.y, currentEuler.z)
end

return rotation_matrix
