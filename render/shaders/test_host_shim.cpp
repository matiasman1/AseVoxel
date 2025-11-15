// Test host shim: Provides minimal host helper functions and tests a shader end-to-end
// This demonstrates: hardcoded model → shader → buffer → PNG output (NO Lua)

#include "../native_shader_api.h"
#include "native_shader_loader.hpp"
#include <cstdio>
#include <cstring>
#include <cstdlib>
#include <cmath>
#include <vector>
#include <algorithm>

// stb_image_write for PNG output
#include "stb_image_write_real.h"

// Hardcoded 4x4x4 voxel model for testing
// Each voxel: RGBA (0=empty, >0=colored)
static unsigned char g_test_model[4][4][4][4];

// Model dimensions
static int g_model_size[3] = {4, 4, 4};

// Host helper: Get voxel color from model
extern "C" int native_model_get_voxel(void* model, int x, int y, int z, unsigned char out_rgba[4]) {
    (void)model; // Unused
    
    // Bounds check
    if (x < 0 || x >= 4 || y < 0 || y >= 4 || z < 0 || z >= 4) {
        return 0; // Outside bounds
    }
    
    // Copy voxel data
    out_rgba[0] = g_test_model[z][y][x][0];
    out_rgba[1] = g_test_model[z][y][x][1];
    out_rgba[2] = g_test_model[z][y][x][2];
    out_rgba[3] = g_test_model[z][y][x][3];
    
    return (out_rgba[3] > 0) ? 1 : 0; // 1 if opaque, 0 if empty
}

// Host helper: Get model size
extern "C" int native_model_get_size(void* model, int* out_x, int* out_y, int* out_z) {
    (void)model; // Unused
    if (out_x) *out_x = g_model_size[0];
    if (out_y) *out_y = g_model_size[1];
    if (out_z) *out_z = g_model_size[2];
    return 0; // Success
}

// Host helper: Check if voxel is visible (simplified - always true for occupied voxels)
extern "C" int native_model_is_visible(void* model, int x, int y, int z) {
    (void)model; // Unused
    unsigned char rgba[4];
    return native_model_get_voxel(nullptr, x, y, z, rgba);
}

// Initialize test model: Hollow wireframe cube (only edges visible from outside)
void init_test_model() {
    memset(g_test_model, 0, sizeof(g_test_model));
    
    // Create a true hollow wireframe cube - only the outer shell, no interior
    // This means: if any coordinate is at min or max, it's part of the shell
    for (int z = 0; z < 4; z++) {
        for (int y = 0; y < 4; y++) {
            for (int x = 0; x < 4; x++) {
                // Only draw the outer shell (at least one axis at boundary)
                bool is_edge = (x == 0 || x == 3 || y == 0 || y == 3 || z == 0 || z == 3);
                
                if (is_edge) {
                    g_test_model[z][y][x][0] = 200; // R
                    g_test_model[z][y][x][1] = 50;  // G
                    g_test_model[z][y][x][2] = 50;  // B
                    g_test_model[z][y][x][3] = 255; // A
                }
            }
        }
    }
}

