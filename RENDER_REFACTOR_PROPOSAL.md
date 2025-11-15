# AseVoxel Render Refactor Proposal

> **Author:** Matias (PixelMatt)  
> **Version:** 1.0  
> **Date:** 2025-11-06  
> **Branch:** Shader-Refactor

---

## Executive Summary

This proposal introduces a **composable rendering pipeline** for AseVoxel that decouples execution backend, draw target, geometry strategy, and shading mode into orthogonal configuration axes. The goal is to enable flexible performance/quality tradeoffs while maintaining backward compatibility and paving the way for native C++ shader acceleration.

### Key Changes

- **4-Axis Pipeline Model:** Backend × Target × Draw × Shading
- **Preset System:** 7 curated configurations (Voxel-like, Fast, Balanced, etc.)
- **Native Shader API:** C ABI for stackable C++ shaders alongside Lua
- **PipelineSpec:** Unified JSON-based configuration shared between Lua/C++

---

## 1. Pipeline Architecture

### 1.1 The Four Axes

Each render pass is defined by selecting one option from each axis:

#### **1. Backend** (execution environment)
- `Native` — C++/native module (asevoxel_native)
- `Local` — Pure Lua execution

#### **2. Target** (rendering output)
- `DirectCanvas.Path` — GraphicsContext paths (Aseprite API v19+)
- `DirectCanvas.Rect` — GraphicsContext rectangle primitives
- `OffscreenImage.Path` — Build paths into offscreen Aseprite Image
- `OffscreenImage.Rasterizer` — Software rasterization into buffer

#### **3. Draw Strategy** (geometry batching)
- `Mesh.Greedy` — Greedy meshing (merge coplanar faces)
- `PerFace` — One draw call per visible face (no batching)

#### **4. Shading Mode** (lighting model)
- `Volumetric` — Up to 3 lit trapezoidal faces per voxel
- `Projected` — Single square per voxel (dominant face color)

### 1.2 Compatibility Matrix

| Backend | Target | Draw | Shading | Notes |
|---------|--------|------|---------|-------|
| Native | DirectCanvas.* | Any | Any | Best performance; requires GC API |
| Native | OffscreenImage.Rasterizer | Any | Any | CPU raster in C++; **current proven path** |
| Local | DirectCanvas.* | Any | Any | Lua with GC; supports full ShaderStack |
| Local | OffscreenImage.* | Any | Any | Maximum compatibility |

**Critical Constraint:** Native + OffscreenImage.Rasterizer **must remain supported** due to proven stability with current C++ buffer → Aseprite Image conversion.

---

## 2. Presets

Pre-configured pipelines for common use cases:

### 2.1 Preset Definitions

| Preset | Backend | Target | Draw | Shading | Use Case |
|--------|---------|--------|------|---------|----------|
| **Voxel-like** | Native | DirectCanvas.Path | Mesh.Greedy | Volumetric | High-fidelity 3D look |
| **Fast** | Native | DirectCanvas.Rect | PerFace | Projected | Maximum speed |
| **Balanced** | Native | DirectCanvas.Rect | Mesh.Greedy | Projected | Speed + quality |
| **HQ-Path** | Local | DirectCanvas.Path | PerFace | Volumetric | Full Lua ShaderStack |
| **Preview Ultra** | Local | OffscreenImage.Rasterizer | Mesh.Greedy | Projected | Max compatibility |
| **Legacy-Compat** | Local | OffscreenImage.Path | PerFace | Volumetric | Current behavior |
| **Debug Viz** | Local | DirectCanvas.Rect | PerFace | Projected | Overlays (normals, etc.) |

### 2.2 Preset Override System

Users can:
1. Select a preset as base
2. Override individual axes in "Advanced" panel
3. Save custom presets to JSON

---

## 3. Mathematical Foundation

### 3.1 Transform Pipeline

For each voxel/face, compute screen position via:

$$\mathbf{p}_{\text{clip}} = \mathbf{P} \cdot \mathbf{V} \cdot \mathbf{M}_w \cdot \mathbf{p}_{\text{local}}$$

Where:
- $\mathbf{M}_w$ — World transform (from voxel grid origin)
- $\mathbf{V}$ — View matrix (camera position/orientation)
- $\mathbf{P}$ — Projection matrix (orthographic or perspective)

**Rotation Representation:** Quaternions $\mathbf{q} = (x, y, z, w)$  
Incremental update: $\mathbf{q}' = \text{normalize}(\Delta\mathbf{q} \otimes \mathbf{q})$

### 3.2 Lighting Models

#### Volumetric Shading

Each visible face $f$ with world-space normal $\mathbf{n}_f$ receives:

$$L_f = \sum_{i=1}^{N_L} k_i \cdot \max(0, \langle \mathbf{n}_f, \hat{\ell}_i \rangle) + A$$

Where:
- $k_i$ — Light intensity
- $\hat{\ell}_i$ — Light direction (unit vector)
- $A$ — Ambient term

Optional Blinn-Phong specular:

$$S_f = \sum_i s_i \cdot \max\big(0, \langle \hat{\mathbf{r}}_i, \hat{\mathbf{v}} \rangle\big)^{p_i}$$

Final voxel color (area-weighted average):

$$\mathbf{c}_v = \sum_{f \in \text{vis}(v)} w_f \cdot (L_f + S_f) \cdot \mathbf{a}_f$$

#### Projected Shading

Select dominant face $f^*$ via:
1. **TLR Priority:** Top > Left > Right > Front > Back > Bottom
2. **Projected Area:** $\text{argmax}_f \, \text{area}(\mathbf{n}_f, \hat{\mathbf{v}})$

Then:

