# AseVoxel Shader Stack Integration - Test Guide

## Quick Test Checklist

### 1. Extension Loading Test
**Goal:** Verify the extension loads without errors

**Steps:**
1. Open Aseprite
2. Go to Edit → Preferences → Extensions
3. Click "Add Extension" and select the `AseVoxel-Viewer.aseprite-extension` file
   - OR if already installed: disable and re-enable
4. Restart Aseprite
5. Check console for errors (Help → Developer Console)

**Expected Output:**
```
[AseVoxel] Loading modular extension...
[AseVoxel] Loading Layer 0: Pure Utilities...
[AseVoxel] Layer 0 complete: matrix, angles
[AseVoxel] Loading Layer 1: Basic Operations...
[AseVoxel] Layer 1 complete: trackball, rotation_matrix, rotation
[AseVoxel] Loading Layer 2: Rendering Core...
[AseVoxel] Layer 2 complete: rendering modules + shader stack
[AseVoxel] Loading Layer 3: File I/O...
[AseVoxel] Layer 3 complete: file I/O and voxel generation
[AseVoxel] Loading Layer 4: Core Logic...
[AseVoxel] Layer 4 complete: core application logic
[AseVoxel] Loading Layer 5: Utilities...
[AseVoxel] Layer 5 complete: utilities
[AseVoxel] Loading Layer 6: UI Dialogs...
[AseVoxel] Layer 6 complete: UI dialogs
[AseVoxel] All modules loaded successfully!
[AseVoxel] Initializing extension...
[AseVoxel] Extension initialized successfully!
```

**Pass Criteria:**
- ✅ No errors in console
- ✅ "AseVoxel Viewer" appears in View menu
- ✅ All layer loading messages appear

---

### 2. Basic Rendering Test
**Goal:** Verify default shader stack works

**Steps:**
1. Create a new sprite (any size)
2. Draw a few colored pixels (e.g., a simple 3x3 cross shape)
3. Go to View → AseVoxel Viewer
4. The preview window should open showing your voxel model

**Expected Results:**
- ✅ Preview window opens without errors
- ✅ Voxel model is visible
- ✅ Model has lighting (not flat gray)
- ✅ Model rotates with mouse drag
- ✅ Scrolling zooms in/out

**Debug:** If errors occur, check Debug tab → "Refresh Debug Info" to see backend status

---

### 3. Shader Stack UI Test
**Goal:** Verify new shader management tabs work

**Steps:**
1. With AseVoxel Viewer open, go to the main dialog
2. Click on the "Lighting" tab

**Expected UI:**
```
Lighting Shaders
  Lighting Shaders:
    (none - using default)
  
  [Add Lighting Shader...] [Configure Shaders...] [Clear All]
```

3. Click "Add Lighting Shader..."
4. A dialog should appear with available shaders:
   - Basic Light (basic)
   - Dynamic Light (dynamic)

**Pass Criteria:**
- ✅ Both tabs (Lighting and FX) are visible
- ✅ "Add Shader" button works
- ✅ Shader selection dialog shows available shaders
- ✅ Can add a shader to the stack
- ✅ Preview updates after adding shader

---

### 4. Shader Configuration Test
**Goal:** Verify shader parameters can be adjusted

**Steps:**
1. In Lighting tab, add a "Dynamic Light" shader
2. Click "Configure Shaders..."
3. A dialog should open showing the shader parameters:
   - Pitch slider
   - Yaw slider
   - Diffuse % slider
   - Ambient % slider
   - Light Color picker
   - Rim Lighting checkbox

4. Adjust the Pitch slider
5. Close configuration dialog
6. Preview should update with new lighting

**Pass Criteria:**
- ✅ Configuration dialog opens
- ✅ All parameters are visible
- ✅ Sliders work
- ✅ Color picker works
- ✅ Preview updates when parameters change

---

### 5. Shader Reordering Test
**Goal:** Verify shaders can be reordered/removed

**Steps:**
1. Add 2 lighting shaders (e.g., Basic + Dynamic)
2. Click "Configure Shaders..."
3. Click ↑ button on second shader
4. Shader should move up in the list
5. Click "Remove" button on a shader
6. Shader should be removed

**Pass Criteria:**
- ✅ Shaders can be reordered with ↑/↓ buttons
- ✅ Shaders can be removed
- ✅ Preview updates after reordering
- ✅ List refreshes correctly

---

### 6. FX Shader Test
**Goal:** Verify FX shaders work

**Steps:**
1. Go to "FX" tab
2. Click "Add FX Shader..."
3. Select "Face Shade (faceshade)"
4. Click "Add"
5. Click "Configure Shaders..."
6. Adjust brightness values for different faces

**Expected FX Shaders:**
- Face Shade (faceshade) - Model-center face brightness
- Face Shade Camera (faceshade_camera) - Camera-relative shading
- Isometric (iso) - Isometric shading

**Pass Criteria:**
- ✅ FX shaders can be added
- ✅ FX shader parameters can be configured
- ✅ Preview shows FX shader effect
- ✅ Can combine lighting + FX shaders