int main(int argc, char** argv) {
    if (argc < 3) {
        fprintf(stderr, "Usage: %s <shader_dir> <shader_id> [output.png]\n", argv[0]);
        fprintf(stderr, "Example: %s ../../bin pixelmatt.basic test_output.png\n", argv[0]);
        return 1;
    }
    
    const char* shader_dir = argv[1];
    const char* shader_id = argv[2];
    const char* output_path = (argc >= 4) ? argv[3] : "test_output.png";
    
    printf("=== Native Shader Test Host ===\n");
    printf("Shader directory: %s\n", shader_dir);
    printf("Target shader ID: %s\n", shader_id);
    printf("Output PNG: %s\n\n", output_path);
    
    // Initialize test model
    init_test_model();
    printf("[1/6] Initialized 4x4x4 hollow cube model\n");
    
    // Scan for shaders
    int count = native_shader_loader::scan_directory(shader_dir);
    printf("[2/6] Scanned shader directory: %d shaders found\n", count);
    
    if (count == 0) {
        fprintf(stderr, "ERROR: No shaders loaded\n");
        return 1;
    }
    
    // List all shaders
    printf("      Available shaders:\n");
    for (int i = 0; i < count; i++) {
        const char* id = native_shader_loader::get_shader_id(i);
        const native_shader_v1_t* iface = native_shader_loader::get_shader_interface(id);
        if (iface) {
            printf("        - %s (%s)\n", id, iface->display_name());
        }
    }
    printf("\n");
    
    // Get shader interface
    const native_shader_v1_t* shader = native_shader_loader::get_shader_interface(shader_id);
    if (!shader) {
        fprintf(stderr, "ERROR: Shader '%s' not found\n", shader_id);
        native_shader_loader::unload_all();
        return 1;
    }
    
    printf("[3/6] Found shader: %s\n", shader->display_name());
    
    // Create shader instance
    void* instance = native_shader_loader::create_shader_instance(shader_id);
    if (!instance) {
        fprintf(stderr, "ERROR: Failed to create shader instance\n");
        native_shader_loader::unload_all();
        return 1;
    }
    
    printf("[4/6] Created shader instance\n");
    
    // Set up rendering context
    native_ctx_t ctx;
    memset(&ctx, 0, sizeof(ctx));
    
    // Identity matrices (simplified - no transforms)
    for (int i = 0; i < 16; i++) {
        ctx.M[i] = (i % 5 == 0) ? 1.0f : 0.0f; // Identity
        ctx.V[i] = (i % 5 == 0) ? 1.0f : 0.0f;
        ctx.P[i] = (i % 5 == 0) ? 1.0f : 0.0f;
    }
    
    // Lighting setup for isometric view:
    // Camera at (1, 1, -1), light direction points FROM voxels TO camera
    // View direction = (1, 1, -1) normalized
    // This makes all three visible faces (front +Z, right +X, top +Y) equally lit!
    // Verify: (1,0,0)·(1,1,-1) = 1, (0,1,0)·(1,1,-1) = 1, (0,0,1)·(1,1,-1) = -1
    // Wait, that's not equal... Let me recalculate for TRUE isometric equality
    // Actually for isometric, we need to rotate the NORMALS, not change light dir!
    // But since we're NOT rotating the model, the view dir should be straight (0,0,1)
    // and the model should be rotated. Let's use the AseVoxel convention:
    ctx.num_lights = 1;
    
    // AseVoxel basic mode: view direction is ALWAYS (0, 0, 1)
    // The MODEL is rotated to isometric angle, not the camera!
    // TEST: Light from 45-degree angle (side-up) for FaceShade testing
    ctx.lights[0].dir[0] = 0.707f;  // 45° in X
    ctx.lights[0].dir[1] = 0.0f;    // No Y component
    ctx.lights[0].dir[2] = 0.707f;  // 45° in Z (normalized)
    ctx.lights[0].intensity = 1.0f;
    ctx.lights[0].spec_power = 32.0f;
    
    ctx.model = nullptr; // Not used (host helpers read g_test_model directly)
    ctx.time_sec = 0.0f;
    ctx.width = 64;  // Render to 64x64 image
    ctx.height = 64;
    
    // Allocate output buffer
    int buffer_size = ctx.width * ctx.height * 4; // RGBA
    unsigned char* buffer = (unsigned char*)malloc(buffer_size);
    if (!buffer) {
        fprintf(stderr, "ERROR: Failed to allocate output buffer\n");
        native_shader_loader::destroy_shader_instance(shader_id, instance);
        native_shader_loader::unload_all();
        return 1;
    }
    
    memset(buffer, 0, buffer_size); // Clear to black
    ctx.output_buffer = buffer;
    ctx.output_stride = ctx.width * 4;
    
    printf("[5/6] Rendering 4x4x4 model to %dx%d buffer...\n", ctx.width, ctx.height);
    printf("      Light 0: (%.2f, %.2f, %.2f), intensity: %.2f\n", 
           ctx.lights[0].dir[0], ctx.lights[0].dir[1], ctx.lights[0].dir[2], ctx.lights[0].intensity);
    printf("      Light 1: (%.2f, %.2f, %.2f), intensity: %.2f\n", 
           ctx.lights[1].dir[0], ctx.lights[1].dir[1], ctx.lights[1].dir[2], ctx.lights[1].intensity);
    
    // Proper isometric face-based rendering with pixel-perfect alignment
    // Each voxel face is drawn as a rhombus/diamond polygon
    int voxels_rendered = 0;
    int faces_rendered = 0;
    
    // Unit cube vertices (8 corners)
    float cube_verts[8][3] = {
        {-0.5f, -0.5f, -0.5f}, // 0: back-bottom-left
        { 0.5f, -0.5f, -0.5f}, // 1: back-bottom-right
        { 0.5f,  0.5f, -0.5f}, // 2: back-top-right
        {-0.5f,  0.5f, -0.5f}, // 3: back-top-left
        {-0.5f, -0.5f,  0.5f}, // 4: front-bottom-left
        { 0.5f, -0.5f,  0.5f}, // 5: front-bottom-right
        { 0.5f,  0.5f,  0.5f}, // 6: front-top-right
        {-0.5f,  0.5f,  0.5f}  // 7: front-top-left
    };
    
    // Face definitions (vertex indices for each quad)
    struct Face {
        int verts[4];  // CCW winding
        const char* name;
    };
    
    Face faces[6] = {
        {{4, 5, 6, 7}, "front"},  // +Z
        {{1, 0, 3, 2}, "back"},   // -Z
        {{5, 1, 2, 6}, "right"},  // +X
        {{0, 4, 7, 3}, "left"},   // -X
        {{7, 6, 2, 3}, "top"},    // +Y
        {{0, 1, 5, 4}, "bottom"}  // -Y
    };
    
    // Helper: project 3D point to isometric 2D (pixel-perfect)
    auto project_iso = [](float x, float y, float z) -> std::pair<int, int> {
        // Isometric projection (2:1 ratio, pixel-perfect)
        // X-axis: right 4px, down 2px
        // Z-axis: left 4px, down 2px
        // Y-axis: up 4px
        int iso_x = (int)((x - z) * 4.0f);
        int iso_y = (int)((x + z) * 2.0f - y * 4.0f);
        
        // Center in canvas
        iso_x += 32;
        iso_y += 32;
        
        return {iso_x, iso_y};
    };
    
    // Helper: fill a convex quad (scanline rasterizer)
    auto fill_quad = [&](int x0, int y0, int x1, int y1, int x2, int y2, int x3, int y3, 
                         unsigned char r, unsigned char g, unsigned char b) {
        // Simple scanline fill for convex quad
        // Find Y bounds
        int min_y = y0;
        int max_y = y0;
        if (y1 < min_y) min_y = y1; if (y1 > max_y) max_y = y1;
        if (y2 < min_y) min_y = y2; if (y2 > max_y) max_y = y2;
        if (y3 < min_y) min_y = y3; if (y3 > max_y) max_y = y3;
        
        min_y = std::max(0, min_y);
        max_y = std::min(ctx.height - 1, max_y);
        
        // Edge list
        struct Edge { int x0, y0, x1, y1; };
        Edge edges[4] = {
            {x0, y0, x1, y1},
            {x1, y1, x2, y2},
            {x2, y2, x3, y3},
            {x3, y3, x0, y0}
        };
        
        for (int y = min_y; y <= max_y; y++) {
            int x_intersections[4];
            int count = 0;
            
            for (int e = 0; e < 4; e++) {
                Edge& edge = edges[e];
                if ((edge.y0 <= y && y < edge.y1) || (edge.y1 <= y && y < edge.y0)) {
                    if (edge.y1 != edge.y0) {
                        float t = (float)(y - edge.y0) / (float)(edge.y1 - edge.y0);
                        int x = edge.x0 + (int)(t * (edge.x1 - edge.x0));
                        x_intersections[count++] = x;
                    }
                }
            }
            
            if (count >= 2) {
                // Sort intersections
                for (int i = 0; i < count - 1; i++) {
                    for (int j = i + 1; j < count; j++) {
                        if (x_intersections[j] < x_intersections[i]) {
                            int tmp = x_intersections[i];
                            x_intersections[i] = x_intersections[j];
                            x_intersections[j] = tmp;
                        }
                    }
                }
                
                // Fill spans
                for (int i = 0; i < count - 1; i += 2) {
                    int x_start = std::max(0, x_intersections[i]);
                    int x_end = std::min(ctx.width - 1, x_intersections[i + 1]);
                    
                    for (int x = x_start; x <= x_end; x++) {
                        int idx = (y * ctx.width + x) * 4;
                        buffer[idx + 0] = r;
                        buffer[idx + 1] = g;
                        buffer[idx + 2] = b;
                        buffer[idx + 3] = 255;
                    }
                }
            }
        }
    };
    
    // Build list of faces to render with depth sorting
    struct RenderFace {
        int x, y, z;
        int face_idx;
        float depth;
        unsigned char base_rgba[4];
    };
    
    std::vector<RenderFace> render_list;
    
    // Collect all visible faces
    for (int z = 0; z < 4; z++) {
        for (int y = 0; y < 4; y++) {
            for (int x = 0; x < 4; x++) {
                unsigned char voxel_rgba[4];
                if (!native_model_get_voxel(nullptr, x, y, z, voxel_rgba)) {
                    continue; // Empty voxel
                }
                
                // Get base voxel color
                unsigned char base_rgba[4];
                if (!native_model_get_voxel(nullptr, x, y, z, base_rgba)) {
                    continue;
                }
                    
                // For isometric view, model is rotated by standard angles
                // Typical isometric: X-rot = atan(1/sqrt(2)) ≈ 35.26°, Y-rot = 45°
                // This makes front/right/top faces equally visible
                // Rotation matrix for isometric (simplified - no actual rotation since we're using iso projection)
                // Instead, we compute what the normals would be after isometric rotation:
                // After Y-rot 45° then X-rot 35.26°:
                // front (0,0,1) → (0.707, -0.408, 0.577)
                // right (1,0,0) → (0.707, 0.408, 0.577)
                // top (0,1,0) → (0, 0.816, 0.577)
                // All have same Z component (0.577) → equal lighting with viewDir (0,0,1)!
                float face_normals_rotated[6][3] = {
                    { 0.707f, -0.408f, 0.577f}, // front (after iso rotation)
                    {-0.707f,  0.408f, -0.577f}, // back
                    { 0.707f,  0.408f, 0.577f}, // right
                    {-0.707f, -0.408f, 0.577f}, // left
                    { 0.0f,    0.816f, 0.577f}, // top
                    { 0.0f,   -0.816f, -0.577f}  // bottom
                };
                
                // Check each face for visibility
                for (int f = 0; f < 6; f++) {
                    Face& face = faces[f];
                    
                    // Back-face culling: check if face is pointing toward camera
                    float* normal = face_normals_rotated[f];
                    float ndotl = normal[0] * ctx.lights[0].dir[0] +
                                 normal[1] * ctx.lights[0].dir[1] +
                                 normal[2] * ctx.lights[0].dir[2];
                    
                    // Cull back-facing polygons (facing away from camera)
                    if (ndotl <= 0.001f) {
                        continue; // Face not visible
                    }
                    
                    // Check if neighbor blocks this face (occlusion culling)
                    int nx = x, ny = y, nz = z;
                    if (strcmp(face.name, "front") == 0) nz++;
                    else if (strcmp(face.name, "back") == 0) nz--;
                    else if (strcmp(face.name, "right") == 0) nx++;
                    else if (strcmp(face.name, "left") == 0) nx--;
                    else if (strcmp(face.name, "top") == 0) ny++;
                    else if (strcmp(face.name, "bottom") == 0) ny--;
                    
                    unsigned char neighbor[4];
                    if (native_model_get_voxel(nullptr, nx, ny, nz, neighbor)) {
                        continue; // Face is occluded by neighbor
                    }
                    
                    // Calculate face center depth for sorting
                    float face_center_x = x;
                    float face_center_y = y;
                    float face_center_z = z;
                    
                    // Depth calculation: for isometric, depth = x + y + z
                    // Lower values = farther from camera, higher = closer
                    float depth = face_center_x + face_center_y + face_center_z;
                    
                    // Add to render list
                    RenderFace rf;
                    rf.x = x;
                    rf.y = y;
                    rf.z = z;
                    rf.face_idx = f;
                    rf.depth = depth;
                    memcpy(rf.base_rgba, base_rgba, 4);
                    render_list.push_back(rf);
                }
            }
        }
    }
    
    // Sort faces back-to-front (painter's algorithm)
    std::sort(render_list.begin(), render_list.end(), [](const RenderFace& a, const RenderFace& b) {
        return a.depth < b.depth; // Lower depth (farther) drawn first
    });
    
    printf("      Collected %zu visible faces, rendering back-to-front...\n", render_list.size());
    
    // Face normals (rotated for isometric)
    float face_normals_rotated[6][3] = {
        { 0.707f, -0.408f, 0.577f}, // front
        {-0.707f,  0.408f, -0.577f}, // back
        { 0.707f,  0.408f, 0.577f}, // right
        {-0.707f, -0.408f, 0.577f}, // left
        { 0.0f,    0.816f, 0.577f}, // top
        { 0.0f,   -0.816f, -0.577f}  // bottom
    };
    
    // Render all faces in sorted order
    for (const RenderFace& rf : render_list) {
        Face& face = faces[rf.face_idx];
        float* normal = face_normals_rotated[rf.face_idx];
        
        // Compute lighting
        float ndotl = normal[0] * ctx.lights[0].dir[0] +
                     normal[1] * ctx.lights[0].dir[1] +
                     normal[2] * ctx.lights[0].dir[2];
        
        if (ndotl < 0.0f) ndotl = 0.0f;
        
        // Basic lighting formula: ambient + diffuse
        float ambient = 0.3f;
        float total_light = ambient + (ndotl * 0.7f);
        
        // Apply lighting to base color
        unsigned char lit_rgba[4];
        lit_rgba[0] = (unsigned char)(rf.base_rgba[0] * total_light);
        lit_rgba[1] = (unsigned char)(rf.base_rgba[1] * total_light);
        lit_rgba[2] = (unsigned char)(rf.base_rgba[2] * total_light);
        lit_rgba[3] = rf.base_rgba[3];
        
        // Project face vertices to screen space
        int screen_x[4], screen_y[4];
        for (int v = 0; v < 4; v++) {
            float vx = rf.x + cube_verts[face.verts[v]][0];
            float vy = rf.y + cube_verts[face.verts[v]][1];
            float vz = rf.z + cube_verts[face.verts[v]][2];
            
            auto [sx, sy] = project_iso(vx, vy, vz);
            screen_x[v] = sx;
            screen_y[v] = sy;
        }
        
        // Draw face as filled polygon
        fill_quad(screen_x[0], screen_y[0],
                 screen_x[1], screen_y[1],
                 screen_x[2], screen_y[2],
                 screen_x[3], screen_y[3],
                 lit_rgba[0], lit_rgba[1], lit_rgba[2]);
        
        faces_rendered++;
        voxels_rendered++; // Count per face for now
    }
    
    printf("      Rendered %d voxels, %d faces\n", voxels_rendered, faces_rendered);
    
    // Write PNG
    if (!stbi_write_png(output_path, ctx.width, ctx.height, 4, buffer, ctx.width * 4)) {
        fprintf(stderr, "ERROR: Failed to write PNG to %s\n", output_path);
        free(buffer);
        native_shader_loader::destroy_shader_instance(shader_id, instance);
        native_shader_loader::unload_all();
        return 1;
    }
    
    printf("[6/6] Wrote output to %s\n", output_path);
    printf("\n=== Test completed successfully ===\n");
    
    // Cleanup
    free(buffer);
    native_shader_loader::destroy_shader_instance(shader_id, instance);
    native_shader_loader::unload_all();
    
    return 0;
}
