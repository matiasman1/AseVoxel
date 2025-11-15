# Native Rendering Constraints & Buffer Management

> **Critical Reference for:** RENDER_REFACTOR_PROPOSAL.md  
> **Status:** Current implementation documentation  
> **Date:** 2025-11-06

---

## Overview

This document describes the **proven, working C++ rasterization path** that MUST be preserved during the render refactor. It explains the current buffer management approach, why it works, and the challenges we've faced with alternative approaches.

---

## 1. Current Architecture

### 1.1 High-Level Flow

```
Lua Request → asevoxel_native.cpp → C++ Rasterizer → Raw Buffer → Lua String → Aseprite Image
```

**Components:**

1. **Entry Point:** `l_render_basic(lua_State* L)` or `l_render_stack(lua_State* L)`
2. **Buffer Allocation:** `std::vector<unsigned char> buffer(width*height*4, 0)`
3. **Rasterization:** `rasterQuad(poly, width, height, buffer)`
4. **Buffer Return:** `lua_pushlstring(L, (const char*)buffer.data(), buffer.size())`
5. **Lua Side:** `Image{fromFile=pixels, width=w, height=h}`

### 1.2 Code Reference

**File:** `asevoxel_native.cpp` (lines 677-689)

```cpp
// Allocate RGBA buffer (4 bytes per pixel)
std::vector<unsigned char> buffer((size_t)width*height*4, 0);

// Fill background color
for(int y=0; y<height; y++){
  for(int x=0; x<width; x++){
    size_t off = ((size_t)y*width + x)*4;
    buffer[off+0] = bgR;  // Red
    buffer[off+1] = bgG;  // Green
    buffer[off+2] = bgB;  // Blue
    buffer[off+3] = bgA;  // Alpha
  }
}

// Rasterize all quads (far-to-near sorted)
for(auto &p: polys) rasterQuad(p, width, height, buffer);

// Return to Lua as binary string
lua_pushinteger(L, width);
lua_setfield(L, -2, "width");
lua_pushinteger(L, height);
lua_setfield(L, -2, "height");
lua_pushlstring(L, (const char*)buffer.data(), buffer.size());
lua_setfield(L, -2, "pixels");
```

**Lua Side:** (e.g., `previewRenderer.lua`)

```lua
local result = AseVoxel.native.render_basic(voxels, params)
local img = Image{
  fromFile = result.pixels,  -- Binary string from C++
  width = result.width,
  height = result.height
}
```

---

## 2. Why This Approach Works

### 2.1 Proven Stability

- **No crashes:** This path has been used in production without image corruption
- **Correct pixel layout:** RGBA byte order matches Aseprite's `Image{fromFile=...}` expectations
- **Memory safety:** `std::vector` handles allocation/deallocation automatically
- **Cross-platform:** Works on Linux, macOS, Windows without modifications

### 2.2 Performance Characteristics

- **Buffer allocation:** ~1-2ms for 1024x1024 image (one-time cost)
- **Rasterization:** Dominated by quad sorting and pixel writes
- **Lua string copy:** Negligible (<1ms for typical sizes)
- **Aseprite Image creation:** Fast (internal fromFile parser)

### 2.3 Minimal Dependencies

- **C++ stdlib only:** No external libraries (no libpng, libjpeg, etc.)
- **Lua C API:** Standard FFI boundary
- **Aseprite API:** Only uses `Image{fromFile=...}` constructor

---

## 3. Previous Failed Approaches

### 3.1 Attempt: Direct Pixel Manipulation via Lua Table

**Idea:** Build Lua table of pixels, use Aseprite's table constructor

**Issues:**
- **Slow:** 10-100x slower than binary string (FFI overhead per pixel)
- **Memory:** Lua heap fragmentation with large images
- **API Limitations:** No stable table → Image constructor in all Aseprite versions

### 3.2 Attempt: Native Image Object Construction

**Idea:** Create Aseprite `Image` object directly in C++

**Issues:**
- **No C++ API:** Aseprite doesn't expose Image constructor to C++ extensions
- **Lua-only:** Image class is Lua-side only (no native binding)
- **Version Fragility:** Internal APIs change between Aseprite releases

### 3.3 Attempt: Shared Memory Buffer

**Idea:** Allocate buffer in C++, pass pointer to Lua, wrap in Image

**Issues:**
- **Ownership Unclear:** Lua GC doesn't know about C++ buffer lifetime
- **Crashes:** Use-after-free when C++ deallocates before Lua finishes
- **Platform-Specific:** Different memory models on Windows vs Linux

