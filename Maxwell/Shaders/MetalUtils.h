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

inline float pmlDepth(
    uint p,
    uint size,
    uint thickness
) {
    if (p < thickness) {
        return float(thickness - p) / float(thickness);
    }

    if (p >= size - thickness) {
        return float(p - (size - thickness - 1))
             / float(thickness);
    }

    return 0.0;
}

inline float calculateSigmaMax(float pmlPhysical) {
    float R = 1e-6;
    float m = 3;
    float eta0 = 377; // ohms
    return - ((m + 1) * log(R) / 2 * eta0 * pmlPhysical);
}

#endif /* MetalUtils_h */
