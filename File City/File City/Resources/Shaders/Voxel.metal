#include <metal_stdlib>
using namespace metal;

struct VertexIn {
    float3 position [[attribute(0)]];
    float3 normal [[attribute(1)]];
    float2 uv [[attribute(2)]];
};

struct InstanceData {
    float3 position;
    float pad0;
    float3 scale;
    float pad1;
    uint materialID;
    float highlight;
    float hover;
    int textureIndex;
};

struct Uniforms {
    float4x4 viewProjection;
};

struct VertexOut {
    float4 position [[position]];
    float3 normal;
    float2 uv;
    int textureIndex [[flat]];
    uint materialID [[flat]];
    float highlight;
    float hover;
};

vertex VertexOut vertex_main(VertexIn in [[stage_in]],
                             const device InstanceData *instances [[buffer(1)]],
                             constant Uniforms &uniforms [[buffer(2)]],
                             uint instanceID [[instance_id]]) {
    InstanceData instance = instances[instanceID];
    float3 local = in.position;
    if (local.y > 0.0) {
        float ridge = 1.0 - (abs(local.x) / 0.5);
        local.y += ridge * 0.35;
    }
    float3 scaled = local * instance.scale;
    float3 world = scaled + instance.position;
    VertexOut out;
    out.position = uniforms.viewProjection * float4(world, 1.0);
    out.normal = in.normal;
    out.uv = in.uv;
    out.textureIndex = instance.textureIndex;
    out.materialID = instance.materialID;
    out.highlight = instance.highlight;
    out.hover = instance.hover;
    return out;
}

fragment float4 fragment_main(VertexOut in [[stage_in]],
                              texture2d_array<float> textures [[texture(0)]],
                              sampler textureSampler [[sampler(0)]]) {
    float shade = saturate(dot(normalize(in.normal), float3(0.4, 0.85, 0.2)));
    float3 palette[12] = {
        float3(0.55, 0.7, 0.62),
        float3(0.76, 0.66, 0.52),
        float3(0.62, 0.6, 0.7),
        float3(0.52, 0.62, 0.78),
        float3(0.92, 0.58, 0.42),
        float3(0.86, 0.78, 0.46),
        float3(0.38, 0.66, 0.52),
        float3(0.34, 0.56, 0.72),
        float3(0.84, 0.48, 0.5),
        float3(0.66, 0.74, 0.84),
        float3(0.5, 0.52, 0.6),
        float3(0.78, 0.82, 0.64),
    };
    
    float3 baseColor = palette[in.materialID % 12];
    
    // Sample texture if index is valid (>= 0)
    if (in.textureIndex >= 0) {
        // Simple planar mapping or just use UVs passed from vertex
        // For now, let's use the UVs.
        float4 texColor = textures.sample(textureSampler, in.uv, uint(in.textureIndex));
        // DEBUG: Ignore alpha, force blend to verify texture presence
        // If texture is black/invisible, we will know.
        baseColor = texColor.rgb; 
    }
    
    float bands = floor(shade * 3.0) / 3.0;
    float light = 0.4 + 0.6 * bands;
    float3 roofColor = baseColor * 0.75 + float3(0.08, 0.1, 0.12);
    float roofMask = step(0.85, in.normal.y);
    float3 wallColor = baseColor * light;
    float3 lit = mix(wallColor, roofColor * (0.55 + 0.45 * bands), roofMask);
    float3 highlight = float3(1.0, 0.9, 0.65);
    float3 finalColor = mix(lit, highlight, saturate(in.highlight));
    float hover = saturate(in.hover);
    float rim = pow(1.0 - saturate(in.normal.y), 2.0);
    float glowStrength = hover * (0.25 + 0.45 * rim);
    float3 glowColor = float3(0.3, 0.8, 0.85);
    finalColor += glowColor * glowStrength;
    return float4(finalColor, 1.0);
}