### 3.4 Lessons Learned

✅ **Binary string transfer is reliable:** Lua's `lua_pushlstring` is designed for this
✅ **Aseprite's fromFile parser is robust:** Handles raw RGBA bytes without headers
❌ **Avoid native Image construction:** No stable API available
❌ **Don't mix Lua/C++ memory ownership:** Leads to lifetime issues

---

## 4. Critical Constraints for Refactor

### 4.1 MUST Preserve

**Target:** `OffscreenImage.Rasterizer` (in PipelineSpec)

**Requirements:**
- Buffer allocated in C++ (`std::vector<unsigned char>`)
- Rasterization performed in native code
- Buffer returned via `lua_pushlstring`
- Lua wraps in `Image{fromFile=...}`

**Why:** This is the **fallback path** when:
- Native backend available but GraphicsContext not supported
- Maximum compatibility mode needed
- User explicitly selects for stability

### 4.2 MAY Add (but don't break existing)

**New Targets:**
- `DirectCanvas.Path` (if Aseprite API available)
- `DirectCanvas.Rect` (if Aseprite API available)
- `OffscreenImage.Path` (Lua-side path building)

**Rule:** These are **additions**, not replacements. The rasterizer path must remain functional.

### 4.3 Testing Requirements

Before merging any refactor:
- [ ] Render 64³ voxel grid via `OffscreenImage.Rasterizer`
- [ ] Verify pixel-perfect match with pre-refactor output
- [ ] Check for memory leaks (Valgrind/ASAN)
- [ ] Test on all platforms (Linux, macOS, Windows)
- [ ] Benchmark: <5% performance regression

---

## 5. Rasterization Details

### 5.1 Quad Rasterizer (`rasterQuad`)

**File:** `asevoxel_native.cpp` (lines 200-300, approximate)

**Algorithm:**
1. **Bounding Box:** Compute min/max X/Y from quad vertices
2. **Scanline Loop:** Iterate rows, compute left/right edge intersections
3. **Span Fill:** Write color for X in [left, right]
4. **Alpha Blending:** Optional (currently overwrites)

**Color Format:** RGBA (0-255 per channel), 4 bytes per pixel

### 5.2 Depth Sorting

**File:** `asevoxel_native.cpp` (line 674)

```cpp
std::sort(polys.begin(), polys.end(), [](const FacePoly&a, const FacePoly&b){
  return a.depth > b.depth; // Far to near (painter's algorithm)
});
```

**Why:** No Z-buffer; relies on sorted back-to-front rendering

**Limitation:** Transparent faces require special handling (not yet implemented)

### 5.3 Performance Hotspots

1. **Depth Sort:** O(N log N) where N = visible faces (10k-100k typical)
2. **Rasterization:** O(pixels covered) per quad
3. **Background Fill:** O(width × height) once per frame

**Optimization Opportunities:**
- SIMD for span filling
- Parallel rasterization (tiles)
- Early-out for fully occluded faces

---

## 6. Integration with Refactor

### 6.1 PipelineSpec Mapping

| PipelineSpec Field | Value | Native Path |
|--------------------|-------|-------------|
| `backend` | `"Native"` | Use C++ code |
| `target` | `"OffscreenImage.Rasterizer"` | **THIS PATH** |
| `draw` | `"Mesh.Greedy"` or `"PerFace"` | Both supported |
| `shading` | `"Volumetric"` or `"Projected"` | Both supported |

### 6.2 Dispatch Function

**Proposed:** `render/native_render_dispatch.cpp`

```cpp
extern "C" int asev_render_dispatch(const char* json_spec, ...) {
  PipelineSpec spec = PipelineSpec::from_json_string(json_spec);
  
  if (spec.backend == Backend::Native &&
      spec.target == Target::OffscreenImage_Rasterizer) {
    // Call EXISTING rasterizer (preserved)
    return render_to_buffer_legacy(model, view, output);
  }
  
  // ... other paths ...
}
```

**Key:** `render_to_buffer_legacy` wraps current `l_render_basic` logic

### 6.3 Refactoring Strategy

**Phase 1:** Extract core rasterizer

```cpp
// New file: render/native_rasterizer_core.cpp
namespace asev {
  struct RasterBuffer {
    std::vector<unsigned char> data;
    int width, height;
  };
  
  RasterBuffer rasterize_faces(
    const std::vector<FacePoly>& polys,
    int width, int height,
    unsigned char bgR, unsigned char bgG, unsigned char bgB, unsigned char bgA
  );
}
```

