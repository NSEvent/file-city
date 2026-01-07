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
    
    private var beams: [Beam] = []
    
    func spawn(at position: SIMD3<Float>, targetID: UUID) {
        // Only spawn if not too close to another existing beam to prevent overlapping mess?
        // For now just spawn.
        let beam = Beam(position: position, startTime: CACurrentMediaTime(), targetID: targetID)
        beams.append(beam)
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
    }
    
    func update() {
        let now = CACurrentMediaTime()
        beams.removeAll { now - $0.startTime > $0.duration }
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
        
        return instances
    }
}
