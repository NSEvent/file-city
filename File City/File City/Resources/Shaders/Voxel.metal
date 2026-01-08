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
    float3 localNormal [[flat]];
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
    
    // Pass original normal
    float3 originalNormal = in.normal;
    
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
        // Banner is long along X. Wave displacement in Z (sideways).
        // Wave propagates along X.
        float wave = sin(local.x * 0.8 + uniforms.time * 12.0);
        local.z += wave * 0.25;
        // Slight vertical flutter
        local.y += sin(local.x * 1.5 + uniforms.time * 15.0) * 0.05;
    } else if (instance.shapeID == 14) {
        // Tesla Model 3 body shape
        // Car is oriented along Z axis (front at +Z, rear at -Z)
        // local coords: x=width, y=height, z=length
        // local is -0.5 to 0.5 in each dimension

        float z = local.z; // -0.5 (rear) to 0.5 (front)
        float y = local.y; // -0.5 (bottom) to 0.5 (top)

        // Only sculpt the top half
        if (y > 0.0) {
            // Front hood slope (z > 0.2): slopes down toward front
            if (z > 0.2) {
                float frontT = (z - 0.2) / 0.3; // 0 at z=0.2, 1 at z=0.5
                float hoodDrop = frontT * frontT * 0.6;
                local.y -= hoodDrop * (y + 0.5);
            }
            // Rear trunk slope (z < -0.15): slopes down toward rear
            else if (z < -0.15) {
                float rearT = (-0.15 - z) / 0.35; // 0 at z=-0.15, 1 at z=-0.5
                float trunkDrop = rearT * rearT * 0.45;
                local.y -= trunkDrop * (y + 0.5);
            }
            // Cabin roof curve (middle section): slight dome
            else {
                float roofCurve = 1.0 - 4.0 * (z - 0.025) * (z - 0.025);
                roofCurve = max(0.0, roofCurve);
                local.y += roofCurve * 0.08 * (y + 0.5);
            }

            // Slight taper at sides for aerodynamic look
            float sideTaper = 1.0 - abs(z) * 0.15;
            local.x *= sideTaper;
        }
        // Bottom: slight inward tuck for wheel wells
        else {
            float wheelWellZ = abs(z) - 0.3;
            if (wheelWellZ > 0 && abs(local.x) > 0.35) {
                local.y += wheelWellZ * 0.2;
            }
        }
    } else if (instance.shapeID == 15) {
        // Tesla glass/window canopy
        // Sits on top of body, curved greenhouse shape
        float z = local.z;
        float y = local.y;

        // Only the top part forms the glass dome
        if (y > -0.2) {
            // Taper front windshield (z > 0.1)
            if (z > 0.1) {
                float frontT = (z - 0.1) / 0.4;
                local.y -= frontT * frontT * 0.7 * (y + 0.5);
                local.z -= frontT * 0.15;
            }
            // Taper rear window (z < -0.1)
            else if (z < -0.1) {
                float rearT = (-0.1 - z) / 0.4;
                local.y -= rearT * rearT * 0.5 * (y + 0.5);
                local.z += rearT * 0.1;
            }

            // Roof dome
            float roofCurve = 1.0 - 4.0 * z * z;
            roofCurve = max(0.0, roofCurve);
            local.y += roofCurve * 0.05;

            // Side taper for sleek look
            local.x *= 0.92 - abs(z) * 0.1;
        }
    } else if (instance.shapeID == 16) {
        // Wheel shape - cylinder approximation
        // Flatten into disk shape and round edges
        float radius = length(local.yz);
        float maxRadius = 0.5;
        if (radius > maxRadius * 0.85) {
            float scale = (maxRadius * 0.85) / radius;
            local.y *= scale;
            local.z *= scale;
        }
        // Make it thinner (wheel width)
        local.x *= 0.4;
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
    out.localNormal = originalNormal;
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

    // Tesla-style car color palette
    float3 carPalette[12] = {
        float3(0.85, 0.12, 0.15),  // Red (Tesla signature)
        float3(0.95, 0.95, 0.97),  // Pearl White
        float3(0.08, 0.08, 0.10),  // Black
        float3(0.72, 0.74, 0.76),  // Silver Metallic
        float3(0.10, 0.22, 0.45),  // Deep Blue
        float3(0.55, 0.58, 0.62),  // Midnight Silver
        float3(0.18, 0.20, 0.22),  // Midnight Cherry (dark)
        float3(0.92, 0.90, 0.85),  // Cream White
        float3(0.25, 0.35, 0.42),  // Steel Blue
        float3(0.45, 0.12, 0.15),  // Dark Red
        float3(0.20, 0.25, 0.30),  // Gunmetal
        float3(0.88, 0.65, 0.25),  // Gold/Bronze
    };

    // Car body (shapeID 14)
    if (in.shapeID == 14) {
        baseColor = carPalette[in.materialID % 12];

        // Car body lighting - more metallic/reflective
        float shade = saturate(dot(normalize(in.normal), float3(0.4, 0.85, 0.2)));
        float fresnel = pow(1.0 - abs(dot(normalize(in.normal), float3(0, 1, 0))), 3.0);

        // Metallic sheen
        float3 lit = baseColor * (0.5 + 0.5 * shade);
        lit += float3(0.15, 0.15, 0.18) * fresnel;

        // Subtle environment reflection
        float envReflect = pow(saturate(in.normal.y), 2.0) * 0.15;
        lit += float3(0.6, 0.7, 0.9) * envReflect;

        return float4(lit, 1.0);
    }

    // Glass canopy (shapeID 15)
    if (in.shapeID == 15) {
        // Dark tinted glass with reflections
        float3 glassColor = float3(0.08, 0.10, 0.12);

        float shade = saturate(dot(normalize(in.normal), float3(0.4, 0.85, 0.2)));
        float fresnel = pow(1.0 - abs(dot(normalize(in.normal), float3(0, 1, 0))), 2.5);

        // Glass tint + reflection
        float3 lit = glassColor * (0.6 + 0.4 * shade);
        // Sky reflection on top surfaces
        float skyReflect = saturate(in.normal.y) * 0.3;
        lit += float3(0.4, 0.5, 0.7) * (fresnel * 0.4 + skyReflect);

        // Slight edge highlight
        lit += float3(0.2, 0.25, 0.3) * fresnel * 0.3;

        return float4(lit, 1.0);
    }

    // Wheels (shapeID 16)
    if (in.shapeID == 16) {
        // Dark rubber/alloy wheels
        float3 wheelColor = float3(0.12, 0.12, 0.14);
        float shade = saturate(dot(normalize(in.normal), float3(0.4, 0.85, 0.2)));

        // Tire rubber with subtle sheen
        float3 lit = wheelColor * (0.5 + 0.5 * shade);

        // Alloy rim highlight on outer edge
        float rimHighlight = pow(abs(in.normal.x), 4.0) * 0.3;
        lit += float3(0.5, 0.5, 0.55) * rimHighlight;

        return float4(lit, 1.0);
    }

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
            // materialID 1 = rotate UV 90 degrees (for horizontal roads)
            if (in.materialID == 1) {
                // Swap and rotate: road lines should run along X instead of Z
                tiledUV = float2(in.uv.y, in.uv.x) * float2(in.scale.z, in.scale.x) * 0.5;
            } else {
                tiledUV = in.uv * float2(in.scale.x, in.scale.z) * 0.5;
            }
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
        if (in.textureIndex >= 0) {
            // Unconditional mapping - texture all faces to ensure visibility during turns
            
            // Calculate U based on segment offset
            // pad0 is offset, pad1 is width
            // in.uv.x is 0..1 per segment.
            
            // Detect face orientation to fix text mirroring and word order
            bool isFrontFace = (in.localNormal.z > 0.0);
            
            float uOffset = in.highlight;
            float uWidth = in.activity;
            
            // localU: 0.0 (Visual Left) -> 1.0 (Visual Right)
            // Empirically, 1.0 - in.uv.x provides this for Front Face (pZ).
            // For Back Face (nZ): v0(LocL, VisR) is U=0. v1(LocR, VisL) is U=1.
            // Vis L(1) -> Vis R(0). in.uv.x goes 1->0.
            // So 1.0 - in.uv.x goes 0->1 (Vis L -> Vis R).
            // So 1.0 - in.uv.x works for BOTH faces to map Vis Left -> Vis Right.
            float localU = 1.0 - in.uv.x;

            float globalU;
            if (isFrontFace) {
                // Front Face: Standard mapping
                globalU = uOffset + localU * uWidth;
            } else {
                // Back Face: "Move" the segment window to the opposite side of the texture
                // If Seg 0 (Offset 0.875) is Right-most in World...
                // From Back, Seg 0 is Left-most on screen.
                // We want Left-most on screen to show "D" (Offset 0).
                // So we map Offset 0.875 -> 0.0.
                // If Seg 7 (Offset 0) is Left-most in World...
                // From Back, Seg 7 is Right-most on screen.
                // We want Right-most on screen to show "y" (Offset 0.875).
                // So we map Offset 0.0 -> 0.875.
                // Formula: newBase = 1.0 - (uOffset + uWidth).
                // Check Seg 0: 1.0 - (0.875 + 0.125) = 0. Correct.
                // Check Seg 7: 1.0 - (0 + 0.125) = 0.875. Correct.
                
                float invertedBase = 1.0 - (uOffset + uWidth);
                globalU = invertedBase + localU * uWidth;
            }
            
            float2 finalUV = float2(globalU, in.uv.y);
            
            float4 texColor = signLabels.sample(textureSampler, finalUV, uint(in.textureIndex));
            finalColor = texColor.rgb;
            
            // Fabric shading
            float fold = sin(globalU * 50.0 + uniforms.time * 5.0);
            finalColor *= (0.9 + 0.1 * fold);
        }
    }
    return float4(finalColor, 1.0);
}