**Phase 2:** Wrap for Lua compatibility

```cpp
// Existing entry point (unchanged externally)
static int l_render_basic(lua_State* L) {
  // ... parse params ...
  auto buf = asev::rasterize_faces(polys, width, height, bgR, bgG, bgB, bgA);
  
  lua_pushinteger(L, buf.width);
  lua_setfield(L, -2, "width");
  lua_pushinteger(L, buf.height);
  lua_setfield(L, -2, "height");
  lua_pushlstring(L, (const char*)buf.data.data(), buf.data.size());
  lua_setfield(L, -2, "pixels");
  return 1;
}
```

**Phase 3:** Add PipelineSpec dispatcher

```cpp
extern "C" int asev_render_dispatch(const char* json_spec, ...) {
  // ... route to asev::rasterize_faces ...
}
```

---

## 7. GraphicsContext Alternatives (Future)

### 7.1 What We Can't Do (Yet)

**No Direct C++ Access to:**
- `app.GraphicsContext` (Lua-only API)
- `gc:drawRect()`, `gc:drawPath()` (no C++ bindings)
- Aseprite's internal rendering pipeline

**Why:** Aseprite extensions are primarily Lua-based; C++ is for computation only

### 7.2 Potential Hybrid Approach

**Idea:** C++ computes geometry, Lua draws via GraphicsContext

```lua
-- Lua side
local faces = AseVoxel.native.compute_faces(model, view)
for _, face in ipairs(faces) do
  gc:drawRect(Rect(face.x, face.y, face.w, face.h))
  gc:fillColor(Color{r=face.r, g=face.g, b=face.b, a=face.a})
end
```

**Pros:**
- Leverages native speed for transforms/visibility
- Uses Aseprite's antialiasing/GPU acceleration

**Cons:**
- FFI overhead per face (thousands of calls)
- Complex marshaling for large datasets
- Still requires Lua→GC binding (not guaranteed stable)

**Status:** Investigate in Phase 6+ (see GRAPHICS_CONTEXT_CPP_INVESTIGATION.md)

---

## 8. Memory Safety Checklist

### 8.1 Buffer Lifecycle

- [ ] Allocated via `std::vector` (RAII)
- [ ] Size calculated: `width * height * 4` (checked for overflow?)
- [ ] Bounds-checked writes in `rasterQuad`
- [ ] Transferred to Lua via `lua_pushlstring` (copies data)
- [ ] C++ buffer destroyed when function returns (automatic)

### 8.2 Known Safe Patterns

✅ **Stack allocation for small data:** OK for metadata (width/height)  
✅ **Heap via smart pointers:** `std::vector` manages heap  
✅ **Lua string ownership:** Lua GC owns copied buffer  

### 8.3 Known Unsafe Patterns (AVOID)

❌ **Raw `new`/`delete`:** Use `std::vector` instead  
❌ **Passing C++ pointers to Lua:** Ownership unclear  
❌ **Shared mutable state:** Thread-unsafe  

---

## 9. Testing Protocol

### 9.1 Regression Tests

**File:** `tests/test_native_rasterizer.lua`

```lua
local function test_rasterizer_output()
  local voxels = generate_test_cube(16, 16, 16)
  local params = {
    width = 512, height = 512,
    xRotation = 30, yRotation = 45,
    scale = 8.0,
    backgroundColor = {r=0, g=0, b=0, a=255}
  }
  
  local result = AseVoxel.native.render_basic(voxels, params)
  
  assert(result.width == 512)
  assert(result.height == 512)
  assert(#result.pixels == 512*512*4)
  
  -- Compare against golden image
  local golden = load_golden_image("test_cube_30_45.png")
  local delta_e = compare_images(result.pixels, golden)
  assert(delta_e < 2.0, "Rendering changed: ΔE = " .. delta_e)
end
```

### 9.2 Performance Benchmarks

```lua
local function benchmark_rasterizer()
  local sizes = {32, 64, 128}
  for _, size in ipairs(sizes) do
    local voxels = generate_dense_voxels(size, size, size)
    local start = os.clock()
    AseVoxel.native.render_basic(voxels, {width=1024, height=1024})
    local elapsed = os.clock() - start
    print(string.format("%d³ voxels: %.2f ms", size, elapsed*1000))
    -- Assert: <100ms for 64³
    if size == 64 then assert(elapsed < 0.1) end
  end
end
```

