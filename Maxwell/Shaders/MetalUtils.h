//
//  MetalUtils.h
//  Maxwell
//
//  Created by Max Van den Eynde on 31/08/2026.
//

#ifndef MetalUtils_h
#define MetalUtils_h

#include <metal_stdlib>
using namespace metal;

inline uint gridIndex(uint x, uint y, uint Nx) {
    return y * Nx + x;
}

inline float boundaryDamping(
    uint2 id,
    uint Nx,
    uint Ny,
    uint thickness
) {
    uint dx = min(id.x, Nx - 1 - id.x);
    uint dy = min(id.y, Ny - 1 - id.y);

    uint d = min(dx, dy);

    if (d >= thickness) {
        return 1.0;
    }

    float t = float(thickness - d) / float(thickness);

    float strength = 0.4;

    return exp(-strength * t * t);
}

#endif /* MetalUtils_h */
