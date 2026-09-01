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

enum SourceForm : uint {
    FORM_SINE = 0,
    FORM_PULSE = 1,
    FORM_GAUSSIAN = 2
};

enum SourceType : uint {
    TYPE_LINE = 0,
    TYPE_POINT = 1,
    TYPE_BEAM = 2,
};

float sourceContribution(uint2 id, constant ElectricSource* sources, constant Uniforms& uniforms) {
    float contribution = 0.0;
    
    for (uint i = 0; i < uniforms.sourceCount; i++) {
        ElectricSource source = sources[i];
        
        uint simX = source.x + uniforms.pmlThickness;
        uint simY = source.y + uniforms.pmlThickness;
        
        if (id.x == simX && id.y == simY) {
            // Just handle point, sine functions
            if (source.type == TYPE_POINT && source.form == FORM_SINE) {
                float frequencyHz = source.frequency * 1e9;
                contribution += source.amplitude * sin(2.0 * M_PI_F * frequencyHz * uniforms.t + source.phase);
            }
        }
    }
    
    return contribution;
}


kernel void updateEz(device GridCell* cells [[buffer(0)]],
                     constant Uniforms& uniforms [[buffer(1)]],
                     constant ElectricSource* sources [[buffer(2)]],
                     uint2 id [[thread_position_in_grid]]) {
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
    
    float sigmaX = uniforms.sigmaMaxX * pow(depthX, 3);
    float sigmaY = uniforms.sigmaMaxY * pow(depthY, 3);
    
    float sigmaE = sigmaX + sigmaY;
    
    float lossE = sigmaE * uniforms.dt / (2.0f * epsilon0);
    float caE = (1.0f - lossE) / (1.0f + lossE);
    float cbE = (uniforms.dt / epsilon0) / (1.0 + lossE);
    
    current.Ez = caE * current.Ez + cbE * (leftDiff - downDiff);
    
    current.Ez += sourceContribution(id, sources, uniforms);
    
    cells[index] = current;
}
