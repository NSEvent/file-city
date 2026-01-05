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
    uint3 pad2;
};

struct Uniforms {
    float4x4 viewProjection;
};

struct VertexOut {
    float4 position [[position]];
    float3 normal;
    uint materialID;
};

vertex VertexOut vertex_main(VertexIn in [[stage_in]],
                             const device InstanceData *instances [[buffer(1)]],
                             constant Uniforms &uniforms [[buffer(2)]],
                             uint instanceID [[instance_id]]) {
    InstanceData instance = instances[instanceID];
    float3 scaled = in.position * instance.scale;
    float3 world = scaled + instance.position;
    VertexOut out;
    out.position = uniforms.viewProjection * float4(world, 1.0);
    out.normal = in.normal;
    out.materialID = instance.materialID;
    return out;
}

fragment float4 fragment_main(VertexOut in [[stage_in]]) {
    float shade = saturate(dot(normalize(in.normal), float3(0.4, 0.8, 0.2)));
    float base = 0.35 + 0.6 * shade;
    return float4(base, base, base, 1.0);
}