---

### 7. Debug Tab Test
**Goal:** Verify shader stack testing tools work

**Steps:**
1. Go to "Debug" tab
2. Scroll down to "Shader Stack Testing" section
3. Click "Test Shader Stack"
4. A dialog should show:
   ```
   === Shader Stack Test ===
   ✓ Shader stack module loaded
   ✓ Found 2 lighting shaders
   ✓ Found 3 FX shaders
   ✓ Current config: 1 lighting, 0 FX
   ✓ All shaders valid
   ```

5. Click "Test Full Pipeline"
6. Should render and show timing

7. Click "Reset to Default Shader"
8. Should reset to basicLight shader

**Pass Criteria:**
- ✅ Test Shader Stack button works
- ✅ All shaders are found and valid
- ✅ Pipeline test completes without errors
- ✅ Reset to default works

---

### 8. Performance Test
**Goal:** Verify rendering performance is acceptable

**Steps:**
1. Enable profiling in Debug tab
2. Rotate the model several times
3. Click "Show Profiling Report"
4. Check render times

**Expected Performance (on moderate hardware):**
- Small models (<100 voxels): <50ms per frame
- Medium models (100-500 voxels): <150ms per frame
- Large models (500+ voxels): <500ms per frame

**Pass Criteria:**
- ✅ Profiling report shows timing data
- ✅ Render times are reasonable for model size
- ✅ No crashes or freezes during rendering

---

## Known Issues & Troubleshooting

### Issue: "Shader stack module not loaded!"
**Cause:** loader.lua didn't load shader modules
**Fix:** Check console for loading errors, ensure shader_stack.lua exists

### Issue: "No lighting shaders to configure!"
**Cause:** Shader stack not initialized
**Fix:** Click "Reset to Default Shader" in Debug tab

### Issue: Preview is completely black
**Cause:** Shader returned nil or invalid color
**Fix:** 
1. Check Debug tab → "Last backend" 
2. Try "Reset to Default Shader"
3. Check console for shader errors

### Issue: Sliders don't update preview
**Cause:** schedulePreview() not being called
**Fix:** Check that callbacks are wired correctly in main_dialog.lua

### Issue: Extension won't load
**Cause:** Syntax error in modified files
**Fix:** 
1. Check Help → Developer Console for error messages
2. Review recent file changes
3. Use git diff to see what changed

---

## Regression Testing

### Old System Compatibility
The old lighting system has been COMPLETELY REMOVED. This is intentional.

**What was removed:**
- ❌ shadingMode = "Basic" | "Dynamic" | "Stack" parameter
- ❌ params.lighting table (pitch, yaw, diffuse, etc.)
- ❌ params.fxStack (old FX stack)
- ❌ basicShadeIntensity / basicLightIntensity parameters
- ❌ Old "FX" tab with mode selector

**What replaces it:**
- ✅ params.shaderStack = { lighting: [...], fx: [...] }
- ✅ Modular shader pipeline
- ✅ Auto-generated UI from shader schemas
- ✅ Two separate tabs: "Lighting" and "FX"

**Migration:**
Old scenes/code will need shader stack initialization. The default is:
```lua
shaderStack = {
  lighting = { { id = "basic", params = { lightIntensity = 50, shadeIntensity = 50 } } },
  fx = {}
}
```

---

## Success Metrics

### Minimum Functional Version (Current Goal)
- [x] Extension loads without errors
- [ ] Default shader provides visible lighting
- [ ] Can add/remove/configure shaders via UI
- [ ] Preview updates when shaders change
- [ ] No crashes during normal use

### Complete Integration (Future)
- [ ] Native C++ renderer supports shader stack
- [ ] Scene persistence works
- [ ] Migration from old system seamless
- [ ] Documentation complete
- [ ] Performance matches or exceeds old system

---

## Test Results Log

### Test Date: [Fill in when testing]

| Test | Status | Notes |
|------|--------|-------|
| 1. Extension Loading | ⬜ | |
| 2. Basic Rendering | ⬜ | |
| 3. Shader Stack UI | ⬜ | |
| 4. Shader Configuration | ⬜ | |
| 5. Shader Reordering | ⬜ | |
| 6. FX Shader | ⬜ | |
| 7. Debug Tab | ⬜ | |
| 8. Performance | ⬜ | |

**Overall Status:** ⬜ Pass / ⬜ Fail / ⬜ Partial

**Critical Issues Found:**
- 

**Non-Critical Issues:**
- 

**Performance Notes:**
- 

---

## Next Steps After Testing

1. **If ALL tests pass:**
   - ✅ Backend integration complete!
   - Move to native C++ renderer implementation
   - Update documentation

2. **If MOST tests pass:**
   - Fix critical issues
   - Document known issues
   - Continue with native renderer work

3. **If MANY tests fail:**
   - Review code changes carefully
   - Check for syntax errors
   - Test individual shaders in isolation
   - Verify loader.lua includes all modules

---

**Testing completed by:** [Name]
**Date:** [Date]
**Aseprite Version:** [Version]
**OS:** [Linux/Windows/macOS]
