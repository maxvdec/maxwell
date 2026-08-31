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
    
    const float epsilon0 = 8.854187817e-12f;
    
    float leftDiff = (current.H.y - left.H.y) / uniforms.dx;
    float downDiff = (current.H.x - down.H.x) / uniforms.dy;
    
    float depthX = pmlDepth(id.x, uniforms.Nx, uniforms.pmlThickness);
    float depthY = pmlDepth(id.y, uniforms.Ny, uniforms.pmlThickness);
    
    float pmlPhysicalWidthX = float(uniforms.pmlThickness) * uniforms.dx;
    float sigmaMaxX = calculateSigmaMax(pmlPhysicalWidthX);
    float pmlPhysicalWidthY = float(uniforms.pmlThickness) * uniforms.dy;
    float sigmaMaxY = calculateSigmaMax(pmlPhysicalWidthY);
    
    float sigmaX = sigmaMaxX * pow(depthX, 3);
    float sigmaY = sigmaMaxY * pow(depthY, 3);
    
    float sigmaE = sigmaX + sigmaY;
    
    float lossE = sigmaE * uniforms.dt / (2.0f * epsilon0);
    float caE = (1.0f - lossE) / (1.0f + lossE);
    float cbE = (uniforms.dt / epsilon0) / (1.0 + lossE);
    
    current.Ez = caE * current.Ez + cbE * (leftDiff - downDiff);
    
    if (id.x == uniforms.Nx / 2 && id.y == uniforms.Ny / 2) {
        current.Ez += sin(2.0 * M_PI_F * uniforms.sourceFrequency * uniforms.t);
    }
    
    cells[index] = current;
}
