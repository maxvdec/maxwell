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
    if (id.x == uniforms.Nx - 1 || id.y == uniforms.Ny - 1) {
        return;
    }
    
    if (id.x == 0 || id.y == 0) {
        return;
    }
    
    uint index = gridIndex(id.x, id.y, uniforms.Nx);
    
    GridCell current = cells[index];
    current.previousEz = current.Ez;
    
    uint indexLeft = gridIndex(id.x - 1, id.y, uniforms.Nx);
    GridCell left = cells[indexLeft];
    
    uint indexDown = gridIndex(id.x, id.y - 1, uniforms.Nx);
    GridCell down = cells[indexDown];
    
    const float epsilon0 = 8.854e-12;
    float coefficient = uniforms.dt / epsilon0;
    
    float leftDiff = (current.H.y - left.H.y) / uniforms.dx;
    float downDiff = (current.H.x - down.H.x) / uniforms.dy;
    
    current.Ez += coefficient * (leftDiff - downDiff);

    
    if (id.x == uniforms.Nx / 2 && id.y == uniforms.Ny / 2) {
        current.Ez += sin(2.0 * M_PI_F * uniforms.sourceFrequency * uniforms.t);
    }
    
    cells[index] = current;
}

kernel void absorbEzBoundary(
    device GridCell* cells [[buffer(0)]],
    constant Uniforms& uniforms [[buffer(1)]],
    uint id [[thread_position_in_grid]]
) {
    const float c = 299792458.0f;

    float kx =
        (c * uniforms.dt - uniforms.dx)
        / (c * uniforms.dt + uniforms.dx);

    float ky =
        (c * uniforms.dt - uniforms.dy)
        / (c * uniforms.dt + uniforms.dy);

    if (id < uniforms.Ny) {
        uint y = id;

        if (y > 0 && y < uniforms.Ny - 1) {
            uint boundary = gridIndex(0, y, uniforms.Nx);
            uint inside   = gridIndex(1, y, uniforms.Nx);

            float oldBoundary = cells[boundary].previousEz;
            float oldInside   = cells[inside].previousEz;
            float newInside   = cells[inside].Ez;

            cells[boundary].Ez =
                oldInside
                + kx * (newInside - oldBoundary);

            boundary = gridIndex(uniforms.Nx - 1, y, uniforms.Nx);
            inside   = gridIndex(uniforms.Nx - 2, y, uniforms.Nx);

            oldBoundary = cells[boundary].previousEz;
            oldInside   = cells[inside].previousEz;
            newInside   = cells[inside].Ez;

            cells[boundary].Ez =
                oldInside
                + kx * (newInside - oldBoundary);
        }
    }

    if (id < uniforms.Nx) {
        uint x = id;

        if (x > 0 && x < uniforms.Nx - 1) {
            uint boundary = gridIndex(x, 0, uniforms.Nx);
            uint inside   = gridIndex(x, 1, uniforms.Nx);

            float oldBoundary = cells[boundary].previousEz;
            float oldInside   = cells[inside].previousEz;
            float newInside   = cells[inside].Ez;

            cells[boundary].Ez =
                oldInside
                + ky * (newInside - oldBoundary);

            boundary = gridIndex(x, uniforms.Ny - 1, uniforms.Nx);
            inside   = gridIndex(x, uniforms.Ny - 2, uniforms.Nx);

            oldBoundary = cells[boundary].previousEz;
            oldInside   = cells[inside].previousEz;
            newInside   = cells[inside].Ez;

            cells[boundary].Ez =
                oldInside
                + ky * (newInside - oldBoundary);
        }
    }
}