### 9.3 Memory Leak Detection

```bash
# Linux
valgrind --leak-check=full aseprite test_native_rasterizer.lua

# macOS
leaks --atExit -- aseprite test_native_rasterizer.lua

# Windows
drmemory -- aseprite.exe test_native_rasterizer.lua
```

**Acceptance:** 0 leaks reported from asevoxel_native.cpp code

---

## 10. Documentation for Future Maintainers

### 10.1 When to Use This Path

**Use `OffscreenImage.Rasterizer` when:**
- Maximum compatibility needed (old Aseprite versions)
- Native backend available but GraphicsContext not
- User reports rendering issues with other targets (fallback)
- Performance is acceptable (not real-time preview)

### 10.2 When to Avoid

**Don't use when:**
- Real-time preview needed (60fps) → use DirectCanvas if available
- Aseprite version supports GraphicsContext → prefer DirectCanvas.Rect
- Purely debugging (use DebugViz preset with wireframes)

### 10.3 How to Debug

**Common Issues:**

1. **Black/Corrupt Image:**
   - Check buffer size calculation (overflow?)
   - Verify RGBA byte order (R, G, B, A not B, G, R, A)
   - Inspect `result.pixels` length in Lua

2. **Crash on Large Images:**
   - Add overflow check: `if (width * height > INT_MAX / 4) error()`
   - Limit max dimensions (e.g., 4096x4096)

3. **Wrong Colors:**
   - Verify gamma correction (linear vs sRGB)
   - Check color space conversion in shading code

**Debug Logging:**

```cpp
#ifdef ASEV_DEBUG
  fprintf(stderr, "[asev] Rasterizing %dx%d (%zu bytes)\n",
          width, height, buffer.size());
#endif
```

---

## 11. Copilot-Ready Refactor Prompts

### Task 1: Extract Rasterizer Core

```
Extract the core rasterization logic from asevoxel_native.cpp l_render_basic into a new file render/native_rasterizer_core.cpp:

- Create RasterBuffer struct {std::vector<unsigned char> data; int width, height;}
- Implement rasterize_faces(polys, width, height, bgRGBA) returning RasterBuffer
- Preserve exact pixel output (no algorithm changes)
- Keep rasterQuad() helper as static function
- Add unit tests for 16x16, 64x64, 512x512 outputs

Reference: NATIVE_RENDERING_CONSTRAINTS.md section 6.3
```

### Task 2: Add PipelineSpec Wrapper

```
Create render/native_rasterizer_compat.cpp wrapping native_rasterizer_core for PipelineSpec:

- Function: dispatch_rasterizer(PipelineSpec spec, model, view, output)
- Parse spec.shading to select color computation
- Call rasterize_faces() with computed polys
- Return RasterBuffer for Lua consumption
- Validate: identical output to old l_render_basic

Reference: NATIVE_RENDERING_CONSTRAINTS.md section 6.2
```

### Task 3: Preserve Lua API

```
Update asevoxel_native.cpp l_render_basic to delegate to native_rasterizer_core:

- Parse Lua params (unchanged)
- Call asev::rasterize_faces(...)
- Push RasterBuffer to Lua via lua_pushlstring (unchanged)
- Ensure 100% backward compatibility
- Run regression test suite

Reference: NATIVE_RENDERING_CONSTRAINTS.md section 6.3 Phase 2
```

---

## 12. Success Criteria

Before declaring the refactor complete:

- [ ] `OffscreenImage.Rasterizer` target renders identically to pre-refactor
- [ ] Performance within 5% of baseline
- [ ] Zero memory leaks (Valgrind clean)
- [ ] Works on Linux, macOS, Windows
- [ ] All existing Lua scripts call `render_basic` without changes
- [ ] New `render_dispatch` routes to legacy path correctly
- [ ] Documentation updated with refactored architecture

---

## Appendix: Code Locations

| Component | File | Lines | Description |
|-----------|------|-------|-------------|
| Buffer allocation | `asevoxel_native.cpp` | 677 | `std::vector<unsigned char>` |
| Background fill | `asevoxel_native.cpp` | 678-682 | RGBA loop |
| Rasterization | `asevoxel_native.cpp` | 684 | `rasterQuad()` calls |
| Buffer return | `asevoxel_native.cpp` | 686-689 | `lua_pushlstring` |
| Lua wrapper | `previewRenderer.lua` | ~50 | `Image{fromFile=...}` |

---

**Status:** Living document · Update as refactor progresses · Reference for all native rendering work.
