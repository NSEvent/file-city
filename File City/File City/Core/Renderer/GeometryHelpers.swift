import Foundation
import simd

// MARK: - Geometry Helper Functions

/// Calculate the visual top Y position of a building, accounting for shape deformations
/// Different building shapes (taper, pyramid, wedge) extend above their base height
func visualTopY(for block: CityBlock) -> Float {
    let baseTop = block.position.y + Float(block.height)
    let spireBoost: Float

    switch block.shapeID {
    case Constants.Shapes.slantX, Constants.Shapes.slantZ:
        // Wedges tilt up by 1.5x extent (0.5 * 1.5 = 0.75)
        spireBoost = Float(block.height) * 0.75
    case Constants.Shapes.taper, Constants.Shapes.pyramid:
        // Spire/Pyramid move top up by 0.5x height
        spireBoost = Float(block.height) * 0.5
    default:
        spireBoost = 0
    }

    return baseTop + spireBoost
}

/// Calculate the rotation angle for wedge-shaped buildings
/// Wedges need to be rotated based on camera yaw to face correctly
func rotationYForWedge(block: CityBlock, cameraYaw: Float) -> Float {
    guard Constants.Shapes.isWedge(block.shapeID) else { return 0 }
    return cameraYaw + (.pi / 4)
}

/// Find the maximum visual height at a specific X/Z grid location
/// Useful for placing things on top of stacked buildings
func maxVisualHeightAt(x: Float, z: Float, in blocks: [CityBlock], tolerance: Float = 0.1) -> Float {
    var maxHeight: Float = 0

    for block in blocks {
        if abs(block.position.x - x) < tolerance && abs(block.position.z - z) < tolerance {
            let top = visualTopY(for: block)
            if top > maxHeight {
                maxHeight = top
            }
        }
    }

    return maxHeight
}

/// Find the topmost block at a specific X/Z grid location
/// Returns the block with the highest visual top Y position
func topmostBlock(at x: Float, z: Float, in blocks: [CityBlock], tolerance: Float = 0.1) -> CityBlock? {
    var highest: CityBlock?
    var maxHeight: Float = -.greatestFiniteMagnitude

    for block in blocks {
        if abs(block.position.x - x) < tolerance && abs(block.position.z - z) < tolerance {
            let top = visualTopY(for: block)
            if top > maxHeight {
                maxHeight = top
                highest = block
            }
        }
    }

    return highest
}

/// Calculate the beacon offset for wedge buildings
/// Wedges have their highest point offset from center
func beaconOffset(for block: CityBlock, cameraYaw: Float) -> SIMD2<Float> {
    guard Constants.Shapes.isWedge(block.shapeID) else {
        return .zero
    }

    let footprintX = Float(block.footprint.x)
    let footprintZ = Float(block.footprint.y)
    let rotationY = rotationYForWedge(block: block, cameraYaw: cameraYaw)

    var offsetX: Float = 0
    var offsetZ: Float = 0

    if block.shapeID == Constants.Shapes.slantX {
        offsetX = footprintX * 0.45
    } else if block.shapeID == Constants.Shapes.slantZ {
        offsetZ = footprintZ * 0.45
    }

    // Apply rotation
    let c = cos(rotationY)
    let s = sin(rotationY)
    let rotatedX = offsetX * c - offsetZ * s
    let rotatedZ = offsetX * s + offsetZ * c

    return SIMD2<Float>(rotatedX, rotatedZ)
}

/// Calculate ray direction from screen point
/// Used for picking (hit testing) in the 3D view
func rayDirection(from point: CGPoint, in size: CGSize, camera: Camera) -> SIMD3<Float> {
    guard size.width > 1, size.height > 1 else {
        return SIMD3<Float>(0, 0, -1)
    }

    let ndcX = Float((2.0 * point.x / size.width) - 1.0)
    let ndcY = Float(1.0 - (2.0 * point.y / size.height))

    let projInv = camera.projectionMatrix().inverse
    let viewInv = camera.viewMatrix().inverse

    let clipNear = SIMD4<Float>(ndcX, ndcY, -1, 1)
    var viewNear = projInv * clipNear
    viewNear /= viewNear.w
    let worldNear = viewInv * viewNear

    let clipFar = SIMD4<Float>(ndcX, ndcY, 1, 1)
    var viewFar = projInv * clipFar
    viewFar /= viewFar.w
    let worldFar = viewInv * viewFar

    let origin = SIMD3<Float>(worldNear.x, worldNear.y, worldNear.z)
    let target = SIMD3<Float>(worldFar.x, worldFar.y, worldFar.z)
    let direction = simd_normalize(target - origin)

    return direction
}

// MARK: - Sorting Helpers

/// Get sorted unique values from an array of floats
func sortedUnique(values: [Float]) -> [Float] {
    var seen = Set<Int>()
    var unique: [Float] = []
    for v in values {
        let key = Int(v * 100)
        if seen.insert(key).inserted {
            unique.append(v)
        }
    }
    return unique.sorted()
}

/// Calculate minimum spacing between consecutive values
func minSpacing(values: [Float]) -> Float {
    guard values.count > 1 else { return 0 }
    var minDelta: Float = .greatestFiniteMagnitude
    for i in 1..<values.count {
        let delta = values[i] - values[i - 1]
        if delta > 0.1 && delta < minDelta {
            minDelta = delta
        }
    }
    return minDelta == .greatestFiniteMagnitude ? 0 : minDelta
}

// MARK: - Intersection Helpers

/// Intersect ray with sphere (used for vehicle picking)
func intersectSphere(ray: RayTracer.Ray, center: SIMD3<Float>, radius: Float) -> Float? {
    let oc = ray.origin - center
    let a = simd_dot(ray.direction, ray.direction)
    let b = 2.0 * simd_dot(oc, ray.direction)
    let c = simd_dot(oc, oc) - radius * radius
    let discriminant = b * b - 4 * a * c

    if discriminant < 0 {
        return nil
    }

    let t = (-b - sqrt(discriminant)) / (2.0 * a)
    return t > 0 ? t : nil
}

// MARK: - Random Number Helpers

/// Generate pseudo-random float from seed (0.0 - 1.0)
func randomUnit(seed: UInt64) -> Float {
    var s = seed
    s = (s &* 1103515245 &+ 12345) & 0x7fffffff
    return Float(s) / Float(0x7fffffff)
}
