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
    var isFlying: Bool = false             // Fly mode (no gravity, Space/Shift for up/down)
    var position = SIMD3<Float>(0, 2, 0)   // Eye position in first-person
    var fpYaw: Float = 0                   // Horizontal rotation (radians)
    var fpPitch: Float = 0                 // Vertical rotation (radians, clamped)
    var verticalVelocity: Float = 0        // Vertical velocity for gravity/jumping

    // Movement constants
    let playerHeight: Float = 3.5          // Player body height (for collision)
    let walkSpeed: Float = 20.0            // Normal walk speed (units per second)
    let sprintSpeed: Float = 35.0          // Sprint speed (units per second)
    var isSprinting: Bool = false          // Currently sprinting
    let mouseSensitivity: Float = 0.002    // Radians per pixel
    let maxPitch: Float = .pi / 2 - 0.1    // Prevent looking straight up/down

    // Grapple state
    var isGrappling: Bool = false
    var grappleTarget: SIMD3<Float> = .zero
    let grappleSpeed: Float = 80.0         // Speed when being pulled by grapple
    let grappleArrivalDistance: Float = 3.0 // Stop grappling when this close

    // Grapple attachment (hold shift to stay attached)
    enum GrappleAttachment {
        case none
        case block(position: SIMD3<Float>)
        case plane(index: Int)
        case helicopter(index: Int)
        case beacon(nodeID: UUID)
        case car(index: Int)
    }
    var grappleAttachment: GrappleAttachment = .none
    var isShiftHeld: Bool = false

    var moveSpeed: Float {
        isSprinting ? sprintSpeed : walkSpeed
    }

    // Physics constants
    let gravity: Float = -30.0             // Gravity acceleration (units/s²)
    let jumpVelocity: Float = 18.0         // Initial jump velocity
    let groundLevel: Float = 3.5           // Eye height when on ground

    // Isometric constants (original values)
    private let isoPitch: Float = 0.75
    private let isoYaw: Float = 0.7853982  // ~45°

    // MARK: - Computed Properties

    var yaw: Float {
        isFirstPerson ? fpYaw : isoYaw
    }

    /// Fixed yaw for wedge building rotation (always isometric angle)
    var wedgeYaw: Float {
        isoYaw
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
        fpYaw -= deltaX * mouseSensitivity
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

        // Calculate intended horizontal movement
        let horizontalMovement = self.forward * forwardAmount + self.right * rightAmount
        let horizontalDelta = horizontalMovement * moveSpeed * deltaTime

        var newPosition = position

        // Vertical movement depends on mode
        if isFlying {
            // Flying mode: direct up/down control
            newPosition.y += upAmount * moveSpeed * deltaTime
        } else {
            // Gravity mode: apply physics
            verticalVelocity += gravity * deltaTime
            newPosition.y += verticalVelocity * deltaTime

            // Check if on ground
            if newPosition.y <= groundLevel {
                newPosition.y = groundLevel
                verticalVelocity = 0
            }
        }

        // Clamp minimum height (stay above ground)
        newPosition.y = max(playerHeight * 0.5, newPosition.y)

        // Collision detection with buildings using sliding collision
        if let blocks {
            let playerRadius: Float = 0.5  // Player collision radius
            let playerFeetY = newPosition.y - playerHeight * 0.5
            let playerHeadY = newPosition.y + 0.2  // Small buffer above eye level
            let prevFeetY = position.y - playerHeight * 0.5

            // Handle rooftop landing first (vertical collision)
            for block in blocks {
                let halfX = Float(block.footprint.x) * 0.5
                let halfZ = Float(block.footprint.y) * 0.5
                let blockTop = block.position.y + Float(block.height)

                let minX = block.position.x - halfX
                let maxX = block.position.x + halfX
                let minZ = block.position.z - halfZ
                let maxZ = block.position.z + halfZ

                // Check if player is horizontally within building bounds
                let inX = position.x > minX && position.x < maxX
                let inZ = position.z > minZ && position.z < maxZ

                if inX && inZ {
                    // Landing on rooftop: if feet would go below rooftop and we were above it
                    if playerFeetY < blockTop && prevFeetY >= blockTop - 0.1 {
                        newPosition.y = blockTop + playerHeight * 0.5
                        if !isFlying {
                            verticalVelocity = 0
                        }
                    }
                }
            }

            // Recalculate vertical bounds after rooftop landing
            let finalFeetY = newPosition.y - playerHeight * 0.5
            let finalHeadY = newPosition.y + 0.2

            // Try X movement first
            var testX = position.x + horizontalDelta.x

            for block in blocks {
                let halfX = Float(block.footprint.x) * 0.5
                let halfZ = Float(block.footprint.y) * 0.5
                let blockTop = block.position.y + Float(block.height)
                let blockBottom = block.position.y

                // Skip if we're not vertically overlapping with this building
                if finalFeetY >= blockTop || finalHeadY <= blockBottom {
                    continue
                }

                let minX = block.position.x - halfX - playerRadius
                let maxX = block.position.x + halfX + playerRadius
                let minZ = block.position.z - halfZ - playerRadius
                let maxZ = block.position.z + halfZ + playerRadius

                // Check if the new X position would collide
                if testX > minX && testX < maxX && position.z > minZ && position.z < maxZ {
                    // Block X movement - slide along the wall
                    if horizontalDelta.x > 0 {
                        testX = minX
                    } else {
                        testX = maxX
                    }
                }
            }

            // Try Z movement
            var testZ = position.z + horizontalDelta.z

            for block in blocks {
                let halfX = Float(block.footprint.x) * 0.5
                let halfZ = Float(block.footprint.y) * 0.5
                let blockTop = block.position.y + Float(block.height)
                let blockBottom = block.position.y

                // Skip if we're not vertically overlapping with this building
                if finalFeetY >= blockTop || finalHeadY <= blockBottom {
                    continue
                }

                let minX = block.position.x - halfX - playerRadius
                let maxX = block.position.x + halfX + playerRadius
                let minZ = block.position.z - halfZ - playerRadius
                let maxZ = block.position.z + halfZ + playerRadius

                // Check if the new Z position would collide (using resolved X)
                if testX > minX && testX < maxX && testZ > minZ && testZ < maxZ {
                    // Block Z movement - slide along the wall
                    if horizontalDelta.z > 0 {
                        testZ = minZ
                    } else {
                        testZ = maxZ
                    }
                }
            }

            newPosition.x = testX
            newPosition.z = testZ
        } else {
            // No collision detection - just apply movement
            newPosition.x += horizontalDelta.x
            newPosition.z += horizontalDelta.z
        }

        position = newPosition
    }

    /// Jump (only works in gravity mode when on a surface)
    func jump() {
        guard isFirstPerson, !isFlying else { return }
        // Only jump if velocity is ~0 (meaning we're on a surface - ground or rooftop)
        if abs(verticalVelocity) < 0.1 {
            verticalVelocity = jumpVelocity
        }
    }

    /// Start grappling towards a target point with optional attachment info
    func startGrapple(to target: SIMD3<Float>, attachment: GrappleAttachment = .none) {
        guard isFirstPerson else { return }
        isGrappling = true
        grappleTarget = target
        grappleAttachment = attachment
        verticalVelocity = 0  // Cancel any falling
    }

    /// Stop grappling and detach (called when shift is released)
    func stopGrapple() {
        isGrappling = false
        grappleAttachment = .none
    }

    /// Check if currently attached to something
    var isAttached: Bool {
        if case .none = grappleAttachment { return false }
        return !isGrappling  // Attached when done grappling but still holding
    }

    /// Update grapple movement (call every frame while grappling)
    /// Returns true if still grappling
    func updateGrapple(deltaTime: Float) -> Bool {
        guard isFirstPerson, isGrappling else { return false }

        let direction = grappleTarget - position
        let distance = simd_length(direction)

        // Arrived at target
        if distance < grappleArrivalDistance {
            isGrappling = false
            verticalVelocity = 0  // Soft landing

            // If shift is held, stay attached; otherwise clear attachment
            if !isShiftHeld {
                grappleAttachment = .none
            }
            return false
        }

        // Move towards target
        let normalizedDir = direction / distance
        let moveAmount = min(grappleSpeed * deltaTime, distance)
        position += normalizedDir * moveAmount

        return true
    }

    /// Update position while attached to a moving object
    func updateAttachment(targetPosition: SIMD3<Float>, rideOnTop: Bool = false) {
        guard isFirstPerson, isAttached, isShiftHeld else {
            if !isShiftHeld {
                grappleAttachment = .none
            }
            return
        }

        // Follow the target with an offset
        let offset: SIMD3<Float>
        if rideOnTop {
            offset = SIMD3<Float>(0, 2.0, 0)  // Sit on top (for cars)
        } else {
            offset = SIMD3<Float>(0, -2.0, 0)  // Hang below (for planes/helicopters)
        }
        position = targetPosition + offset
        verticalVelocity = 0
    }

    /// Toggle flying mode
    func toggleFlying() {
        guard isFirstPerson else { return }
        isFlying.toggle()
        if isFlying {
            verticalVelocity = 0  // Stop any vertical momentum when entering fly mode
        }
    }

    /// Check if player is on a surface (ground or rooftop)
    var isOnGround: Bool {
        abs(verticalVelocity) < 0.1
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
