-- loader.lua
-- Central module loader for AseVoxel refactored structure
-- Uses dofile() to avoid Lua package.path issues with subfol ders
-- Establishes module dependencies and avoids circular references

-- Discover base path using debug.getinfo
local scriptInfo = debug.getinfo(1, "S")
local scriptSource = scriptInfo.source
if scriptSource:sub(1, 1) == "@" then
  scriptSource = scriptSource:sub(2)
end
local basePath = scriptSource:match("^(.+[/\\])[^/\\]+$") or "./"
local sep = app.fs.pathSeparator

-- Module cache to prevent double-loading (mimics require() behavior)
local _loadedModules = {}
local _loadStats = { hits = 0, misses = 0 }

-- Helper function to load a module file using dofile with caching
-- This provides require()-like semantics in Aseprite's sandboxed environment:
--   1. First call: dofile() executes the file and caches the result
--   2. Subsequent calls: return cached module (no re-execution)
local function loadModule(relativePath)
  local fullPath = basePath .. relativePath .. ".lua"
  
  -- Return cached module if already loaded (fast path)
  if _loadedModules[fullPath] then
    _loadStats.hits = _loadStats.hits + 1
    return _loadedModules[fullPath]
  end
  
  -- Load and cache the module (slow path - only happens once per file)
  _loadStats.misses = _loadStats.misses + 1
  local module = dofile(fullPath)
  _loadedModules[fullPath] = module
  return module
end

-- Expose cache stats for debugging
AseVoxel = {
  _loaderStats = function() 
    return {
      modulesLoaded = _loadStats.misses,
      cacheHits = _loadStats.hits,
      totalCalls = _loadStats.hits + _loadStats.misses
    }
  end
}

-- Initialize module namespace structure
AseVoxel.math = {}
AseVoxel.render = {}
AseVoxel.dialog = {}
AseVoxel.utils = {}
AseVoxel.io = {}
AseVoxel.core = {}

-- Make it global for cross-module access
_G.AseVoxel = AseVoxel

print("[AseVoxel] Loading modular extension...")

--------------------------------------------------------------------------------
-- Layer 0: Pure Utilities (No Dependencies)
--------------------------------------------------------------------------------
print("[AseVoxel] Loading Layer 0: Pure Utilities...")

-- Math utilities
AseVoxel.math.matrix = loadModule("math" .. sep .. "matrix")
AseVoxel.math.angles = loadModule("math" .. sep .. "angles")

print("[AseVoxel] Layer 0 complete: matrix, angles")

--------------------------------------------------------------------------------
-- Layer 1: Basic Operations (Layer 0 only)
--------------------------------------------------------------------------------
print("[AseVoxel] Loading Layer 1: Basic Operations...")

-- Now we can load modules that depend on Layer 0
-- For rotation_matrix.lua, we need to pass dependencies
-- Let me revise the approach: each module will access AseVoxel global when needed

AseVoxel.math.trackball = loadModule("math" .. sep .. "trackball")
AseVoxel.math.rotation_matrix = loadModule("math" .. sep .. "rotation_matrix")

-- Load rotation.lua (the original rotation operations)
AseVoxel.math.rotation = loadModule("math" .. sep .. "rotation")

print("[AseVoxel] Layer 1 complete: trackball, rotation_matrix, rotation")

--------------------------------------------------------------------------------
-- Layer 2: Rendering Core  
--------------------------------------------------------------------------------
print("[AseVoxel] Loading Layer 2: Rendering Core...")

-- Standalone render modules (no dependencies or minimal)
AseVoxel.render.native_bridge = loadModule("render" .. sep .. "native_bridge")
AseVoxel.render.remote_renderer = loadModule("render" .. sep .. "remote_renderer")
AseVoxel.render.fx_stack = loadModule("render" .. sep .. "fx_stack")
AseVoxel.render.mesh_builder = loadModule("render" .. sep .. "mesh_builder")
AseVoxel.render.mesh_renderer = loadModule("render" .. sep .. "mesh_renderer")

