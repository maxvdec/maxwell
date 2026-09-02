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
    simd_float2 H;
};

struct ElectricSource {
    unsigned int x; // cells
    unsigned int y; // cells
    
    unsigned int width; // cells
    float rotation; // degrees
    
    float frequency; // GHz
    float amplitude; // V/m
    float phase; // rad
    unsigned int type; // 0 -> line, 1 -> point, 2 -> beam
    unsigned int form; // 0 -> sine, 1 -> pulse, 2 -> gaussian burst, 3 -> gaussian-modulated
    
    float duration; // nanoseconds
    float gaussianWidth; // nanoseconds
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
    
    unsigned int pmlThickness;
    
    unsigned int sourceCount;
    
    float sigmaMaxX;
    float sigmaMaxY;
};


#endif /* BridgingHeader_h */
