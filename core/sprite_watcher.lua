-- sprite_watcher.lua
-- Listens to Aseprite events and triggers live preview/model updates.
-- Dependencies: Loaded via AseVoxel.core namespace

local spriteWatcher = {}

-- Access dependencies through global namespace (loaded by loader.lua)
local function getViewerCore()
  return AseVoxel.core.preview_manager
end

local function getDialogueManager()
  return AseVoxel.dialog.dialog_common
end

-- Keep reference so we can disconnect if needed
spriteWatcher._connections = {}

-- Helper to safely trigger a preview refresh using existing viewParams
local function refresh(viewParams)
  if not viewParams then return end
  local viewerCore = getViewerCore()
  local dialogueManager = getDialogueManager()
  if not viewerCore or not dialogueManager then return end
  
  -- Reuse current rotation matrix & other params; viewerCore.updatePreview rebuilds model
  viewerCore.requestPreview(
    dialogueManager.previewDialog or dialogueManager.mainDialog,
    viewParams,
    dialogueManager.controlsDialog,
    "spritechange"
  )
end

-- Register a generic handler for any event in events list
local function hook(appEvents, eventName, handler)
  local ok, conn = pcall(function()
    return appEvents:on(eventName, handler)
  end)
  if ok and conn then
    spriteWatcher._connections[#spriteWatcher._connections+1] = conn
  end
end

-- Public API
function spriteWatcher.start(viewParams)
  spriteWatcher.stop() -- clear previous
  local events = app.events
  if not events then
    print("[spriteWatcher] app.events not available in this Aseprite build.")
    return
  end

  local function handler(ev)
    -- We could filter by ev.sprite == app.activeSprite if desired
    refresh(viewParams)
  end

  -- Broad set of events that can affect pixels or structure:
  local names = {
    "change",          -- generic (palette, selection, etc.)
    "sitechange",      -- layer/frame changes
    "spritechange",    -- structural sprite modifications
    "celchange",       -- cel edits
    "layerchange",     -- layer edits
    "framechange",     -- frame count or selection changes
    "palettechange",   -- palette modifications
    "selectionchange", -- selection modifications (in case you shade selection)
    "tagchange",
    "userdatachange",
    "tilesetchange"    -- if using tilesets
  }
  for _,n in ipairs(names) do
    hook(events, n, handler)
  end
  print("[spriteWatcher] Live preview hooks installed.")
end

function spriteWatcher.stop()
  if not spriteWatcher._connections then return end
  for _,conn in ipairs(spriteWatcher._connections) do
    pcall(function() if conn.close then conn:close() end end)
  end
  spriteWatcher._connections = {}
end

return spriteWatcher