//
//  EField.metal
//  Maxwell
//
//  Created by Max Van den Eynde on 30/08/2026.
//

#include <metal_stdlib>
#include "../BridgingHeader.h"
#include "./MetalUtils.h"
using namespace metal;



kernel void updateEz(device GridCell* cells [[buffer(0)]], constant Uniforms& uniforms [[buffer(1)]], uint2 id [[thread_position_in_grid]]) {
    if (id.x >= uniforms.Nx || id.y >= uniforms.Ny) {
        return;
    }
    
    if (id.x == 0 || id.y == 0) {
        return;
    }
    
    uint index = gridIndex(id.x, id.y, uniforms.Nx);
    
    GridCell current = cells[index];
    
    uint indexLeft = gridIndex(id.x - 1, id.y, uniforms.Nx);
    GridCell left = cells[indexLeft];
    
    uint indexDown = gridIndex(id.x, id.y - 1, uniforms.Nx);
    GridCell down = cells[indexDown];
    
    const float epsilon0 = 8.854e-12;
    float coefficient = uniforms.dt / epsilon0;
    
    float leftDiff = (current.H.y - left.H.y) / uniforms.dx;
    float downDiff = (current.H.x - down.H.x) / uniforms.dy;
    
    current.Ez += coefficient * (leftDiff - downDiff);
    
    // Inject a source
    if (id.x == uniforms.Nx / 2 && id.y == uniforms.Ny / 2) {
        current.Ez += sin(2.0 * M_PI_F * uniforms.sourceFrequency * uniforms.t);
    }
    
    float damping = boundaryDamping(id, uniforms.Nx, uniforms.Ny, 20);
    current.Ez *= damping;
    
    cells[index] = current;
}
