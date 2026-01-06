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
    float rotationY;
    float pad2;
    uint materialID;
    float highlight;
    float hover;
    int textureIndex;
    int shapeID;
};

struct Uniforms {
    float4x4 viewProjection;
    float time;
    float3 pad;
};

struct VertexOut {
    float4 position [[position]];
    float3 normal;
    float2 uv;
    float3 scale [[flat]];
    int textureIndex [[flat]];
    uint materialID [[flat]];
    int shapeID [[flat]];
    float highlight;
    float hover;
};

vertex VertexOut vertex_main(VertexIn in [[stage_in]],
                             const device InstanceData *instances [[buffer(1)]],
                             constant Uniforms &uniforms [[buffer(2)]],
                             uint instanceID [[instance_id]]) {
    InstanceData instance = instances[instanceID];
    float3 local = in.position;
    
    // Apply shape deformations
    if (instance.shapeID == 5) {
        float radius = length(local.xz);
        float maxRadius = 0.5;
        if (radius > maxRadius) {
            float scale = maxRadius / radius;
            local.x *= scale;
            local.z *= scale;
        }
    } else if (instance.shapeID == 6) {
        float wingBand = 0.35;
        float wingScale = 3.6;
        float bodyScaleZ = 0.25;
        float bodyScaleX = 0.7;
        if (abs(local.y) < wingBand) {
            // Wings extend perpendicular to body (Z axis)
            local.x *= 0.5;
            local.z *= wingScale;
        } else {
            local.x *= bodyScaleX;
            local.z *= bodyScaleZ;
        }
    } else if (instance.shapeID == 7) {
        float t = saturate((local.x + 0.5));
        float shrink = 1.0 - t;
        local.y *= (0.3 + 0.7 * shrink);
        local.z *= (0.3 + 0.7 * shrink);
        local.x *= 1.2;
    } else if (instance.shapeID > 0 && local.y > 0.0) {
        if (instance.shapeID == 1) {
            // Tapered Spire
            local.x *= 0.4;
            local.z *= 0.4;
            local.y += 0.5;
        } else if (instance.shapeID == 2) {
            // Pyramid Point
            local.x = 0.0;
            local.z = 0.0;
            local.y += 0.5;
        } else if (instance.shapeID == 3) {
            // Slant X
            local.y += local.x * 1.5;
        } else if (instance.shapeID == 4) {
            // Slant Z
            local.y += local.z * 1.5;
        }
    }

    float3 scaled = local * instance.scale;
    if (instance.rotationY != 0.0) {
        float c = cos(instance.rotationY);
        float s = sin(instance.rotationY);
        float x = scaled.x * c - scaled.z * s;
        float z = scaled.x * s + scaled.z * c;
        scaled.x = x;
        scaled.z = z;
    }

    float3 world = scaled + instance.position;
    VertexOut out;
    out.position = uniforms.viewProjection * float4(world, 1.0);
    float3 normal = in.normal;
    if (instance.rotationY != 0.0) {
        float c = cos(instance.rotationY);
        float s = sin(instance.rotationY);
        float nx = normal.x * c - normal.z * s;
        float nz = normal.x * s + normal.z * c;
        normal.x = nx;
        normal.z = nz;
    }
    out.normal = normal;
    out.uv = in.uv;
    out.scale = instance.scale;
    out.textureIndex = instance.textureIndex;
    out.materialID = instance.materialID;
    out.shapeID = instance.shapeID;
    out.highlight = instance.highlight;
    out.hover = instance.hover;
    return out;
}

fragment float4 fragment_main(VertexOut in [[stage_in]],
                              constant Uniforms &uniforms [[buffer(2)]],
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

    if (in.shapeID == 7) {
        float flicker = 0.75 + 0.25 * sin((in.uv.x + in.uv.y) * 28.0);
        float heat = saturate(in.hover);
        baseColor = float3(1.0, 0.45, 0.1) * (0.6 + 0.4 * flicker) * (0.6 + 0.8 * heat);
    }
    
    // Sample texture if index is valid (>= 0)
    if (in.textureIndex >= 0) {
        float3 normal = abs(in.normal);
        
        // Calculate UVs based on world position (scaled)
        // We use the vertex UVs which are 0..1 per face, but they stretch.
        // Instead, let's use the object-space UVs adjusted by scale to tile correctly.
        // Or simpler: Just multiply UV by relevant scale dimensions.
        
        float2 tiledUV = in.uv;
        
        // Determine which face we are on based on normal
        // Normals are roughly: (1,0,0), (-1,0,0), (0,1,0), (0,-1,0), (0,0,1), (0,0,-1)
        if (normal.y > 0.9) {
            // Top/Bottom: Scale by X and Z
            tiledUV = in.uv * float2(in.scale.x, in.scale.z) * 0.5; // Scale factor adjustment
        } else if (normal.x > 0.9) {
            // Sides X: Scale by Z and Y
            tiledUV = in.uv * float2(in.scale.z, in.scale.y) * 0.5;
        } else {
            // Sides Z: Scale by X and Y
            tiledUV = in.uv * float2(in.scale.x, in.scale.y) * 0.5;
        }

        float4 texColor = textures.sample(textureSampler, tiledUV, uint(in.textureIndex));
        
        // Blend with base color instead of replacing it, to keep lighting/shading
        // Or just use the texture color if we want the "Nano Banana" look pure.
        // Previous logic was pure replacement for debug. Let's blend nicely now.
        // baseColor = mix(baseColor, texColor.rgb, texColor.a * 0.9);
        
        // For "Nano Banana" look, we usually want the texture to BE the building material.
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
    if (in.shapeID == 8) {
        float pulse = 0.5 + 0.5 * sin(uniforms.time * 7.5);
        float flash = smoothstep(0.55, 0.9, pulse);
        float3 flashColor = float3(1.0, 0.55, 0.15);
        finalColor = mix(finalColor, flashColor, flash);
        finalColor += flashColor * flash * 0.6;
    }
    return float4(finalColor, 1.0);
}
