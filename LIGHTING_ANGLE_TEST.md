# Lighting Angle Test Results

**Date:** November 15, 2025  
**Purpose:** Verify dynamic lighting calculations respond correctly to different light angles

---

## Test Setup

### Model
- 4x4x4 hollow cube (wireframe - only outer shell visible)
- 60 exposed faces total
- Each voxel: RGB (180, 100, 220) - purple color

### Light Configuration
- **Test 1:** Light parallel to camera: `(0.0, 0.0, 1.0)`
- **Test 2:** Light at 45° angle: `(0.707, 0.0, 0.707)` (side-up direction, normalized)

### Shaders Tested
1. **Basic Lighting (Lambert)** - Simple diffuse + ambient
2. **Dynamic Lighting (Phong)** - Diffuse + specular highlights

---

## Expected Behavior

### With Parallel Light (0, 0, 1)
- All forward-facing surfaces should be equally lit
- No visible differences between faces with different orientations
- Maximum brightness on all visible faces

### With 45° Angled Light (0.707, 0, 0.707)
- **Right-facing surfaces** (normal +X) should be BRIGHTER (light hits them directly)
- **Left-facing surfaces** (normal -X) should be DARKER (light hits from behind)
- **Top/bottom faces** should have intermediate brightness
- **Front-facing surfaces** (normal +Z) should have moderate brightness

---

## Test Images Generated

### 45° Angle Tests (Light: 0.707, 0, 0.707)
1. `test_basic_45deg.png` - Basic shader with 45° light (416 bytes)
2. `test_dynamic_45deg.png` - Dynamic shader with 45° light, includes specular (416 bytes)
   - 60 visible faces rendered

### 90° Side Light Test (Light: 1.0, 0, 0)
3. `test_dynamic_90deg.png` - Dynamic shader with pure side lighting (337 bytes)
   - 40 visible faces rendered (20 fewer than 45° - faces perpendicular to light are very dark)
   - Smaller file size indicates higher contrast/more black areas

---

## Analysis Checklist

Compare the 45° angled images with expectations:

✓ **Brightness Variation:**
  - [ ] Right side (facing light) is brighter than left side
  - [ ] Clear gradient visible across the cube
  - [ ] Not uniformly lit (would indicate light angle being ignored)

✓ **Specular Highlights (Dynamic shader only):**
  - [ ] White highlights visible on surfaces facing both light and camera
  - [ ] Highlights concentrated on edges/corners where both conditions met
  - [ ] No highlights on surfaces facing away from light

✓ **Lambert Falloff (Basic shader):**
  - [ ] Smooth brightness gradient based on surface normal to light angle
  - [ ] Faces perpendicular to light have maximum brightness
  - [ ] Faces parallel to light have minimum brightness (ambient only)

---

## Next Steps

If the lighting responds correctly:
1. ✅ Lighting calculations are working properly
2. ✅ Normal computation is accurate
3. ✅ Light direction is being applied correctly
4. → Ready to integrate into main rendering pipeline

If issues found:
- Check normal calculation in shader
- Verify light direction normalization
- Review dot product calculations
- Test with more extreme angles (90°, opposite direction)

---

## Commands Used

```bash
# Build shaders with modified light angle
cd render/shaders
make clean && make

# Test basic shader
./bin/test_host_shim ./bin pixelmatt.basic test_basic_45deg.png

# Test dynamic shader
./bin/test_host_shim ./bin pixelmatt.dynamic test_dynamic_45deg.png
```
