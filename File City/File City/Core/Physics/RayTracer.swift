import Foundation
import simd

final class RayTracer {
    struct Ray {
        let origin: SIMD3<Float>
        let direction: SIMD3<Float>
    }

    struct Hit {
        let distance: Float
        let blockID: UUID
    }

    // Intersection epsilon
    private let epsilon: Float = 1e-6

    func intersect(ray: Ray, blocks: [CityBlock], cameraYaw: Float) -> Hit? {
        var closestHit: Hit?

        for block in blocks {
            let rotationY = rotationYForWedge(block: block, cameraYaw: cameraYaw)
            // 1. Fast AABB Check
            let aabb = calculateAABB(for: block)
            guard let aabbDist = intersectAABB(ray: ray, minBounds: aabb.min, maxBounds: aabb.max),
                  aabbDist < (closestHit?.distance ?? .greatestFiniteMagnitude) else {
                continue
            }

            // 2. Exact Mesh Check
            if let dist = intersectMesh(ray: ray, block: block, rotationY: rotationY) {
                if dist < (closestHit?.distance ?? .greatestFiniteMagnitude) {
                    closestHit = Hit(distance: dist, blockID: block.nodeID)
                }
            }
        }

        return closestHit
    }

    private func calculateAABB(for block: CityBlock) -> (min: SIMD3<Float>, max: SIMD3<Float>) {
        let halfX = Float(block.footprint.x) * 0.5
        let halfZ = Float(block.footprint.y) * 0.5
        let baseHeight = Float(block.height)
        let baseY = block.position.y
        
        // Deformation height multiplier
        // Taper/Pyramid (1,2) add 0.5h -> 1.5h
        // Slant (3,4) add max 0.5 * 1.5 = 0.75h? 
        // Shader logic:
        // Slant X: y += x * 1.5. x is -0.5..0.5. Max add is 0.75. Top is 1.0 + 0.75 = 1.75.
        // Let's use 2.0x to be safe.
        let heightMult: Float = block.shapeID > 0 ? 2.0 : 1.0
        
        let minB = SIMD3<Float>(block.position.x - halfX, baseY, block.position.z - halfZ)
        let maxB = SIMD3<Float>(block.position.x + halfX, baseY + baseHeight * heightMult, block.position.z + halfZ)
        return (minB, maxB)
    }

    private func intersectAABB(ray: Ray, minBounds: SIMD3<Float>, maxBounds: SIMD3<Float>) -> Float? {
        let t1 = (minBounds - ray.origin) / ray.direction
        let t2 = (maxBounds - ray.origin) / ray.direction
        
        let tMin = simd_max(simd_min(t1, t2), SIMD3<Float>(repeating: 0)) // Clip to ray start
        let tMax = simd_min(simd_max(t1, t2), SIMD3<Float>(repeating: .greatestFiniteMagnitude))
        
        let near = max(max(tMin.x, tMin.y), tMin.z)
        let far = min(min(tMax.x, tMax.y), tMax.z)
        
        if near <= far && far >= 0 {
            return near
        }
        return nil
    }

