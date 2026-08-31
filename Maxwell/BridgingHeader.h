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
    float previousEz;
    simd_float2 H;
};

struct Uniforms {
    unsigned int Nx;
    unsigned int Ny;
    float dt;
    
    float dx;
    float dy;
    
    float visualizationScale;
    
    float t;
    float sourceFrequency;
    
    unsigned int reflectingWalls;
};


#endif /* BridgingHeader_h */
