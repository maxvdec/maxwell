//
//  BridgingHeader.h
//  Maxwell
//
//  Created by Max Van den Eynde on 30/08/2026.
//

#ifndef BridgingHeader_h
#define BridgingHeader_h

#include <simd/simd.h>

struct GridCell {
    float Ez;
    float2 H;
};

struct Uniforms {
    float Nx;
    float Ny;
    float dt;
    
    float dx;
    float dy;
};


#endif /* BridgingHeader_h */
