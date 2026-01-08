import Foundation
import simd

final class Camera {
    // MARK: - Shared Properties
    var aspect: Float = 1.0

    // MARK: - Isometric Mode Properties
    var target = SIMD3<Float>(0, 0, 0)
    var distance: Float = 60

    // MARK: - First-Person Mode Properties
    var isFirstPerson: Bool = false
    var position = SIMD3<Float>(0, 2, 0)  // Eye position in first-person
    var fpYaw: Float = 0                   // Horizontal rotation (radians)
    var fpPitch: Float = 0                 // Vertical rotation (radians, clamped)
    var velocity = SIMD3<Float>(0, 0, 0)   // Current velocity for smooth movement

    // Movement constants
    let playerHeight: Float = 2.0          // Eye height above ground
    let moveSpeed: Float = 20.0            // Units per second
    let mouseSensitivity: Float = 0.002    // Radians per pixel
    let maxPitch: Float = .pi / 2 - 0.1    // Prevent looking straight up/down

    // Isometric constants (original values)
    private let isoPitch: Float = 0.75
    private let isoYaw: Float = 0.7853982  // ~45°

    // MARK: - Computed Properties

    var yaw: Float {
        isFirstPerson ? fpYaw : isoYaw
    }

    var pitch: Float {
        isFirstPerson ? fpPitch : isoPitch
    }

    /// Forward direction on XZ plane (for movement)
    var forward: SIMD3<Float> {
        SIMD3<Float>(sin(fpYaw), 0, cos(fpYaw))
    }

    /// Right direction on XZ plane
    var right: SIMD3<Float> {
        SIMD3<Float>(cos(fpYaw), 0, -sin(fpYaw))
    }

    /// Look direction including pitch (for view matrix)
    var lookDirection: SIMD3<Float> {
        SIMD3<Float>(
            cos(fpPitch) * sin(fpYaw),
            sin(fpPitch),
            cos(fpPitch) * cos(fpYaw)
        )
    }

    // MARK: - Isometric Mode Methods

    func zoom(delta: Float) {
        guard !isFirstPerson else { return }
        distance = max(0.02, distance - delta * 20)
    }

    func pan(deltaX: Float, deltaY: Float) {
        guard !isFirstPerson else { return }
        let right = SIMD3<Float>(cos(isoYaw), 0, -sin(isoYaw))
        let forward = SIMD3<Float>(sin(isoYaw), 0, cos(isoYaw))
        target += (right * deltaX + forward * deltaY) * 0.2
    }

    // MARK: - First-Person Mode Methods

    /// Rotate camera based on mouse movement
    func rotate(deltaX: Float, deltaY: Float) {
        guard isFirstPerson else { return }
        fpYaw += deltaX * mouseSensitivity
        fpPitch -= deltaY * mouseSensitivity

        // Clamp pitch to prevent gimbal lock
        fpPitch = max(-maxPitch, min(maxPitch, fpPitch))

        // Wrap yaw to 0..2π
        while fpYaw < 0 { fpYaw += 2 * .pi }
        while fpYaw >= 2 * .pi { fpYaw -= 2 * .pi }
    }

    /// Move camera based on input direction, with optional collision detection
    func move(forward forwardAmount: Float, right rightAmount: Float, up upAmount: Float, deltaTime: Float, blocks: [CityBlock]? = nil) {
        guard isFirstPerson else { return }

        let movement = self.forward * forwardAmount + self.right * rightAmount + SIMD3<Float>(0, upAmount, 0)
        var newPosition = position + movement * moveSpeed * deltaTime

        // Clamp minimum height (stay above ground)
        newPosition.y = max(playerHeight * 0.5, newPosition.y)

        // Collision detection with buildings
        if let blocks {
            let playerRadius: Float = 0.5  // Player collision radius
            let playerBottom = newPosition.y - playerHeight * 0.5
            let playerTop = newPosition.y + 0.2  // Small buffer above eye level

            for block in blocks {
                let halfX = Float(block.footprint.x) * 0.5 + playerRadius
                let halfZ = Float(block.footprint.y) * 0.5 + playerRadius
                let blockTop = block.position.y + Float(block.height)

                // Check if player overlaps with building AABB
                let minX = block.position.x - halfX
                let maxX = block.position.x + halfX
                let minZ = block.position.z - halfZ
                let maxZ = block.position.z + halfZ

                // Check vertical overlap
                if playerBottom < blockTop && playerTop > block.position.y {
                    // Check horizontal overlap and resolve
                    let inX = newPosition.x > minX && newPosition.x < maxX
                    let inZ = newPosition.z > minZ && newPosition.z < maxZ

                    if inX && inZ {
                        // Inside building - push out to nearest edge
                        let distToMinX = abs(newPosition.x - minX)
                        let distToMaxX = abs(newPosition.x - maxX)
                        let distToMinZ = abs(newPosition.z - minZ)
                        let distToMaxZ = abs(newPosition.z - maxZ)

                        let minDist = min(distToMinX, distToMaxX, distToMinZ, distToMaxZ)

                        if minDist == distToMinX {
                            newPosition.x = minX
                        } else if minDist == distToMaxX {
                            newPosition.x = maxX
                        } else if minDist == distToMinZ {
                            newPosition.z = minZ
                        } else {
                            newPosition.z = maxZ
                        }
                    }
                }
            }
        }

        position = newPosition
    }

