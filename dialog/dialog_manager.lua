-- dialog_manager.lua
-- Core dialog state management and coordination

local dialogManager = {}

-- Lazy loaders for dependencies
local function getMathUtils()
  return {
    identity = function()
      return AseVoxel.math.matrix.identity()
    end
  }
end

-- Current state to keep track of controls across dialogs
dialogManager.controlsDialog = nil
dialogManager.exportDialog = nil
dialogManager.mainDialog = nil
dialogManager.previewDialog = nil

-- Store the current rotation matrix globally for co-dependent behavior
-- Initialize with identity matrix
dialogManager.currentRotationMatrix = nil

-- Add a flag to prevent recursive updates
dialogManager.isUpdatingControls = false

-- Add a global update lock with timestamp to prevent UI cascades
dialogManager.updateLock = false
dialogManager.lastUpdateTime = 0
dialogManager.updateThrottleMs = 0 -- let viewerCore handle mouse throttling

-- Initialize rotation matrix on first access
function dialogManager.getCurrentRotationMatrix()
  if not dialogManager.currentRotationMatrix then
    local mathUtils = getMathUtils()
    dialogManager.currentRotationMatrix = mathUtils.identity()
  end
  return dialogManager.currentRotationMatrix
end

-- Safe update function that prevents recursive calls and throttles updates
function dialogManager.safeUpdate(viewParams, updateCallback)
  local currentTime = os.clock() * 1000
  if dialogManager.updateLock or 
     (currentTime - dialogManager.lastUpdateTime) < dialogManager.updateThrottleMs then
    return
  end
  dialogManager.updateLock = true
  dialogManager.lastUpdateTime = currentTime
  pcall(function()
    updateCallback(viewParams)
  end)
  dialogManager.updateLock = false
end

-- Delegate to controls_dialog module
function dialogManager.openControlsDialog(parentDlg, viewParams, updateCallback)
  local controlsDialog = AseVoxel.dialog.controls_dialog
  if controlsDialog and controlsDialog.openControlsDialog then
    return controlsDialog.openControlsDialog(parentDlg, viewParams, updateCallback)
  else
    print("[dialog_manager] ERROR: controls_dialog module not loaded")
    return nil
  end
end

-- Delegate to export_dialog module
function dialogManager.openExportDialog(voxelModel)
  local exportDialog = AseVoxel.dialog.export_dialog
  if exportDialog and exportDialog.show then
    return exportDialog.show(app.activeSprite, { voxelModel = voxelModel })
  else
    print("[dialog_manager] ERROR: export_dialog module not loaded")
    return nil
  end
end

-- Delegate to animation_dialog module
function dialogManager.openAnimationDialog(viewParams, voxelModel, modelDimensions)
  local animationDialog = AseVoxel.dialog.animation_dialog
  if animationDialog and animationDialog.open then
    return animationDialog.open(viewParams, voxelModel, modelDimensions)
  else
    print("[dialog_manager] ERROR: animation_dialog module not loaded")
    return nil
  end
end

return dialogManager
