-- file_common.lua
-- Common file utilities and path operations

local fileCommon = {}

-- Leverage app.fs for path manipulation
fileCommon.joinPath = function(...)
  return app.fs.joinPath(...)
end

fileCommon.getFileExtension = function(path)
  return app.fs.fileExtension(path)
end

fileCommon.getFileName = function(path)
  return app.fs.fileName(path)
end

fileCommon.getFileTitle = function(path)
  return app.fs.fileTitle(path)
end

fileCommon.getDirectory = function(path)
  return app.fs.filePath(path)
end

-- Directory operations
fileCommon.isDirectory = function(path)
  return app.fs.isDirectory(path)
end

fileCommon.isFile = function(path)
  return app.fs.isFile(path)
end

fileCommon.listFiles = function(path)
  return app.fs.listFiles(path)
end

fileCommon.createDirectory = function(path)
  return app.fs.makeDirectory(path)
end

fileCommon.createDirectories = function(path)
  return app.fs.makeAllDirectories(path)
end

--------------------------------------------------------------------------------
-- Generic export dispatcher
--------------------------------------------------------------------------------
function fileCommon.exportGeneric(voxels, filePath, options)
  options = options or {}
  
  -- Default options
  local scaleModel = options.scaleModel or 1.0
  local format = options.format or app.fs.fileExtension(filePath):lower()
  
  -- Ensure file has the correct extension
  if not filePath:lower():match("%." .. format .. "$") then
    filePath = filePath .. "." .. format
  end
  
  if format == "obj" then
    -- For OBJ format, use the exportOBJ module
    local exportOBJ = AseVoxel.io.export_obj
    return exportOBJ.export(voxels, filePath, options)
  elseif format == "ply" then
    local exportPLY = AseVoxel.io.export_ply
    return exportPLY.export(voxels, filePath, options)
  elseif format == "stl" then
    local exportSTL = AseVoxel.io.export_stl
    return exportSTL.export(voxels, filePath, options)
  else
    -- Unsupported format - try obj as fallback
    app.alert("Unsupported export format '" .. format .. "'. Using OBJ format instead.")
    local exportOBJ = AseVoxel.io.export_obj
    return exportOBJ.export(voxels, filePath:gsub("%.[^%.]+$", ".obj"), options)
  end
end

return fileCommon
