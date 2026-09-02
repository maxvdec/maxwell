//
//  RenderEz.metal
//  Maxwell
//
//  Created by Max Van den Eynde on 30/08/2026.
//

#include <metal_stdlib>
#include "../BridgingHeader.h"
using namespace metal;

enum VisualizationMode : int {
    MODE_EZ = 0,
    MODE_MAGNITUDE = 1,
    MODE_MAGNETIC_MAGNITUDE = 2,
    MODE_ELECTRIC_DENSITY = 3,
    MODE_ENERGY_GLOW = 4,
};

kernel void renderEz(
    texture2d<float, access::write> outTexture [[texture(0)]],
    device GridCell* cells [[buffer(0)]],
    constant Uniforms& uniforms [[buffer(1)]],
    constant EMMaterial* materials [[buffer(2)]],
    uint2 id [[thread_position_in_grid]]
) {
    if (id.x >= outTexture.get_width() ||
        id.y >= outTexture.get_height()) {
        return;
    }

    float2 uv = float2(id) / float2(
        outTexture.get_width(),
        outTexture.get_height()
    );
    
    uint visibleNx =
        uniforms.Nx - 2 * uniforms.pmlThickness;

    uint visibleNy =
        uniforms.Ny - 2 * uniforms.pmlThickness;
    
    uint x =
        uniforms.pmlThickness
        + min(
            uint(uv.x * visibleNx),
            visibleNx - 1
        );

    uint y =
        uniforms.pmlThickness
        + min(
            uint(uv.y * visibleNy),
            visibleNy - 1
        );
    
    uint index = y * uniforms.Nx + x;
    
    uint indexDown = (y - 1) * uniforms.Nx + x;
    uint indexLeft = y * uniforms.Nx + (x - 1);
    
    float ez = cells[index].Ez;
    float2 h = cells[index].H;
    float2 hDown = cells[indexDown].H;
    float2 hLeft = cells[indexLeft].H;
    
    int materialIndex = cells[index].materialIndex;
    if (materialIndex >= uniforms.materialCount) {
        outTexture.write(float4(1.0, 0.0, 1.0, 1.0), id);
        return;
    }
    
    EMMaterial mat = materials[cells[index].materialIndex];
    
    if (uniforms.visualizationMode == MODE_EZ) {
        float x = ez * uniforms.visualizationScale;

        float v = sign(x) * log(1.0 + abs(x));
        v /= log(1.0 + 10.0);
        v = clamp(v, -1.0, 1.0);

        float3 negativeColor = float3(0.1, 0.3, 1.0);
        float3 positiveColor = float3(1.0, 0.15, 0.05);

        float3 color =
            v < 0.0
            ? negativeColor * -v
            : positiveColor * v;

        outTexture.write(float4(color, 1.0), id);
    } else if (uniforms.visualizationMode == MODE_MAGNITUDE) {
        float x = abs(ez) * uniforms.visualizationScale;

        float v = log(1.0 + x);
        v /= log(1.0 + 10.0);
        v = clamp(v, 0.0, 1.0);

        outTexture.write(float4(v, v, v, 1.0), id);
    } else if (uniforms.visualizationMode == MODE_MAGNETIC_MAGNITUDE) {
        constexpr float Z0 = 376.730313668f;

        float hx = 0.5 * (h.x + hDown.x);
        float hy = 0.5 * (h.y + hLeft.y);

        float hMagnitude =
            length(float2(hx, hy))
            * Z0
            * uniforms.visualizationScale;
        
        float v = log(1.0 + hMagnitude);
        v /= log(1.0 + 10.0);
        v = clamp(v, 0.0, 1.0);
        
        outTexture.write(float4(v, v, v, 1.0), id);
    } else if (uniforms.visualizationMode == MODE_ELECTRIC_DENSITY) {
        const float epsilon0 = 8.854187817e-12f;
        float epsilon = epsilon0 * mat.epsilonR;

        float electricEnergy = 0.5f * epsilon * ez * ez;

        // Display gain, not physical scaling
        float x = electricEnergy * 1e12f * uniforms.visualizationScale;

        float v = log(1.0f + x);
        v /= log(1.0f + 10.0f);
        v = clamp(v, 0.0f, 1.0f);

        outTexture.write(float4(v, v, v, 1.0f), id);
    } else if (uniforms.visualizationMode == MODE_ENERGY_GLOW) {
        const float epsilon0 = 8.854187817e-12f;
        const float mu0 = 1.25663706212e-6f;

        float hx = 0.5f * (h.x + hDown.x);
        float hy = 0.5f * (h.y + hLeft.y);

        float electricEnergy =
            0.5f * epsilon0 * mat.epsilonR * ez * ez;

        float magneticEnergy =
            0.5f * mu0 * mat.muR *
            dot(float2(hx, hy), float2(hx, hy));

        float exposure = 1e12f * uniforms.visualizationScale;
        float electric = 1.0f - exp(-electricEnergy * exposure);
        float magnetic = 1.0f - exp(-magneticEnergy * exposure);

        outTexture.write(
            float4(electric, magnetic, 0.0f, 1.0f),
            id
        );
    } else {
        outTexture.write(float4(1.0, 0.0, 1.0, 1.0), id);
    }
}
