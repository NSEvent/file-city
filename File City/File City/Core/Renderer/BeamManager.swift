import Foundation
import simd
import QuartzCore

final class BeamManager {
    private struct Beam {
        let id = UUID()
        let position: SIMD3<Float>
        let startTime: CFTimeInterval
        let targetID: UUID
        let duration: CFTimeInterval = 2.0
    }

    private struct ElectricityBeam {
        let id = UUID()
        let fromPosition: SIMD3<Float>
        let toPosition: SIMD3<Float>
        let startTime: CFTimeInterval
        let duration: CFTimeInterval = 1.5
    }

    private var beams: [Beam] = []
    private var electricityBeams: [ElectricityBeam] = []
    
    func spawn(at position: SIMD3<Float>, targetID: UUID) {
        // Only spawn if not too close to another existing beam to prevent overlapping mess?
        // For now just spawn.
        let beam = Beam(position: position, startTime: CACurrentMediaTime(), targetID: targetID)
        beams.append(beam)
    }

    func spawnElectricity(from: SIMD3<Float>, to: SIMD3<Float>) {
        let electricityBeam = ElectricityBeam(fromPosition: from, toPosition: to, startTime: CACurrentMediaTime())
        electricityBeams.append(electricityBeam)
    }

    func getActiveBeamTargetIDs() -> Set<UUID> {
        var targets = Set<UUID>()
        for beam in beams {
            targets.insert(beam.targetID)
        }
        return targets
    }

    func clear() {
        beams.removeAll()
        electricityBeams.removeAll()
    }

    func update() {
        let now = CACurrentMediaTime()
        beams.removeAll { now - $0.startTime > $0.duration }
        electricityBeams.removeAll { now - $0.startTime > $0.duration }
    }
    
