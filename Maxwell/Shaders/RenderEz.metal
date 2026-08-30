//
//  RenderEz.metal
//  Maxwell
//
//  Created by Max Van den Eynde on 30/08/2026.
//

#include <metal_stdlib>
using namespace metal;

kernel void renderEz(
    texture2d<float, access::write> outTexture [[texture(0)]],
    uint2 id [[thread_position_in_grid]]
) {
    if (id.x >= outTexture.get_width() ||
        id.y >= outTexture.get_height()) {
        return;
    }

    float2 uv = float2(id) / float2(
        outTexture.get_width() - 1,
        outTexture.get_height() - 1
    );

    outTexture.write(float4(uv.x, uv.y, 0.0, 1.0), id);
}
