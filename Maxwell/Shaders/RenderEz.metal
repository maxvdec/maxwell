//
//  RenderEz.metal
//  Maxwell
//
//  Created by Max Van den Eynde on 30/08/2026.
//

#include <metal_stdlib>
#include "../BridgingHeader.h"
using namespace metal;

kernel void renderEz(
    texture2d<float, access::write> outTexture [[texture(0)]],
    device GridCell* cells [[buffer(0)]],
    constant Uniforms& uniforms [[buffer(1)]],
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
    
    float ez = cells[index].Ez;
    
    float v = clamp(ez * uniforms.visualizationScale, -1.0, 1.0);

    float3 negativeColor = float3(0.1, 0.3, 1.0);
    float3 positiveColor = float3(1.0, 0.15, 0.05);

    float3 color =
        v < 0.0
        ? negativeColor * -v
        : positiveColor * v;

    outTexture.write(float4(color.x, color.y, color.z, 1.0), id);
}