-- Rendering sub-modules (split from previewRenderer)
AseVoxel.render.face_visibility = loadModule("render" .. sep .. "face_visibility")
AseVoxel.render.fast_visibility = loadModule("render" .. sep .. "fast_visibility")
AseVoxel.render.vertex_cache = loadModule("render" .. sep .. "vertex_cache")
AseVoxel.render.rasterizer = loadModule("render" .. sep .. "rasterizer")
AseVoxel.render.shading = loadModule("render" .. sep .. "shading")
AseVoxel.render.mesh_pipeline = loadModule("render" .. sep .. "mesh_pipeline")
AseVoxel.render.geometry_pipeline = loadModule("render" .. sep .. "geometry_pipeline")
AseVoxel.render.canvas_renderer = loadModule("render" .. sep .. "canvas_renderer")

-- Shader stack system (NEW)
AseVoxel.render.shader_interface = loadModule("render" .. sep .. "shader_interface")
AseVoxel.render.shader_stack = loadModule("render" .. sep .. "shader_stack")
AseVoxel.render.shader_ui = loadModule("render" .. sep .. "shader_ui")

-- Main preview renderer coordination module
AseVoxel.render.preview_renderer = loadModule("render" .. sep .. "preview_renderer")

print("[AseVoxel] Layer 2 complete: rendering modules + shader stack")

--------------------------------------------------------------------------------
-- Layer 3: File I/O
--------------------------------------------------------------------------------
print("[AseVoxel] Loading Layer 3: File I/O...")

AseVoxel.io.file_common = loadModule("io" .. sep .. "file_common")
AseVoxel.io.export_obj = loadModule("io" .. sep .. "export_obj")
AseVoxel.io.export_ply = loadModule("io" .. sep .. "export_ply")
AseVoxel.io.export_stl = loadModule("io" .. sep .. "export_stl")

-- Add voxel_generator to render namespace
AseVoxel.render.voxel_generator = loadModule("render" .. sep .. "voxel_generator")

print("[AseVoxel] Layer 3 complete: file I/O and voxel generation")

--------------------------------------------------------------------------------
-- Layer 4: Core Application Logic
--------------------------------------------------------------------------------
print("[AseVoxel] Loading Layer 4: Core Logic...")

AseVoxel.core.sprite_watcher = loadModule("core" .. sep .. "sprite_watcher")
AseVoxel.core.preview_manager = loadModule("core" .. sep .. "preview_manager")
AseVoxel.core.viewer_core = loadModule("core" .. sep .. "viewer_core")
AseVoxel.core.viewer_state = loadModule("core" .. sep .. "viewer_state")

print("[AseVoxel] Layer 4 complete: core application logic")

--------------------------------------------------------------------------------
-- Layer 5: Utilities
--------------------------------------------------------------------------------
print("[AseVoxel] Loading Layer 5: Utilities...")

-- Note: image_utils.lua doesn't exist in original codebase, skipping
AseVoxel.utils.preview_utils = loadModule("utils" .. sep .. "preview_utils")
AseVoxel.utils.dialog_utils = loadModule("utils" .. sep .. "dialog_utils")
AseVoxel.utils.performance_profiler = loadModule("utils" .. sep .. "performance_profiler")

print("[AseVoxel] Layer 5 complete: utilities")

--------------------------------------------------------------------------------
-- Layer 6: UI Dialogs
--------------------------------------------------------------------------------
print("[AseVoxel] Loading Layer 6: UI Dialogs...")

-- Core dialog manager (state and coordination)
AseVoxel.dialog.dialog_manager = loadModule("dialog" .. sep .. "dialog_manager")

-- Individual dialog modules
AseVoxel.dialog.controls_dialog = loadModule("dialog" .. sep .. "controls_dialog")
AseVoxel.dialog.export_dialog = loadModule("dialog" .. sep .. "export_dialog")
AseVoxel.dialog.fx_stack_dialog = loadModule("dialog" .. sep .. "fx_stack_dialog")
AseVoxel.dialog.help_dialog = loadModule("dialog" .. sep .. "help_dialog")
AseVoxel.dialog.animation_dialog = loadModule("dialog" .. sep .. "animation_dialog")
AseVoxel.dialog.outline_dialog = loadModule("dialog" .. sep .. "outline_dialog")
AseVoxel.dialog.main_dialog = loadModule("dialog" .. sep .. "main_dialog")
AseVoxel.dialog.preview_dialog = loadModule("dialog" .. sep .. "preview_dialog")

-- Core viewer orchestration (depends on all dialogs)
AseVoxel.core.viewer = loadModule("core" .. sep .. "viewer")

