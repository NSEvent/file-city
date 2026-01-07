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
    float rotationX;
    float rotationZ;
    float pad2;
    uint materialID;
    float highlight;
    float hover;
    float activity;
    int activityKind;
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
    float activity;
    int activityKind [[flat]];
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
            // tapered Spire
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
    } else if (instance.shapeID == 12) {
        // Beam: Anchor at bottom
        // Local Y is -0.5 to 0.5. Shift to 0.0 to 1.0
        local.y += 0.5;
    } else if (instance.shapeID == 13) {
        // Waving Banner
        // Wave along Z (length), displace X (side)
        float wave = sin(local.z * 1.5 + uniforms.time * 8.0);
        local.x += wave * 0.15;
    }

    float3 scaled = local * instance.scale;
    float3 normal = in.normal;

    // Apply rotations: Z, then X, then Y
    if (instance.rotationZ != 0.0) {
        float c = cos(instance.rotationZ);
        float s = sin(instance.rotationZ);
        
        float x = scaled.x * c - scaled.y * s;
        float y = scaled.x * s + scaled.y * c;
        scaled.x = x;
        scaled.y = y;
        
        float nx = normal.x * c - normal.y * s;
        float ny = normal.x * s + normal.y * c;
        normal.x = nx;
        normal.y = ny;
    }
    if (instance.rotationX != 0.0) {
        float c = cos(instance.rotationX);
        float s = sin(instance.rotationX);
        
        float y = scaled.y * c - scaled.z * s;
        float z = scaled.y * s + scaled.z * c;
        scaled.y = y;
        scaled.z = z;
        
        float ny = normal.y * c - normal.z * s;
        float nz = normal.y * s + normal.z * c;
        normal.y = ny;
        normal.z = nz;
    }
    if (instance.rotationY != 0.0) {
        float c = cos(instance.rotationY);
        float s = sin(instance.rotationY);
        
        float x = scaled.x * c - scaled.z * s;
        float z = scaled.x * s + scaled.z * c;
        scaled.x = x;
        scaled.z = z;
        
        float nx = normal.x * c - normal.z * s;
        float nz = normal.x * s + normal.z * c;
        normal.x = nx;
        normal.z = nz;
    }

    float3 world = scaled + instance.position;
    VertexOut out;
    out.position = uniforms.viewProjection * float4(world, 1.0);
    out.normal = normal;
    out.uv = in.uv;
    out.scale = instance.scale;
    out.textureIndex = instance.textureIndex;
    out.materialID = instance.materialID;
    out.shapeID = instance.shapeID;
    out.highlight = instance.highlight;
    out.hover = instance.hover;
    out.activity = instance.activity;
    out.activityKind = instance.activityKind;
    return out;
}

fragment float4 fragment_main_v2(VertexOut in [[stage_in]],
                              constant Uniforms &uniforms [[buffer(2)]],
                              texture2d_array<float> textures [[texture(0)]],
                              texture2d_array<float> signLabels [[texture(1)]],
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
    float activity = saturate(in.activity);
    if (activity > 0.0) {
        float pulseSpeed = in.activityKind == 2 ? 10.5 : 6.5;
        float pulse = 0.45 + 0.55 * sin(uniforms.time * pulseSpeed);
        float3 activityColor = in.activityKind == 2 ? float3(1.0, 0.55, 0.2) : float3(0.2, 0.75, 1.0);
        finalColor = mix(finalColor, activityColor, activity * (0.25 + 0.35 * pulse));
        finalColor += activityColor * activity * 0.18;
    }
    if (in.shapeID == 8) {
        float3 flashColor = float3(1.0, 0.55, 0.15);
        float pulse = 0.5 + 0.5 * sin(uniforms.time * 7.5);
        float flash = smoothstep(0.55, 0.9, pulse);
        finalColor = mix(finalColor, flashColor, flash);
        finalColor += flashColor * flash * 0.6;
    } else if (in.shapeID == 9) {
        float3 flashColor = float3(0.2, 0.95, 0.35);
        float glow = 0.75;
        finalColor = mix(finalColor, flashColor, glow);
        finalColor += flashColor * glow * 0.4;
    } else if (in.shapeID == 10) {
        // Text quad - materialID contains ASCII code, textureIndex is font atlas
        // Font atlas layout: 16x16 grid, characters 32-127 in first 96 cells
        uint charCode = in.materialID;
        if (charCode >= 32 && charCode < 128) {
            uint charIndex = charCode - 32;
            uint col = charIndex % 16;
            uint row = charIndex / 16;

            // Each cell is 1/16 of the texture
            float cellSize = 1.0 / 16.0;
            float2 cellOffset = float2(float(col), float(row)) * cellSize;
            // Flip U to correct for face orientation
            float2 flippedUV = float2(1.0 - in.uv.x, in.uv.y);
            float2 charUV = cellOffset + flippedUV * cellSize;

            float4 texColor = textures.sample(textureSampler, charUV, uint(in.textureIndex));
            finalColor = texColor.rgb;

            // Add slight glow for readability
            if (texColor.r > 0.5) {
                finalColor += float3(0.1, 0.1, 0.1);
            }
        }
    } else if (in.shapeID == 11) {
        // Sign label - sample from pre-baked sign label texture array
        // textureIndex contains the sign label index
        if (in.textureIndex >= 0) {
            // Flip U to correct for face orientation
            float2 flippedUV = float2(1.0 - in.uv.x, in.uv.y);
            float4 texColor = signLabels.sample(textureSampler, flippedUV, uint(in.textureIndex));
            finalColor = texColor.rgb;
        }
    } else if (in.shapeID == 12) {
        // Beam - White core, Blue edge
        float alpha = saturate(in.highlight);
        
        // Core beam intensity (0 edge -> 1 center)
        float dist = abs(in.uv.x * 2.0 - 1.0);
        float core = 1.0 - dist;
        core = pow(core, 3.0); // Sharpen
        
        // Pulse vertical
        float pulse = 0.85 + 0.15 * sin(uniforms.time * 25.0 - in.uv.y * 10.0);
        
        float3 blueColor = float3(0.1, 0.4, 1.0);
        float3 whiteColor = float3(1.0, 1.0, 1.0);
        
        // Mix blue and white based on core intensity
        // Very center is white, quickly falls off to blue
        float3 beamColor = mix(blueColor, whiteColor, pow(core, 4.0));
        
        // Final color
        finalColor = beamColor * pulse;
        
        // Fade out alpha at edges to avoid hard lines
        float edgeFade = smoothstep(0.8, 0.0, dist);
        
        return float4(finalColor, alpha * edgeFade * 0.9);
    } else if (in.shapeID == 13) {
        // Banner - Sample from signLabels array
        // Use textureIndex from instance
        if (in.textureIndex >= 0) {
            // Standard UVs are 0..1 per face.
            // On the side face (Normal X), this covers the whole side.
            // Flip U if needed (often needed for these cube mappings)
            float2 flippedUV = float2(1.0 - in.uv.x, in.uv.y);
            
            // Adjust for side? If we see the "back" side of the banner, text is mirrored.
            // Normal.x > 0 vs < 0.
            // If normal.x < 0 (left side), maybe flip back?
            // Actually, for a thin banner, we might see both sides.
            // Let's assume standard flip is okay.
            
            float4 texColor = signLabels.sample(textureSampler, flippedUV, uint(in.textureIndex));
            finalColor = texColor.rgb;
            
            // Cloth texture/shading
            float fabric = 0.9 + 0.1 * sin((in.uv.x + in.uv.y) * 100.0);
            finalColor *= fabric;
        }
    }
    return float4(finalColor, 1.0);
}
