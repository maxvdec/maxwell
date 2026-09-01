//
//  FullscreenTexture.metal
//  Maxwell
//
//  Created by Max Van den Eynde on 30/08/2026.
//

#include <metal_stdlib>
using namespace metal;

struct FullscreenVertexOut {
    float4 position [[position]];
    float2 uv;
};

vertex FullscreenVertexOut fullscreenVertex(
    uint vertexID [[vertex_id]]
) {
    constexpr float2 positions[6] = {
           float2(-1.0, -1.0),
           float2( 1.0, -1.0),
           float2(-1.0,  1.0),

           float2( 1.0, -1.0),
           float2( 1.0,  1.0),
           float2(-1.0,  1.0)
       };

       constexpr float2 uvs[6] = {
           float2(0.0, 1.0),
           float2(1.0, 1.0),
           float2(0.0, 0.0),

           float2(1.0, 1.0),
           float2(1.0, 0.0),
           float2(0.0, 0.0)
       };

       FullscreenVertexOut out;

       out.position =
           float4(
               positions[vertexID],
               0.0,
               1.0
           );

       out.uv =
           uvs[vertexID];

       return out;
}

struct FullscreenFragmentOut {
    float4 color [[color(0)]];
};

fragment FullscreenFragmentOut fullscreenFragment(
    FullscreenVertexOut in [[stage_in]],
    texture2d<float> renderTexture [[texture(0)]]
) {
    constexpr sampler renderSampler(
        mag_filter::linear,
        min_filter::linear,
        address::clamp_to_edge
    );

    FullscreenFragmentOut out;
    out.color = renderTexture.sample(
            renderSampler,
            in.uv
        );
    return out;
}

kernel void gaussianBlurHorizontal(
    texture2d<float, access::read> inputTexture [[texture(0)]],
    texture2d<float, access::write> outputTexture [[texture(1)]],
    constant float* weights [[buffer(0)]],
    constant uint& radius [[buffer(1)]],
    uint2 id [[thread_position_in_grid]]
) {
    if (id.x >= outputTexture.get_width() ||
        id.y >= outputTexture.get_height()) {
        return;
    }

    float4 result = float4(0.0);

    int width = int(inputTexture.get_width());

    for (int offset = -int(radius); offset <= int(radius); offset++) {
        int sampleX = clamp(
            int(id.x) + offset,
            0,
            width - 1
        );

        uint weightIndex = uint(abs(offset));

        result += inputTexture.read(
            uint2(uint(sampleX), id.y)
        ) * weights[weightIndex];
    }

    outputTexture.write(result, id);
}

kernel void gaussianBlurVertical(
    texture2d<float, access::read> inputTexture [[texture(0)]],
    texture2d<float, access::write> outputTexture [[texture(1)]],
    constant float* weights [[buffer(0)]],
    constant uint& radius [[buffer(1)]],
    uint2 id [[thread_position_in_grid]]
) {
    if (id.x >= outputTexture.get_width() ||
        id.y >= outputTexture.get_height()) {
        return;
    }

    float4 result = float4(0.0);

    int height = int(inputTexture.get_height());

    for (int offset = -int(radius); offset <= int(radius); offset++) {
        int sampleY = clamp(
            int(id.y) + offset,
            0,
            height - 1
        );

        uint weightIndex = uint(abs(offset));

        result += inputTexture.read(
            uint2(id.x, uint(sampleY))
        ) * weights[weightIndex];
    }

    outputTexture.write(result, id);
}

struct ImageOverlayVertex {
    float2 position;
    float2 uv;
};

struct ImageOverlayOut {
    float4 position [[position]];
    float2 uv;
};

vertex ImageOverlayOut imageOverlayVertex(
    const device ImageOverlayVertex* vertices [[buffer(0)]],
    uint vertexID [[vertex_id]]
) {
    ImageOverlayOut out;

    out.position = float4(
        vertices[vertexID].position,
        0.0,
        1.0
    );

    out.uv = vertices[vertexID].uv;

    return out;
}

fragment float4 imageOverlayFragment(
    ImageOverlayOut in [[stage_in]],
    texture2d<float> sourceTexture [[texture(0)]],
    constant float& opacity [[buffer(0)]]
) {
    constexpr sampler sourceSampler(
        min_filter::linear,
        mag_filter::linear
    );

    float4 color =
        sourceTexture.sample(
            sourceSampler,
            in.uv
        );

    color.a *= opacity;

    return color;
}
