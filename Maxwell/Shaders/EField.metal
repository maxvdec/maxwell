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
    FORM_GAUSSIAN = 2,
    FORM_GAUSSIAN_MODULATED = 3
};

enum SourceType : uint {
    TYPE_LINE = 0,
    TYPE_POINT = 1,
    TYPE_BEAM = 2,
};
    
float valueForSource(ElectricSource source, constant Uniforms& uniforms) {
    if (source.form == FORM_SINE) {
        float frequencyHz = source.frequency * 1e9;
        return source.amplitude * sin(2.0 * M_PI_F * frequencyHz * uniforms.t + source.phase);
    } else if (source.form == FORM_PULSE) {
        float frequencyHz = source.frequency * 1e9;
        if (uniforms.t < (source.duration / 1e9)) {
            return source.amplitude * sin(2.0 * M_PI_F * frequencyHz * uniforms.t + source.phase);
        }
    } else if (source.form == FORM_GAUSSIAN) {
        float sigma = (source.gaussianWidth / 1e9) / 2.35482;
        float t0 = 4 * sigma;
        return source.amplitude * exp(-1 * (pow(uniforms.t - t0, 2) / (2 * pow(sigma, 2))));
    } else if (source.form == FORM_GAUSSIAN_MODULATED) {
        float sigma = (source.gaussianWidth / 1e9) / 2.35482;
        float t0 = 4 * sigma;
        float gaussian = exp(-1 * (pow(uniforms.t - t0, 2) / (2 * pow(sigma, 2))));
        float frequencyHz = source.frequency * 1e9;
        float sine = sin(2 * M_PI_F * frequencyHz * (uniforms.t - t0) + source.phase);
        return source.amplitude * gaussian * sine;
    }
    
    return 0;
}

float sourceContribution(uint2 id, constant ElectricSource* sources, constant Uniforms& uniforms) {
    float contribution = 0.0;
    
    for (uint i = 0; i < uniforms.sourceCount; i++) {
        ElectricSource source = sources[i];        
        
        if (source.type == TYPE_POINT) {
                   uint simX = source.x + uniforms.pmlThickness;
                   uint simY = source.y + uniforms.pmlThickness;

                   if (id.x == simX && id.y == simY) {
                       contribution += valueForSource(
                           source,
                           uniforms
                       );
                   }
               }

        else if (source.type == TYPE_LINE || source.type == TYPE_BEAM) {
            float2 center = float2(
                                   source.x + uniforms.pmlThickness,
                                   source.y + uniforms.pmlThickness
                                   );
            
            float angle =
            source.rotation * M_PI_F / 180.0f;
            
            float2 direction = float2(
                                      cos(angle),
                                      sin(angle)
                                      );
            
            float halfWidth =
            float(source.length) * 0.5f;
            
            float2 a =
            center - direction * halfWidth;
            
            float2 b =
            center + direction * halfWidth;
            
            float2 p = float2(id);
            
            float2 ab = b - a;
            float2 ap = p - a;
            
            float abLengthSquared = dot(ab, ab);
            
            if (abLengthSquared > 0.0f) {
                float projection = dot(ap, ab) / abLengthSquared;
                
                float distance = abs(ab.x * ap.y - ab.y * ap.x) / sqrt(abLengthSquared);
                
                if (projection >= 0.0f && projection <= 1.0f && distance <= 0.75f) {
                    if (source.type == TYPE_LINE) {
                        contribution += valueForSource(source,uniforms);
                    } else {
                        float positionAlong = (projection - 0.5) * float(source.length);
                        
                        float waist = source.beamWaist;
                        
                        float profile = exp(-(positionAlong * positionAlong) / (waist * waist));
                        contribution += valueForSource(source, uniforms) * profile;
                    }
                }
            }
        }
    }
    
    return contribution;
}


kernel void updateEz(device GridCell* cells [[buffer(0)]],
                     constant Uniforms& uniforms [[buffer(1)]],
                     constant ElectricSource* sources [[buffer(2)]],
                     constant EMMaterial* materials [[buffer(3)]],
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
    float epslion = 0.0;
    float sigmaMaterial = 0.0;
    if (current.materialIndex >= uniforms.materialCount) {
        epslion = epsilon0;
    } else {
        EMMaterial mat = materials[current.materialIndex];
        epslion = mat.epsilonR * epsilon0;
        sigmaMaterial = mat.sigma;
    }
    
    float leftDiff = (current.H.y - left.H.y) / uniforms.dx;
    float downDiff = (current.H.x - down.H.x) / uniforms.dy;
    
    float depthX = pmlDepth(id.x, uniforms.Nx, uniforms.pmlThickness);
    float depthY = pmlDepth(id.y, uniforms.Ny, uniforms.pmlThickness);
    
    float sigmaX = uniforms.sigmaMaxX * pow(depthX, 3);
    float sigmaY = uniforms.sigmaMaxY * pow(depthY, 3);
    
    float sigmaE = sigmaX + sigmaY;
    float sigma = sigmaMaterial + sigmaE;
    
    float lossE = sigma * uniforms.dt / (2.0f * epslion);
    float caE = (1.0f - lossE) / (1.0f + lossE);
    float cbE = (uniforms.dt / epslion) / (1.0 + lossE);
    
    current.Ez = caE * current.Ez + cbE * (leftDiff - downDiff);
    
    current.Ez += sourceContribution(id, sources, uniforms);
    
    cells[index] = current;
}
