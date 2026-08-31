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

#endif /* MetalUtils_h */