$$\mathbf{c}_v = (L_{f^*} + S_{f^*}) \cdot \mathbf{a}_{f^*}$$

---

## 4. Greedy Meshing Algorithm

### 4.1 Per-Orientation Pass

For each cardinal direction (X+, X−, Y+, Y−, Z+, Z−):

1. **Slice:** Extract 2D grid of visible faces perpendicular to direction
2. **Scanline Merge:** 
   - Left-to-right: extend rectangles while material/normal match
   - Top-to-bottom: merge vertically compatible rows
3. **Emit Quad:** Store merged geometry with averaged normal $\bar{\mathbf{n}}$

### 4.2 Lighting with Merged Quads

Area-weighted normal for quad $Q$ covering faces $\{f_j\}$:

$$\bar{\mathbf{n}}_Q = \frac{1}{A_Q} \sum_j A_j \cdot \mathbf{n}_j$$

Apply lighting equation with $\bar{\mathbf{n}}_Q$ to preserve volumetric appearance.

---

## 5. Implementation Phases

### Phase 1: Foundation (Weeks 1-2)
- [ ] `PipelineSpec` struct (Lua + C++)
- [ ] JSON serialization/deserialization
- [ ] Preset definitions
- [ ] Validation/compatibility checks

### Phase 2: Dispatch Layer (Weeks 3-4)
- [ ] Routing function: `PipelineSpec → execution path`
- [ ] Backend selection (Native vs Local)
- [ ] Target selection (DirectCanvas vs OffscreenImage)
- [ ] Preserve existing Native + Rasterizer path

### Phase 3: Geometry (Weeks 5-6)
- [ ] Greedy meshing module (Lua)
- [ ] Greedy meshing module (C++)
- [ ] PerFace rendering path
- [ ] Mesh rendering path

### Phase 4: Shading (Weeks 7-8)
- [ ] Projected shader implementation
- [ ] Volumetric shader (refactor existing)
- [ ] TLR priority face selection
- [ ] Area-based dominant face selection

### Phase 5: UI Integration (Weeks 9-10)
- [ ] MainDialog Render tab
- [ ] Preset selector dropdown
- [ ] Advanced override controls
- [ ] Dependency validation UI
- [ ] Performance HUD

### Phase 6: Native Shader API (Weeks 11-14)
- [ ] C ABI definition (`asev_shader_api.h`)
- [ ] Dynamic loader (dlopen/LoadLibrary)
- [ ] Stage model implementation
- [ ] Param system + UI binding
- [ ] Example shaders (2-3 reference implementations)

---

## 6. Migration Strategy

### 6.1 Backward Compatibility

- **Default Preset:** "Legacy-Compat" matches current behavior
- **Auto-Migration:** Existing user settings map to closest preset
- **Fallback Chain:** Native unavailable → Local; DirectCanvas unsupported → OffscreenImage

### 6.2 Deprecation Timeline

- **Immediate:** All paths supported
- **3 months:** Legacy-Compat marked as deprecated in UI
- **6 months:** Legacy-Compat removed; users must select modern preset

---

## 7. Performance Targets

Based on reference scene (64³ voxels, 50% fill):

| Preset | Target FPS | Draw Calls | Quality |
|--------|------------|------------|---------|
| Fast | 60+ | <100 | Medium |
| Balanced | 30-60 | <500 | High |
| Voxel-like | 15-30 | <1000 | Very High |
| HQ-Path | 10-15 | <2000 | Maximum |

---

## 8. Open Questions

1. **Face AO Precompute:** Should we cache ambient occlusion per face? (Memory vs quality tradeoff)
2. **Image Graph:** Future abstraction to unify Lua/Native shader stacks as dataflow nodes?
3. **Per-Shader Presets:** Allow shaders to ship their own preset bundles?
4. **Hot Reload:** Native shader hot-reload without restart? (Scope: Phase 7?)

---

## 9. Success Criteria

- [ ] All 7 presets render correctly
- [ ] Performance targets met for Fast/Balanced
- [ ] Zero regressions in image quality for Legacy-Compat
- [ ] Native + Rasterizer path preserved
- [ ] At least 2 example native shaders shipped
- [ ] Community preset sharing enabled

---

## 10. Related Documents

- [NATIVE_SHADER_API.md](./NATIVE_SHADER_API.md) — C ABI specification
- [PIPELINE_SPEC.md](./PIPELINE_SPEC.md) — JSON schema & code
- [IMPLEMENTATION_PLAN.md](./IMPLEMENTATION_PLAN.md) — Detailed work breakdown
- [NATIVE_RENDERING_CONSTRAINTS.md](./NATIVE_RENDERING_CONSTRAINTS.md) — C++ rasterizer requirements

---

## Appendix A: Quick Reference

### A.1 Enum Values (Lua & C++)

```lua
Backend = { Native = "Native", Local = "Local" }
Target  = {
  DirectCanvas_Path = "DirectCanvas.Path",
  DirectCanvas_Rect = "DirectCanvas.Rect",
  OffscreenImage_Path = "OffscreenImage.Path",
  OffscreenImage_Rasterizer = "OffscreenImage.Rasterizer"
}
Draw = { Mesh_Greedy = "Mesh.Greedy", PerFace = "PerFace" }
Shading = { Volumetric = "Volumetric", Projected = "Projected" }
```

### A.2 Minimal PipelineSpec JSON

```json
{
  "backend": "Native",
  "target": "OffscreenImage.Rasterizer",
  "draw": "Mesh.Greedy",
  "shading": "Projected",
  "shader_stack": [],
  "name": "Custom Preset"
}
```

---

**Next Steps:** Review with team → Approve phases 1-3 → Begin implementation.
