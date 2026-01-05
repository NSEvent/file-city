#include <metal_stdlib>
using namespace metal;

struct VertexIn {
    float3 position [[attribute(0)]];
    float3 normal [[attribute(1)]];
};

struct InstanceData {
    float3 position;
    float pad0;
    float3 scale;
    float pad1;
    uint materialID;
    float highlight;
    float hover;
    uint pad2;
};

struct Uniforms {
    float4x4 viewProjection;
};

struct VertexOut {
    float4 position [[position]];
    float3 normal;
    uint materialID;
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
    out.materialID = instance.materialID;
    out.highlight = instance.highlight;
    out.hover = instance.hover;
    return out;
}

fragment float4 fragment_main(VertexOut in [[stage_in]]) {
    float shade = saturate(dot(normalize(in.normal), float3(0.4, 0.8, 0.2)));
    float3 palette[12] = {
        float3(0.18, 0.62, 0.84),
        float3(0.94, 0.58, 0.2),
        float3(0.2, 0.72, 0.46),
        float3(0.85, 0.28, 0.36),
        float3(0.55, 0.4, 0.85),
        float3(0.95, 0.84, 0.25),
        float3(0.25, 0.75, 0.85),
        float3(0.92, 0.36, 0.58),
        float3(0.4, 0.78, 0.35),
        float3(0.8, 0.5, 0.35),
        float3(0.35, 0.45, 0.9),
        float3(0.78, 0.78, 0.86),
    };
    float3 baseColor = palette[in.materialID % 12];
    float3 roofColor = float3(0.28, 0.2, 0.2);
    float roofMask = step(0.85, in.normal.y);
    float3 wallColor = baseColor * (0.35 + 0.65 * shade);
    float3 lit = mix(wallColor, roofColor * (0.5 + 0.5 * shade), roofMask);
    float3 highlight = float3(1.0, 0.88, 0.35);
    float3 finalColor = mix(lit, highlight, saturate(in.highlight));
    float hover = saturate(in.hover);
    float rim = pow(1.0 - saturate(in.normal.y), 2.0);
    float glowStrength = hover * (0.4 + 0.6 * rim);
    float3 glowColor = float3(0.28, 0.9, 1.0);
    finalColor += glowColor * glowStrength;
    return float4(finalColor, 1.0);
}
