import Foundation
import simd

final class Camera {
    // MARK: - Shared Properties
    var aspect: Float = 1.0

    // MARK: - Isometric Mode Properties
    var target = SIMD3<Float>(0, 0, 0)
    var distance: Float = Constants.Camera.defaultDistance

    // MARK: - First-Person Mode Properties
    var isFirstPerson: Bool = false
    var isFlying: Bool = false             // Fly mode (no gravity, Space/Shift for up/down)
    var position = SIMD3<Float>(0, 2, 0)   // Eye position in first-person
    var fpYaw: Float = 0                   // Horizontal rotation (radians)
    var fpPitch: Float = 0                 // Vertical rotation (radians, clamped)
    var verticalVelocity: Float = 0        // Vertical velocity for gravity/jumping

    // Movement constants (from Constants.Movement)
    var playerHeight: Float { Constants.Movement.playerHeight }
    var walkSpeed: Float { Constants.Movement.walkSpeed }
    var sprintSpeed: Float { Constants.Movement.sprintSpeed }
    var isSprinting: Bool = false
    var mouseSensitivity: Float { Constants.Movement.mouseSensitivity }
    var maxPitch: Float { Constants.Movement.maxPitch }

    // Grapple state
    var isGrappling: Bool = false
    var grappleTarget: SIMD3<Float> = .zero
    var grappleSpeed: Float { Constants.Grapple.speed }
    var grappleArrivalDistance: Float { Constants.Grapple.arrivalDistance }

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

    // MARK: - Plane Piloting
    enum PilotingMode {
        case none
        case flyingPlane(index: Int)
    }

    struct PlaneFlightState {
        var position: SIMD3<Float>
        var velocity: SIMD3<Float>
        var pitch: Float = 0          // Nose up/down (radians)
        var roll: Float = 0           // Bank left/right (radians)
        var yaw: Float = 0            // Heading (radians)
        var isBoosting: Bool = false

        // Physics constants (delegated to Constants.PlanePhysics)
        static var baseThrust: Float { Constants.PlanePhysics.baseThrust }
        static var boostThrust: Float { Constants.PlanePhysics.boostThrust }
        static var gravity: Float { Constants.PlanePhysics.gravity }
        static var pitchRate: Float { Constants.PlanePhysics.pitchRate }
        static var rollRate: Float { Constants.PlanePhysics.rollRate }
        static var maxPitch: Float { Constants.PlanePhysics.maxPitch }
        static var maxRoll: Float { Constants.PlanePhysics.maxRoll }
        static var liftCoefficient: Float { Constants.PlanePhysics.liftCoefficient }
        static var dragCoefficient: Float { Constants.PlanePhysics.dragCoefficient }
        static var minSpeed: Float { Constants.PlanePhysics.minSpeed }
        static var maxSpeed: Float { Constants.PlanePhysics.maxSpeed }
        static var boostMaxSpeed: Float { Constants.PlanePhysics.boostMaxSpeed }

        var forwardVector: SIMD3<Float> {
            SIMD3<Float>(
                cos(pitch) * sin(yaw),
                sin(pitch),
                cos(pitch) * cos(yaw)
            )
        }

        var speed: Float {
            simd_length(velocity)
        }
    }

    var pilotingMode: PilotingMode = .none
    var planeFlightState: PlaneFlightState?
    var thirdPersonCameraPosition: SIMD3<Float> = .zero
    var cameraLookOffset: SIMD2<Float> = .zero        // Mouse look offset (yaw, pitch)
    var thirdPersonDistance: Float { Constants.PlanePhysics.thirdPersonDistance }
    var thirdPersonHeight: Float { Constants.PlanePhysics.thirdPersonHeight }
    let maxLookOffset: Float = 0.5                    // Max radians for mouse look freedom

    var moveSpeed: Float {
        isSprinting ? sprintSpeed : walkSpeed
    }

    // Physics constants (from Constants.Movement)
    var gravity: Float { Constants.Movement.gravity }
    var jumpVelocity: Float { Constants.Movement.jumpVelocity }
    var groundLevel: Float { Constants.Movement.groundLevel }

    // Isometric constants (from Constants.Camera)
    private var isoPitch: Float { Constants.Camera.isometricPitch }
    private var isoYaw: Float { Constants.Camera.isometricYaw }

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
        distance = max(Constants.Camera.minDistance, distance - delta * 20)
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
            let playerRadius = Constants.Movement.playerRadius
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

    // MARK: - Plane Piloting Methods

    /// Board a plane and enter piloting mode
    func boardPlane(index: Int, planePosition: SIMD3<Float>, planeYaw: Float) {
        guard isFirstPerson else { return }

        // Initialize flight state
        let initialSpeed: Float = 50.0
        let forwardDir = SIMD3<Float>(sin(planeYaw), 0, cos(planeYaw))
        planeFlightState = PlaneFlightState(
            position: planePosition,
            velocity: forwardDir * initialSpeed,
            pitch: 0,
            roll: 0,
            yaw: planeYaw,
            isBoosting: false
        )

        pilotingMode = .flyingPlane(index: index)
        thirdPersonCameraPosition = planePosition - forwardDir * thirdPersonDistance + SIMD3<Float>(0, thirdPersonHeight, 0)
        cameraLookOffset = .zero  // Reset mouse look

        // Clear grapple state
        isGrappling = false
        grappleAttachment = .none
    }

    /// Exit the plane and return to first-person falling mode
    func exitPlane() -> SIMD3<Float> {
        guard case .flyingPlane(_) = pilotingMode,
              let flightState = planeFlightState else {
            return position
        }

        let exitPosition = flightState.position
        pilotingMode = .none
        planeFlightState = nil

        // Set player position to plane position
        position = exitPosition
        verticalVelocity = 0
        isFlying = false  // Start falling

        return exitPosition
    }

