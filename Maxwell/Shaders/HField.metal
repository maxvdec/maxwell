//
//  HField.metal
//  Maxwell
//
//  Created by Max Van den Eynde on 31/08/2026.
//

#include <metal_stdlib>
#include "../BridgingHeader.h"
#include "./MetalUtils.h"
using namespace metal;

kernel void updateH(device GridCell* cells [[buffer(0)]], constant Uniforms& uniforms [[buffer(1)]], uint2 id [[thread_position_in_grid]]) {
    if (id.x >= uniforms.Nx - 1 || id.y >= uniforms.Ny - 1) {
        return;
    }
    
    if (all(id == 0)) {
        return;
    }

    uint index = gridIndex(id.x, id.y, uniforms.Nx);
    
    GridCell cell = cells[index];
    
    uint indexUp = gridIndex(id.x, id.y + 1, uniforms.Nx);
    uint indexRight = gridIndex(id.x + 1, id.y, uniforms.Nx);
    
    GridCell up = cells[indexUp];
    GridCell right = cells[indexRight];
    
    const float mu0 = 1.254e-6;
    float coeffY = uniforms.dt / (mu0 * uniforms.dy);
    float coeffX = uniforms.dt / (mu0 * uniforms.dx);
    
    cell.H.x -= coeffY * (up.Ez - cell.Ez);
    cell.H.y += coeffX * (right.Ez - cell.Ez);
    
    float damping = boundaryDamping(id, uniforms.Nx, uniforms.Ny, 20);
    cell.H *= damping;
    
    cells[index] = cell;
}