    func buildInstances() -> [VoxelInstance] {
        let now = CACurrentMediaTime()
        var instances: [VoxelInstance] = []
        
        for beam in beams {
            let age = Float(now - beam.startTime)
            let progress = age / Float(beam.duration)
            
            // Animation: Shoot up quickly, then fade out
            // Shoot up: Height grows 0 -> 100 in 0.2s?
            // Actually user said "Shoot a light beam directly up at the sky for 2 seconds"
            // Let's make it appear fully extended quickly or grow fast.
            
            let growTime: Float = 0.15
            let maxHeight: Float = 800.0
            
            var currentHeight: Float = maxHeight
            var alpha: Float = 1.0
            
            if age < growTime {
                currentHeight = maxHeight * (age / growTime)
            } else {
                // Fade out at end
                let fadeStart: Float = 1.5
                if age > fadeStart {
                    alpha = 1.0 - (age - fadeStart) / (2.0 - fadeStart)
                }
            }
            
            // Beam instance
            // Shape 12 will handle anchoring at bottom in shader
            instances.append(VoxelInstance(
                position: beam.position,
                scale: SIMD3<Float>(0.8, currentHeight, 0.8), // Thin beam
                rotationY: 0,
                rotationX: 0,
                rotationZ: 0,
                materialID: 0,
                highlight: alpha, // Use highlight for opacity/intensity control in shader
                textureIndex: -1,
                shapeID: 12
            ))
        }

        // Render electricity beams
        for ebeam in electricityBeams {
            let age = Float(now - ebeam.startTime)
            let progress = age / Float(ebeam.duration)

            // Fade in quickly, then out
            let fadeIn: Float = 0.1
            var alpha: Float = 1.0

            if age < fadeIn {
                alpha = age / fadeIn
            } else {
                let fadeStart: Float = 1.0
                if age > fadeStart {
                    alpha = 1.0 - (age - fadeStart) / (1.5 - fadeStart)
                }
            }

            // Create smooth continuous electric bolt
            let direction = ebeam.toPosition - ebeam.fromPosition
            let distance = length(direction)
            let normalizedDir = distance > 0 ? direction / distance : SIMD3<Float>(0, 1, 0)

            // Get perpendicular vectors for bolt width
            let up = abs(normalizedDir.y) < 0.9 ? SIMD3<Float>(0, 1, 0) : SIMD3<Float>(1, 0, 0)
            let right = normalize(cross(normalizedDir, up))
            let actualUp = normalize(cross(right, normalizedDir))

            // Create main bolt with smooth undulation
            let boltSegments = 20
            let boltWidth: Float = 1.2

            for i in 0..<boltSegments {
                let t0 = Float(i) / Float(boltSegments)
                let t1 = Float(i + 1) / Float(boltSegments)

                // Base positions along the line
                let basePos0 = ebeam.fromPosition + normalizedDir * distance * t0
                let basePos1 = ebeam.fromPosition + normalizedDir * distance * t1

                // Smooth undulation using sine waves at different frequencies
                let wave1 = sin(Float(now) * 8.0 + t0 * Float.pi * 6.0) * 0.4
                let wave2 = sin(Float(now) * 5.0 + t0 * Float.pi * 4.0 + 2.0) * 0.3
                let wave3 = sin(Float(now) * 12.0 + t0 * Float.pi * 8.0 + 4.0) * 0.2

                let offset0 = (right * (wave1 + wave2) + actualUp * wave3) * boltWidth
                let offset1 = (right * (sin(Float(now) * 8.0 + t1 * Float.pi * 6.0) * 0.4 +
                                       sin(Float(now) * 5.0 + t1 * Float.pi * 4.0 + 2.0) * 0.3) +
                             actualUp * sin(Float(now) * 12.0 + t1 * Float.pi * 8.0 + 4.0) * 0.2) * boltWidth

                let pos0 = basePos0 + offset0
                let pos1 = basePos1 + offset1

                let midPos = (pos0 + pos1) * 0.5
                let segDir = pos1 - pos0
                let segDist = length(segDir)

                // Render segment with extra bright cyan
                instances.append(VoxelInstance(
                    position: midPos,
                    scale: SIMD3<Float>(0.5, segDist + 0.1, 0.5),
                    rotationY: 0,
                    rotationX: 0,
                    rotationZ: 0,
                    materialID: 3, // Cyan/electric color
                    highlight: alpha * 2.0, // Very bright
                    textureIndex: -1,
                    shapeID: 5 // Cylinder
                ))
            }

            // Add secondary glow bolts for electric field effect
            let glowBolts = 2
            for g in 0..<glowBolts {
                let glowOffset = Float(g) * 0.5 - 0.25
                let glowSegments = 15

                for i in 0..<glowSegments {
                    let t0 = Float(i) / Float(glowSegments)
                    let t1 = Float(i + 1) / Float(glowSegments)

                    let basePos0 = ebeam.fromPosition + normalizedDir * distance * t0
                    let basePos1 = ebeam.fromPosition + normalizedDir * distance * t1

                    // Slightly different wave patterns for glow
                    let wave1 = sin(Float(now) * 7.0 + t0 * Float.pi * 5.0 + Float(g)) * 0.35
                    let wave2 = sin(Float(now) * 4.5 + t0 * Float.pi * 3.5 + 1.5 + Float(g)) * 0.25

                    let offset0 = (right * (wave1 + wave2) + actualUp * glowOffset) * 0.8
                    let offset1 = (right * (sin(Float(now) * 7.0 + t1 * Float.pi * 5.0 + Float(g)) * 0.35 +
                                           sin(Float(now) * 4.5 + t1 * Float.pi * 3.5 + 1.5 + Float(g)) * 0.25) +
                                 actualUp * glowOffset) * 0.8

                    let pos0 = basePos0 + offset0
                    let pos1 = basePos1 + offset1

                    let midPos = (pos0 + pos1) * 0.5
                    let segDir = pos1 - pos0
                    let segDist = length(segDir)

                    instances.append(VoxelInstance(
                        position: midPos,
                        scale: SIMD3<Float>(0.3, segDist + 0.05, 0.3),
                        rotationY: 0,
                        rotationX: 0,
                        rotationZ: 0,
                        materialID: 3,
                        highlight: alpha * 1.2, // Slightly dimmer glow
                        textureIndex: -1,
                        shapeID: 5
                    ))
                }
            }
        }

        return instances
    }
}