print("[AseVoxel] Layer 6 complete: UI dialogs")

--------------------------------------------------------------------------------
-- Expose top-level API
--------------------------------------------------------------------------------

-- Make commonly used modules easily accessible
print("[AseVoxel] Layer 6 complete: UI dialogs")

--------------------------------------------------------------------------------
-- Expose top-level API
--------------------------------------------------------------------------------

-- Create convenience namespaces for modules
AseVoxel.rotation = AseVoxel.math.rotation
AseVoxel.fxStack = AseVoxel.render.fx_stack
AseVoxel.shaderStack = AseVoxel.render.shader_stack
AseVoxel.shaderUI = AseVoxel.render.shader_ui
AseVoxel.meshBuilder = AseVoxel.render.mesh_builder
AseVoxel.meshRenderer = AseVoxel.render.mesh_renderer
AseVoxel.meshPipeline = AseVoxel.render.mesh_pipeline
AseVoxel.nativeBridge = AseVoxel.render.native_bridge
AseVoxel.remoteRenderer = AseVoxel.render.remote_renderer
AseVoxel.voxelGenerator = AseVoxel.render.voxel_generator
AseVoxel.previewRenderer = AseVoxel.render.preview_renderer
AseVoxel.spriteWatcher = AseVoxel.core.sprite_watcher
AseVoxel.previewManager = AseVoxel.core.preview_manager
AseVoxel.viewerCore = AseVoxel.core.viewer_core
AseVoxel.viewerState = AseVoxel.core.viewer_state
AseVoxel.previewUtils = AseVoxel.utils.preview_utils
AseVoxel.dialogUtils = AseVoxel.utils.dialog_utils

-- Dialog modules
AseVoxel.dialogManager = AseVoxel.dialog.dialog_manager
AseVoxel.exportDialog = AseVoxel.dialog.export_dialog
AseVoxel.fxStackDialog = AseVoxel.dialog.fx_stack_dialog
AseVoxel.helpDialog = AseVoxel.dialog.help_dialog
AseVoxel.animationDialog = AseVoxel.dialog.animation_dialog
AseVoxel.outlineDialog = AseVoxel.dialog.outline_dialog
AseVoxel.mainDialog = AseVoxel.dialog.main_dialog
AseVoxel.previewDialog = AseVoxel.dialog.preview_dialog
AseVoxel.viewer = AseVoxel.core.viewer

-- I/O modules
AseVoxel.fileUtils = AseVoxel.io.file_common
AseVoxel.exportOBJ = AseVoxel.io.export_obj
AseVoxel.exportPLY = AseVoxel.io.export_ply
AseVoxel.exportSTL = AseVoxel.io.export_stl

-- Create convenience mathUtils-style namespace for compatibility
AseVoxel.mathUtils = {
  identity = AseVoxel.math.matrix.identity,
  multiplyMatrices = AseVoxel.math.matrix.multiplyMatrices,
  transposeMatrix = AseVoxel.math.matrix.transposeMatrix,
  isOrthogonal = AseVoxel.math.matrix.isOrthogonal,
  atan2 = AseVoxel.math.angles.atan2,
  normalizeAngle = AseVoxel.math.angles.normalizeAngle,
  wrapAngle = AseVoxel.math.angles.wrapAngle,
  mouseToTrackball = AseVoxel.math.trackball.mouseToTrackball,
  createAxisAngleMatrix = AseVoxel.math.trackball.createAxisAngleMatrix,
  createRotationMatrix = AseVoxel.math.rotation_matrix.createRotationMatrix,
  matrixToEuler = AseVoxel.math.rotation_matrix.matrixToEuler,
  createRelativeRotationMatrix = AseVoxel.math.rotation_matrix.createRelativeRotationMatrix,
  applyRelativeRotation = AseVoxel.math.rotation_matrix.applyRelativeRotation,
  setAxisRotation = AseVoxel.math.rotation_matrix.setAxisRotation,
  -- Also forward rotation functions for convenience
  applyAbsoluteRotation = AseVoxel.math.rotation.applyAbsoluteRotation,
  transformVoxel = AseVoxel.math.rotation.transformVoxel,
  optimizeVoxelModel = AseVoxel.math.rotation.optimizeVoxelModel
}

print("[AseVoxel] All modules loaded successfully!")

return AseVoxel