    /// Toggle between isometric and first-person mode
    func toggleFirstPerson() {
        isFirstPerson.toggle()

        if isFirstPerson {
            // Enter first-person: place camera at current view position
            let eye = SIMD3<Float>(
                target.x + distance * cos(isoPitch) * sin(isoYaw),
                target.y + distance * sin(isoPitch),
                target.z + distance * cos(isoPitch) * cos(isoYaw)
            )
            position = SIMD3<Float>(eye.x, playerHeight, eye.z)
            fpYaw = isoYaw + .pi  // Face toward the city (opposite direction)
            fpPitch = 0
        } else {
            // Exit first-person: update target to look at current position
            target = position - forward * 30
            target.y = 0
            distance = 60
        }
    }

    /// Set position to center of city at ground level
    func enterCityCenter(blocks: [CityBlock]) {
        guard isFirstPerson, !blocks.isEmpty else { return }

        // Find center of all blocks
        var minX: Float = .greatestFiniteMagnitude
        var maxX: Float = -.greatestFiniteMagnitude
        var minZ: Float = .greatestFiniteMagnitude
        var maxZ: Float = -.greatestFiniteMagnitude

        for block in blocks {
            minX = min(minX, block.position.x)
            maxX = max(maxX, block.position.x)
            minZ = min(minZ, block.position.z)
            maxZ = max(maxZ, block.position.z)
        }

        position = SIMD3<Float>(
            (minX + maxX) / 2,
            playerHeight,
            maxZ + 10  // Start at the edge, facing into the city
        )
        fpYaw = .pi  // Face toward negative Z (into the city)
        fpPitch = 0
    }

    // MARK: - View Matrix

    func viewMatrix() -> simd_float4x4 {
        if isFirstPerson {
            let lookTarget = position + lookDirection
            return lookAt(eye: position, target: lookTarget, up: SIMD3<Float>(0, 1, 0))
        } else {
            let eye = SIMD3<Float>(
                target.x + distance * cos(isoPitch) * sin(isoYaw),
                target.y + distance * sin(isoPitch),
                target.z + distance * cos(isoPitch) * cos(isoYaw)
            )
            return lookAt(eye: eye, target: target, up: SIMD3<Float>(0, 1, 0))
        }
    }

    /// Get current eye position (for picking in first-person)
    func eyePosition() -> SIMD3<Float> {
        if isFirstPerson {
            return position
        } else {
            return SIMD3<Float>(
                target.x + distance * cos(isoPitch) * sin(isoYaw),
                target.y + distance * sin(isoPitch),
                target.z + distance * cos(isoPitch) * cos(isoYaw)
            )
        }
    }

    func projectionMatrix() -> simd_float4x4 {
        let fov: Float = isFirstPerson ? 1.2 : 0.75  // Wider FOV for first-person
        return perspective(fovY: fov, aspect: aspect, near: 0.01, far: 2000)
    }

    private func lookAt(eye: SIMD3<Float>, target: SIMD3<Float>, up: SIMD3<Float>) -> simd_float4x4 {
        let z = simd_normalize(eye - target)
        let x = simd_normalize(simd_cross(up, z))
        let y = simd_cross(z, x)
        let translation = SIMD3<Float>(-simd_dot(x, eye), -simd_dot(y, eye), -simd_dot(z, eye))
        return simd_float4x4(columns: (
            SIMD4<Float>(x.x, y.x, z.x, 0),
            SIMD4<Float>(x.y, y.y, z.y, 0),
            SIMD4<Float>(x.z, y.z, z.z, 0),
            SIMD4<Float>(translation.x, translation.y, translation.z, 1)
        ))
    }

    private func perspective(fovY: Float, aspect: Float, near: Float, far: Float) -> simd_float4x4 {
        let yScale = 1 / tan(fovY * 0.5)
        let xScale = yScale / max(aspect, 0.01)
        let zRange = far - near
        let zScale = -(far + near) / zRange
        let wzScale = -2 * far * near / zRange
        return simd_float4x4(columns: (
            SIMD4<Float>(xScale, 0, 0, 0),
            SIMD4<Float>(0, yScale, 0, 0),
            SIMD4<Float>(0, 0, zScale, -1),
            SIMD4<Float>(0, 0, wzScale, 0)
        ))
    }
}
