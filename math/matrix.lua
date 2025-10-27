-- matrix.lua
-- Matrix operations for 3D rotations

local matrix = {}

--------------------------------------------------------------------------------
-- Matrix utility functions for 3D rotations
--------------------------------------------------------------------------------
-- Create identity matrix
function matrix.identity()
    return {
        {1, 0, 0},
        {0, 1, 0},
        {0, 0, 1}
    }
end

-- Matrix multiplication (3x3 matrices)
function matrix.multiplyMatrices(a, b)
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

-- Transpose a 3x3 matrix (used for rotation matrices)
function matrix.transposeMatrix(m)
  return {
    {m[1][1], m[2][1], m[3][1]},
    {m[1][2], m[2][2], m[3][2]},
    {m[1][3], m[2][3], m[3][3]}
  }
end

-- Check if a matrix is orthogonal (valid rotation matrix)
function matrix.isOrthogonal(m)
    -- Calculate determinant - should be close to 1
    local det = m[1][1] * (m[2][2] * m[3][3] - m[2][3] * m[3][2])
              - m[1][2] * (m[2][1] * m[3][3] - m[2][3] * m[3][1])
              + m[1][3] * (m[2][1] * m[3][2] - m[2][2] * m[3][1])
    
    return math.abs(det - 1.0) < 0.001
end

return matrix