    /// Check if currently piloting a plane
    var isPilotingPlane: Bool {
        if case .flyingPlane(_) = pilotingMode { return true }
        return false
    }

    /// Update plane physics based on control inputs
    func updatePlanePhysics(deltaTime: Float, pitchInput: Float, rollInput: Float, isBoosting: Bool) {
        guard case .flyingPlane(_) = pilotingMode,
              var state = planeFlightState else { return }

        let dt = deltaTime

        // 1. Apply control inputs to orientation
        let pitchDelta = pitchInput * PlaneFlightState.pitchRate * dt
        let rollDelta = rollInput * PlaneFlightState.rollRate * dt

        state.pitch = max(-PlaneFlightState.maxPitch, min(PlaneFlightState.maxPitch, state.pitch + pitchDelta))
        state.roll = max(-PlaneFlightState.maxRoll, min(PlaneFlightState.maxRoll, state.roll + rollDelta))

        // 2. Banking turns: roll affects yaw rate (negated to match coordinate system)
        let bankTurnRate = -sin(state.roll) * 0.8
        state.yaw += bankTurnRate * dt

        // Wrap yaw to 0..2π
        while state.yaw < 0 { state.yaw += 2 * .pi }
        while state.yaw >= 2 * .pi { state.yaw -= 2 * .pi }

        // 3. Calculate forward direction from orientation
        let forward = state.forwardVector

        // 4. Calculate forces
        let speed = state.speed

        // Thrust
        let thrustMagnitude = isBoosting ? PlaneFlightState.boostThrust : PlaneFlightState.baseThrust
        let thrust = forward * thrustMagnitude

        // Lift (depends on speed and roll - banking reduces effective lift)
        let liftMagnitude = speed * PlaneFlightState.liftCoefficient * cos(state.roll)
        let lift = SIMD3<Float>(0, liftMagnitude, 0)

        // Drag (opposes velocity, proportional to speed squared)
        var drag = SIMD3<Float>.zero
        if speed > 0.1 {
            drag = -simd_normalize(state.velocity) * speed * speed * PlaneFlightState.dragCoefficient
        }

        // Gravity
        let gravity = SIMD3<Float>(0, -PlaneFlightState.gravity, 0)

        // 5. Sum forces and update velocity
        let totalForce = thrust + lift + drag + gravity
        state.velocity += totalForce * dt

        // 6. Speed limits
        let maxSpeed = isBoosting ? PlaneFlightState.boostMaxSpeed : PlaneFlightState.maxSpeed
        let currentSpeed = simd_length(state.velocity)
        if currentSpeed > maxSpeed {
            state.velocity = simd_normalize(state.velocity) * maxSpeed
        }
        // Minimum speed (stall prevention while airborne)
        if currentSpeed < PlaneFlightState.minSpeed && state.position.y > 10 {
            state.velocity = simd_normalize(state.velocity) * PlaneFlightState.minSpeed
        }

        // 7. Update position
        state.position += state.velocity * dt

        // 8. Minimum altitude (don't crash into ground)
        if state.position.y < 5.0 {
            state.position.y = 5.0
            state.velocity.y = max(0, state.velocity.y)
            state.pitch = max(0, state.pitch)  // Force nose up when low
        }

        // 9. Roll auto-leveling when no input
        if rollInput == 0 {
            state.roll *= 0.98
        }

        // 10. Pitch tends toward level flight when no input
        if pitchInput == 0 {
            state.pitch *= 0.99
        }

        state.isBoosting = isBoosting
        planeFlightState = state

        // Gradually return look offset to center
        cameraLookOffset *= 0.95
    }

    /// Adjust camera look offset while piloting (flight sim style mouse look)
    func adjustPlaneCameraLook(deltaX: Float, deltaY: Float) {
        cameraLookOffset.x -= deltaX * mouseSensitivity
        cameraLookOffset.y -= deltaY * mouseSensitivity

        // Clamp to max offset
        cameraLookOffset.x = max(-maxLookOffset, min(maxLookOffset, cameraLookOffset.x))
        cameraLookOffset.y = max(-maxLookOffset * 0.5, min(maxLookOffset, cameraLookOffset.y))
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
        // Third-person plane view
        if case .flyingPlane(_) = pilotingMode, let flightState = planeFlightState {
            // Camera always stays directly behind and above the plane (based on yaw only)
            let planeForward = SIMD3<Float>(sin(flightState.yaw), 0, cos(flightState.yaw))
            let cameraPos = flightState.position - planeForward * thirdPersonDistance + SIMD3<Float>(0, thirdPersonHeight, 0)

            // Look at the plane, with optional mouse look offset
            var lookTarget = flightState.position

            // Apply mouse look offset to look direction
            if cameraLookOffset != .zero {
                let lookDir = simd_normalize(lookTarget - cameraPos)
                let right = simd_normalize(simd_cross(SIMD3<Float>(0, 1, 0), lookDir))
                let up = simd_cross(lookDir, right)
                lookTarget = lookTarget + right * cameraLookOffset.x * 20.0 + up * cameraLookOffset.y * 20.0
            }

            return lookAt(eye: cameraPos, target: lookTarget, up: SIMD3<Float>(0, 1, 0))
        } else if isFirstPerson {
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
        let fov: Float = isFirstPerson ? Constants.Camera.firstPersonFOV : Constants.Camera.isometricFOV
        return perspective(fovY: fov, aspect: aspect, near: Constants.Camera.nearPlane, far: Constants.Camera.farPlane)
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
