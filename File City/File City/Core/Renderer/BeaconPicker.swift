import Foundation
import simd

struct BeaconPicker {
    struct Box {
        let nodeID: UUID
        let min: SIMD3<Float>
        let max: SIMD3<Float>
    }

    static func pick(ray: RayTracer.Ray, boxes: [Box]) -> UUID? {
        return pickWithDistance(ray: ray, boxes: boxes)?.nodeID
    }

    static func pickWithDistance(ray: RayTracer.Ray, boxes: [Box]) -> (nodeID: UUID, distance: Float)? {
        var closest: (nodeID: UUID, distance: Float)?
        for box in boxes {
            if let distance = intersectAABB(ray: ray, minBounds: box.min, maxBounds: box.max) {
                if closest == nil || distance < closest!.distance {
                    closest = (box.nodeID, distance)
                }
            }
        }
        return closest
    }

    private static func intersectAABB(ray: RayTracer.Ray, minBounds: SIMD3<Float>, maxBounds: SIMD3<Float>) -> Float? {
        let invDirection = SIMD3<Float>(
            ray.direction.x == 0 ? .greatestFiniteMagnitude : 1.0 / ray.direction.x,
            ray.direction.y == 0 ? .greatestFiniteMagnitude : 1.0 / ray.direction.y,
            ray.direction.z == 0 ? .greatestFiniteMagnitude : 1.0 / ray.direction.z
        )
        let t1 = (minBounds - ray.origin) * invDirection
        let t2 = (maxBounds - ray.origin) * invDirection
        let tMin = max(max(min(t1.x, t2.x), min(t1.y, t2.y)), min(t1.z, t2.z))
        let tMax = min(min(max(t1.x, t2.x), max(t1.y, t2.y)), max(t1.z, t2.z))
        if tMax < 0 || tMin > tMax { return nil }
        return tMin >= 0 ? tMin : tMax
    }
}
