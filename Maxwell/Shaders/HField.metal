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
    
    const float mu0 = 1.25663706212e-6f;
    const float epsilon0 = 8.854187817e-12f;
    
    float depthX = pmlDepth(id.x, uniforms.Nx, uniforms.pmlThickness);
    float depthY = pmlDepth(id.y, uniforms.Ny, uniforms.pmlThickness);
    
    float ezDiffY = (up.Ez - cell.Ez) / uniforms.dy;
    float sigmaEY = uniforms.sigmaMaxY * pow(depthY, 3);
    float sigmaMY = sigmaEY * mu0 / epsilon0;
    
    float lossHx = sigmaMY * uniforms.dt / (2.0f * mu0);
    float caHx = (1.0f - lossHx) / (1.0f + lossHx);
    float cbHx = (uniforms.dt / mu0) / (1.0 + lossHx);
    
    cell.H.x = caHx * cell.H.x - cbHx * ezDiffY;
    
    float ezDiffX = (right.Ez - cell.Ez) / uniforms.dx;
    float sigmaEX = uniforms.sigmaMaxX * pow(depthX, 3);
    float sigmaMX = sigmaEX * mu0 / epsilon0;
    
    float lossHy = sigmaMX * uniforms.dt / (2.0f * mu0);
    float caHy = (1.0f - lossHy) / (1.0f + lossHy);
    float cbHy = (uniforms.dt / mu0) / (1.0 + lossHy);
    
    cell.H.y = caHy * cell.H.y + cbHy * ezDiffX;
    
    cells[index] = cell;
}