    private func intersectMesh(ray: Ray, block: CityBlock, rotationY: Float) -> Float? {
        let halfX = Float(block.footprint.x) * 0.5
        let halfZ = Float(block.footprint.y) * 0.5
        let height = Float(block.height)
        let baseY = block.position.y
        
        // Base vertices (Y=base)
        var v0 = SIMD3<Float>(block.position.x - halfX, baseY, block.position.z - halfZ) // Back Left
        var v1 = SIMD3<Float>(block.position.x + halfX, baseY, block.position.z - halfZ) // Back Right
        var v2 = SIMD3<Float>(block.position.x + halfX, baseY, block.position.z + halfZ) // Front Right
        var v3 = SIMD3<Float>(block.position.x - halfX, baseY, block.position.z + halfZ) // Front Left
        
        // Top vertices (Y=height, potentially modified)
        var t0 = SIMD3<Float>(block.position.x - halfX, baseY + height, block.position.z - halfZ)
        var t1 = SIMD3<Float>(block.position.x + halfX, baseY + height, block.position.z - halfZ)
        var t2 = SIMD3<Float>(block.position.x + halfX, baseY + height, block.position.z + halfZ)
        var t3 = SIMD3<Float>(block.position.x - halfX, baseY + height, block.position.z + halfZ)

        if block.shapeID == 5 { // Cylinder
            applyCylinder(&t0, centerX: block.position.x, centerZ: block.position.z, scaleX: Float(block.footprint.x), scaleZ: Float(block.footprint.y))
            applyCylinder(&t1, centerX: block.position.x, centerZ: block.position.z, scaleX: Float(block.footprint.x), scaleZ: Float(block.footprint.y))
            applyCylinder(&t2, centerX: block.position.x, centerZ: block.position.z, scaleX: Float(block.footprint.x), scaleZ: Float(block.footprint.y))
            applyCylinder(&t3, centerX: block.position.x, centerZ: block.position.z, scaleX: Float(block.footprint.x), scaleZ: Float(block.footprint.y))

            var v0c = v0
            var v1c = v1
            var v2c = v2
            var v3c = v3
            applyCylinder(&v0c, centerX: block.position.x, centerZ: block.position.z, scaleX: Float(block.footprint.x), scaleZ: Float(block.footprint.y))
            applyCylinder(&v1c, centerX: block.position.x, centerZ: block.position.z, scaleX: Float(block.footprint.x), scaleZ: Float(block.footprint.y))
            applyCylinder(&v2c, centerX: block.position.x, centerZ: block.position.z, scaleX: Float(block.footprint.x), scaleZ: Float(block.footprint.y))
            applyCylinder(&v3c, centerX: block.position.x, centerZ: block.position.z, scaleX: Float(block.footprint.x), scaleZ: Float(block.footprint.y))

            return intersectPrism(ray: ray, v0: v0c, v1: v1c, v2: v2c, v3: v3c, t0: t0, t1: t1, t2: t2, t3: t3)
        }

        if block.shapeID == 1 { // Taper
            // Top scaled by 0.4, moved up by 0.5h
            let scale: Float = 0.4
            let yOffset = height * 0.5
            
            // Recenter, scale, move back, move up
            // Center X/Z is block.position.x/z
            t0.x = block.position.x + (t0.x - block.position.x) * scale
            t0.z = block.position.z + (t0.z - block.position.z) * scale
            t0.y += yOffset
            
            t1.x = block.position.x + (t1.x - block.position.x) * scale
            t1.z = block.position.z + (t1.z - block.position.z) * scale
            t1.y += yOffset
            
            t2.x = block.position.x + (t2.x - block.position.x) * scale
            t2.z = block.position.z + (t2.z - block.position.z) * scale
            t2.y += yOffset
            
            t3.x = block.position.x + (t3.x - block.position.x) * scale
            t3.z = block.position.z + (t3.z - block.position.z) * scale
            t3.y += yOffset
            
        } else if block.shapeID == 2 { // Pyramid
            // Collapses to center point, moved up by 0.5h
            let center = SIMD3<Float>(block.position.x, baseY + height * 1.5, block.position.z)
            t0 = center; t1 = center; t2 = center; t3 = center
            
        } else if block.shapeID == 3 { // Slant X
            // y += x * 1.5
            // Local x is -0.5 .. 0.5
            // v0/v3 are x=-0.5 -> y -= 0.75h ?? No, vertex shader: local.y += local.x * 1.5
            // This modifies the vertex position.
            // Wait, does it modify the BASE vertices too?
            // "if (local.y > 0.0)" -> NO. Only top vertices are modified in my shader logic!
            // Correct.
            
            // t0 (Left): x = -0.5 -> y += -0.75h = 0.25h
            // t1 (Right): x = 0.5 -> y += 0.75h = 1.75h
            t0.y += -0.5 * 1.5 * height
            t3.y += -0.5 * 1.5 * height
            t1.y += 0.5 * 1.5 * height
            t2.y += 0.5 * 1.5 * height
            
        } else if block.shapeID == 4 { // Slant Z
            // y += z * 1.5
            // t0 (Back): z = -0.5 -> y -= 0.75h
            // t2 (Front): z = 0.5 -> y += 0.75h
            t0.y += -0.5 * 1.5 * height
            t1.y += -0.5 * 1.5 * height
            t2.y += 0.5 * 1.5 * height
            t3.y += 0.5 * 1.5 * height
        }
        
        if rotationY != 0, block.shapeID == 3 || block.shapeID == 4 {
            let center = block.position
            v0 = rotateY(point: v0, around: center, radians: rotationY)
            v1 = rotateY(point: v1, around: center, radians: rotationY)
            v2 = rotateY(point: v2, around: center, radians: rotationY)
            v3 = rotateY(point: v3, around: center, radians: rotationY)
            t0 = rotateY(point: t0, around: center, radians: rotationY)
            t1 = rotateY(point: t1, around: center, radians: rotationY)
            t2 = rotateY(point: t2, around: center, radians: rotationY)
            t3 = rotateY(point: t3, around: center, radians: rotationY)
        }

        let triangles: [(SIMD3<Float>, SIMD3<Float>, SIMD3<Float>)] = [
            // Side 0 (Back): v0, t0, t1, v1
            (v0, t0, t1), (v0, t1, v1),
            // Side 1 (Right): v1, t1, t2, v2
            (v1, t1, t2), (v1, t2, v2),
            // Side 2 (Front): v2, t2, t3, v3
            (v2, t2, t3), (v2, t3, v3),
            // Side 3 (Left): v3, t3, t0, v0
            (v3, t3, t0), (v3, t0, v0),
            // Top Cap: t0, t2, t1 / t0, t3, t2
            (t0, t2, t1), (t0, t3, t2),
            // Bottom Cap: v0, v1, v2 / v0, v2, v3
            (v0, v1, v2), (v0, v2, v3)
        ]
        
        var minT: Float = .greatestFiniteMagnitude
        var hit = false
        
        for (a, b, c) in triangles {
            if let t = intersectTriangle(ray: ray, v0: a, v1: b, v2: c) {
                if t < minT {
                    minT = t
                    hit = true
                }
            }
        }
        
        return hit ? minT : nil
    }

