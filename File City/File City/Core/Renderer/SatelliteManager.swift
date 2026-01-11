import Foundation
import simd
import QuartzCore
import Combine

final class SatelliteManager {
    let satelliteClickedSubject = PassthroughSubject<UUID, Never>()

    private struct Satellite {
        let id: UUID
        let sessionID: UUID
        var orbitAngle: Float
        var orbitSpeed: Float
        var orbitRadius: Float
        var orbitHeight: Float
        var state: ClaudeSession.SessionState
        var stateStartTime: CFTimeInterval
        var fadeProgress: Float
        var isExiting: Bool
    }

    private var satellites: [Satellite] = []
    private var cityCenter: SIMD3<Float> = .zero
    private var cityRadius: Float = 50.0
    private var lastUpdateTime: CFTimeInterval = 0

    // Visual constants
    private let baseOrbitRadiusMultiplier: Float = 1.3
    private let orbitHeightRange: ClosedRange<Float> = 120.0...160.0
    private let baseOrbitSpeed: Float = 0.12
    private let sizeMultiplier: Float = 3.0

    func setCityBounds(center: SIMD3<Float>, radius: Float) {
        self.cityCenter = center
        self.cityRadius = max(radius, 30.0)
    }

    func spawn(sessionID: UUID) {
        let angle = Float.random(in: 0...(Float.pi * 2))
        let orbitRadius = cityRadius * baseOrbitRadiusMultiplier + Float.random(in: -10...10)
        let height = Float.random(in: orbitHeightRange)
        let speedVariation = Float.random(in: 0.8...1.2)

        let satellite = Satellite(
            id: UUID(),
            sessionID: sessionID,
            orbitAngle: angle,
            orbitSpeed: baseOrbitSpeed * speedVariation,
            orbitRadius: orbitRadius,
            orbitHeight: height,
            state: .launching,
            stateStartTime: CACurrentMediaTime(),
            fadeProgress: 0,
            isExiting: false
        )
        satellites.append(satellite)
    }

    func updateState(sessionID: UUID, state: ClaudeSession.SessionState) {
        NSLog("[SatelliteManager] updateState called: sessionID=%@, state=%d", sessionID.uuidString, state.rawValue)
        guard let index = satellites.firstIndex(where: { $0.sessionID == sessionID }) else {
            NSLog("[SatelliteManager] No satellite found for session %@", sessionID.uuidString)
            return
        }
        NSLog("[SatelliteManager] Updating satellite %d from state %d to %d", index, satellites[index].state.rawValue, state.rawValue)
        satellites[index].state = state
        satellites[index].stateStartTime = CACurrentMediaTime()
        if state == .exiting {
            satellites[index].isExiting = true
        }
    }

    func remove(sessionID: UUID) {
        if let index = satellites.firstIndex(where: { $0.sessionID == sessionID }) {
            satellites[index].isExiting = true
        }
    }

    struct SatelliteHitBox {
        let center: SIMD3<Float>
        let halfExtents: SIMD3<Float>  // Half-size in local space
        let rotationY: Float
        let sessionID: UUID
    }

    /// Returns oriented bounding boxes for all satellite parts for exact ray testing
    func getSatelliteHitBoxes() -> [SatelliteHitBox] {
        var hitBoxes: [SatelliteHitBox] = []
        let now = CACurrentMediaTime()

        for sat in satellites where !sat.isExiting {
            let pos = satellitePosition(sat)
            let fadeScale = sat.fadeProgress
            let stateScale: Float = sat.state == .generating ? (1.5 + 0.3 * sin(Float(now) * 6.0)) : 1.0
            let sz = sizeMultiplier * stateScale
            let bodyRotation = sat.orbitAngle + Float.pi / 2

            // Main body
            let bodyScale = SIMD3<Float>(2.0, 1.5, 2.5) * sz * fadeScale
            hitBoxes.append(SatelliteHitBox(
                center: pos,
                halfExtents: bodyScale * 0.5,
                rotationY: bodyRotation,
                sessionID: sat.sessionID
            ))

            // Solar panels
            let panelOffset: Float = 4.0 * sz
            let s = sin(bodyRotation)
            let c = cos(bodyRotation)
            let rightVec = SIMD3<Float>(c, 0, s)
            let panelScale = SIMD3<Float>(3.5, 0.1, 2.0) * sz * fadeScale

            // Right panel
            hitBoxes.append(SatelliteHitBox(
                center: pos + rightVec * panelOffset,
                halfExtents: panelScale * 0.5,
                rotationY: bodyRotation,
                sessionID: sat.sessionID
            ))

            // Left panel
            hitBoxes.append(SatelliteHitBox(
                center: pos - rightVec * panelOffset,
                halfExtents: panelScale * 0.5,
                rotationY: bodyRotation,
                sessionID: sat.sessionID
            ))

            // Antenna dish
            let antennaScale = SIMD3<Float>(0.8, 0.3, 0.8) * sz * fadeScale
            hitBoxes.append(SatelliteHitBox(
                center: pos + SIMD3<Float>(0, 1.8 * sz * fadeScale, 0),
                halfExtents: antennaScale * 0.5,
                rotationY: bodyRotation + Float(now * 0.5),
                sessionID: sat.sessionID
            ))

            // Beacon
            let beaconScale = SIMD3<Float>(0.4, 0.4, 0.4) * sz * fadeScale
            hitBoxes.append(SatelliteHitBox(
                center: pos + SIMD3<Float>(0, -1.2 * sz * fadeScale, 0),
                halfExtents: beaconScale * 0.5,
                rotationY: 0,
                sessionID: sat.sessionID
            ))
        }

        return hitBoxes
    }

    func clear() {
        satellites.removeAll()
    }

