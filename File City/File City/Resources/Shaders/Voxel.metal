#include <metal_stdlib>
using namespace metal;

struct VertexIn {
    float3 position [[attribute(0)]];
    float3 normal [[attribute(1)]];
    uint materialID [[attribute(2)]];
};

vertex float4 vertex_main(const VertexIn in [[stage_in]]) {
    return float4(in.position, 1.0);
}

fragment float4 fragment_main() {
    return float4(1.0, 1.0, 1.0, 1.0);
}