    private func rotationYForWedge(block: CityBlock, cameraYaw: Float) -> Float {
        guard block.shapeID == 3 || block.shapeID == 4 else { return 0 }
        let cameraX = sin(cameraYaw)
        let cameraZ = cos(cameraYaw)
        if block.shapeID == 3 {
            return cameraX >= 0 ? .pi : 0
        }
        return cameraZ >= 0 ? .pi : 0
    }

    private func rotateY(point: SIMD3<Float>, around center: SIMD3<Float>, radians: Float) -> SIMD3<Float> {
        let translated = point - center
        let c = cos(radians)
        let s = sin(radians)
        let x = translated.x * c - translated.z * s
        let z = translated.x * s + translated.z * c
        return SIMD3<Float>(x, translated.y, z) + center
    }

    private func intersectPrism(
        ray: Ray,
        v0: SIMD3<Float>,
        v1: SIMD3<Float>,
        v2: SIMD3<Float>,
        v3: SIMD3<Float>,
        t0: SIMD3<Float>,
        t1: SIMD3<Float>,
        t2: SIMD3<Float>,
        t3: SIMD3<Float>
    ) -> Float? {
        let triangles: [(SIMD3<Float>, SIMD3<Float>, SIMD3<Float>)] = [
            (v0, t0, t1), (v0, t1, v1),
            (v1, t1, t2), (v1, t2, v2),
            (v2, t2, t3), (v2, t3, v3),
            (v3, t3, t0), (v3, t0, v0),
            (t0, t2, t1), (t0, t3, t2),
            (v0, v1, v2), (v0, v2, v3)
        ]

        var minT: Float = .greatestFiniteMagnitude
        var hit = false

        for (a, b, c) in triangles {
            if let t = intersectTriangle(ray: ray, v0: a, v1: b, v2: c) {
                if t < minT {
                    minT = t
                    hit = true
                }
            }
        }

        return hit ? minT : nil
    }

    private func applyCylinder(
        _ vertex: inout SIMD3<Float>,
        centerX: Float,
        centerZ: Float,
        scaleX: Float,
        scaleZ: Float
    ) {
        let localX = (vertex.x - centerX) / scaleX
        let localZ = (vertex.z - centerZ) / scaleZ
        let radius = sqrt(localX * localX + localZ * localZ)
        let maxRadius: Float = 0.5

        if radius > maxRadius {
            let factor = maxRadius / radius
            vertex.x = centerX + (localX * factor) * scaleX
            vertex.z = centerZ + (localZ * factor) * scaleZ
        }
    }

    private func intersectTriangle(ray: Ray, v0: SIMD3<Float>, v1: SIMD3<Float>, v2: SIMD3<Float>) -> Float? {
        let edge1 = v1 - v0
        let edge2 = v2 - v0
        let h = simd_cross(ray.direction, edge2)
        let a = simd_dot(edge1, h)
        
        if a > -epsilon && a < epsilon { return nil }
        
        let f = 1.0 / a
        let s = ray.origin - v0
        let u = f * simd_dot(s, h)
        
        if u < 0.0 || u > 1.0 { return nil }
        
        let q = simd_cross(s, edge1)
        let v = f * simd_dot(ray.direction, q)
        
        if v < 0.0 || u + v > 1.0 { return nil }
        
        let t = f * simd_dot(edge2, q)
        
        if t > epsilon {
            return t
        }
        return nil
    }
}
