#include <metal_stdlib>
using namespace metal;

kernel void extractEnergyBloom(
    texture2d<float, access::read> energyTexture [[texture(0)]],
    texture2d<float, access::write> bloomTexture [[texture(1)]],
    constant float& threshold [[buffer(0)]],
    uint2 id [[thread_position_in_grid]]
) {
    if (id.x >= bloomTexture.get_width() ||
        id.y >= bloomTexture.get_height()) {
        return;
    }

    float4 energy = energyTexture.read(id);
    float brightness = max(energy.r, energy.g);
    float knee = smoothstep(threshold, threshold + 0.18f, brightness);
    bloomTexture.write(float4(energy.rg * knee, 0.0f, 1.0f), id);
}

kernel void compositeEnergyGlow(
    texture2d<float, access::read> energyTexture [[texture(0)]],
    texture2d<float, access::read> bloomTexture [[texture(1)]],
    texture2d<float, access::write> outputTexture [[texture(2)]],
    uint2 id [[thread_position_in_grid]]
) {
    if (id.x >= outputTexture.get_width() ||
        id.y >= outputTexture.get_height()) {
        return;
    }

    float2 energy = energyTexture.read(id).rg;
    float2 bloom = bloomTexture.read(id).rg;

    constexpr float3 electricWhite = float3(1.0f, 0.94f, 0.88f);
    constexpr float3 magneticWhite = float3(0.88f, 0.94f, 1.0f);

    float3 sharp =
        energy.r * electricWhite +
        energy.g * magneticWhite;

    float3 glow =
        bloom.r * electricWhite +
        bloom.g * magneticWhite;

    float3 color = 1.0f - exp(-(sharp + glow * 2.35f));
    outputTexture.write(float4(saturate(color), 1.0f), id);
}
