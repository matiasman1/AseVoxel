# Quick Test Card - AseVoxel Shader Stack

## 🚀 Quick Start (5 minutes)

### 1. Install Extension
```bash
# Build extension
cd /home/usuario/Documentos/AseVoxel
bash create_extension.sh -k -C

# Install in Aseprite:
# Edit → Preferences → Extensions → Add Extension
# Select: AseVoxel-Viewer.aseprite-extension
# Restart Aseprite
```

### 2. Open Test Sprite
1. Create new sprite (any size)
2. Draw a simple 3x3 colored cross
3. View → AseVoxel Viewer

### 3. Test Shader Stack
**In Main Dialog → Lighting Tab:**
- See: "Lighting Shaders: (none - using default)"
- Click "Add Lighting Shader..."
- Select "Dynamic Light (dynamic)"
- Click "Add"
- Click "Configure Shaders..."
- Adjust Pitch slider → Preview updates ✅

**In Main Dialog → FX Tab:**
- Click "Add FX Shader..."
- Select "Face Shade (faceshade)"
- Click "Add"
- Click "Configure Shaders..."
- Adjust brightness values → Preview updates ✅

### 4. Test Debug Tools
**In Main Dialog → Debug Tab:**
- Scroll to "Shader Stack Testing"
- Click "Test Shader Stack"
- Should show: ✓ Found 2 lighting shaders, ✓ Found 3 FX shaders
- Click "Test Full Pipeline" → Should render without errors

## ✅ Pass Criteria (Essential)

| Test | Expected Result | Status |
|------|----------------|--------|
| Extension loads | No errors in console | ⬜ |
| Preview shows model | Voxels visible with lighting | ⬜ |
| Add shader works | Shader appears in list | ⬜ |
| Configure works | Parameter dialog opens | ⬜ |
| Preview updates | Changes reflected immediately | ⬜ |
| Debug test passes | All shaders valid | ⬜ |

## 🐛 Common Issues

### "Shader stack module not loaded!"
**Fix:** Check console for loading errors

### Preview is black
**Fix:** Debug tab → "Reset to Default Shader"

### Sliders don't work
**Fix:** Check console for Lua errors

### Extension won't install
**Fix:** Check that all .lua files are present

## 📊 Quick Test Results

**Date:** _________
**Aseprite Version:** _________
**OS:** _________

**Overall Status:** ⬜ PASS / ⬜ FAIL

**Critical Issues:**
- 

**Notes:**
- 

## 📝 Report Issues

If tests fail, provide:
1. Console output (Help → Developer Console)
2. Which test failed
3. Error message (if any)
4. Aseprite version and OS

## 🎯 Success = All checkboxes ✅

If all tests pass, the integration is successful! 🎉

Next: Implement native C++ renderer for performance.