    func update() {
        let now = CACurrentMediaTime()
        if lastUpdateTime == 0 {
            lastUpdateTime = now
            return
        }
        let dt = Float(min(0.1, now - lastUpdateTime))
        lastUpdateTime = now

        for i in (0..<satellites.count).reversed() {
            var sat = satellites[i]

            // Update orbit position
            sat.orbitAngle += sat.orbitSpeed * dt
            if sat.orbitAngle > Float.pi * 2 {
                sat.orbitAngle -= Float.pi * 2
            }

            // Fade in/out
            if sat.isExiting {
                sat.fadeProgress = max(0, sat.fadeProgress - dt * 1.5)
                if sat.fadeProgress <= 0 {
                    satellites.remove(at: i)
                    continue
                }
            } else {
                sat.fadeProgress = min(1, sat.fadeProgress + dt * 2.0)
            }

            satellites[i] = sat
        }
    }

    func buildInstances() -> [VoxelInstance] {
        var instances: [VoxelInstance] = []
        let now = CACurrentMediaTime()

        for sat in satellites {
            let pos = satellitePosition(sat)
            let glowIntensity = calculateGlow(state: sat.state, stateStartTime: sat.stateStartTime, now: now)
            let fadeScale = sat.fadeProgress
            let stateMaterial = glowMaterialID(for: sat.state)

            // Body rotation - face direction of travel
            let bodyRotation = sat.orbitAngle + Float.pi / 2

            // Make generating state more dramatic - satellite grows and pulses
            let stateScale: Float = sat.state == .generating ? (1.5 + 0.3 * sin(Float(now) * 6.0)) : 1.0

            // Main satellite body - color based on state
            let sz = sizeMultiplier * stateScale
            instances.append(VoxelInstance(
                position: pos,
                scale: SIMD3<Float>(2.0, 1.5, 2.5) * sz * fadeScale,
                rotationY: bodyRotation,
                rotationX: 0,
                rotationZ: 0,
                materialID: stateMaterial,
                highlight: glowIntensity * fadeScale,
                textureIndex: -1,
                shapeID: 20 // Satellite shape
            ))

            // Solar panels - extend on X axis (perpendicular to direction of travel)
            let panelOffset: Float = 4.0 * sz
            let s = sin(bodyRotation)
            let c = cos(bodyRotation)
            let rightVec = SIMD3<Float>(c, 0, s)

            // Right panel
            instances.append(VoxelInstance(
                position: pos + rightVec * panelOffset,
                scale: SIMD3<Float>(3.5, 0.1, 2.0) * sz * fadeScale,
                rotationY: bodyRotation,
                rotationX: 0,
                rotationZ: 0,
                materialID: 4, // Blue-ish for solar panels
                highlight: glowIntensity * 0.3 * fadeScale,
                textureIndex: -1,
                shapeID: 0
            ))

            // Left panel
            instances.append(VoxelInstance(
                position: pos - rightVec * panelOffset,
                scale: SIMD3<Float>(3.5, 0.1, 2.0) * sz * fadeScale,
                rotationY: bodyRotation,
                rotationX: 0,
                rotationZ: 0,
                materialID: 4,
                highlight: glowIntensity * 0.3 * fadeScale,
                textureIndex: -1,
                shapeID: 0
            ))

            // Antenna dish on top
            instances.append(VoxelInstance(
                position: pos + SIMD3<Float>(0, 1.8 * sz * fadeScale, 0),
                scale: SIMD3<Float>(0.8, 0.3, 0.8) * sz * fadeScale,
                rotationY: bodyRotation + Float(now * 0.5),
                rotationX: 0,
                rotationZ: 0,
                materialID: 0,
                highlight: glowIntensity * fadeScale,
                textureIndex: -1,
                shapeID: 5 // Cylinder for dish
            ))

            // Status light beacon
            let beaconPulse = sin(Float(now) * 4.0) * 0.3 + 0.7
            instances.append(VoxelInstance(
                position: pos + SIMD3<Float>(0, -1.2 * sz * fadeScale, 0),
                scale: SIMD3<Float>(0.4, 0.4, 0.4) * sz * fadeScale,
                rotationY: 0,
                rotationX: 0,
                rotationZ: 0,
                materialID: glowMaterialID(for: sat.state),
                highlight: glowIntensity * beaconPulse * fadeScale,
                textureIndex: -1,
                shapeID: 5 // Cylinder
            ))
        }

        return instances
    }

    private func satellitePosition(_ sat: Satellite) -> SIMD3<Float> {
        let x = cityCenter.x + cos(sat.orbitAngle) * sat.orbitRadius
        let z = cityCenter.z + sin(sat.orbitAngle) * sat.orbitRadius
        return SIMD3<Float>(x, sat.orbitHeight, z)
    }

    private func calculateGlow(state: ClaudeSession.SessionState, stateStartTime: CFTimeInterval, now: CFTimeInterval) -> Float {
        switch state {
        case .launching:
            // Dim, slowly pulsing orange
            let pulse = 0.3 + 0.2 * sin(Float(now) * 2.0)
            return pulse
        case .idle:
            // Steady bright blue glow
            return 0.8
        case .generating:
            // Very bright, fast pulsing cyan
            let pulse = 0.85 + 0.15 * sin(Float(now) * 8.0)
            return pulse
        case .exiting:
            // Fading out
            let elapsed = Float(now - stateStartTime)
            return max(0, 0.8 - elapsed * 0.5)
        }
    }

    private func glowMaterialID(for state: ClaudeSession.SessionState) -> UInt32 {
        switch state {
        case .launching:
            return 9 // Warm/orange tint
        case .idle:
            return 4 // Blue
        case .generating:
            return 2 // Red - very visible when working
        case .exiting:
            return 9 // Orange for exiting
        }
    }
}
