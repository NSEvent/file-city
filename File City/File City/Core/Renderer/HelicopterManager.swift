import Foundation
import simd
import QuartzCore

final class HelicopterManager {
    private struct Helicopter {
        let id = UUID()
        var position: SIMD3<Float>
        let target: SIMD3<Float>
        var state: State = .inbound
        var velocity: SIMD3<Float> = .zero
        let textureIndex: Int32
        
        enum State {
            case inbound
            case hovering
            case outbound
        }
    }

    private struct Package {
        let id = UUID()
        var position: SIMD3<Float>
        var velocity: SIMD3<Float>
        let targetY: Float
    }

    private struct Explosion {
        let id = UUID()
        let position: SIMD3<Float>
        let startTime: CFTimeInterval
    }
    
    private var helicopters: [Helicopter] = []
    private var packages: [Package] = []
    private var explosions: [Explosion] = []
    
    // Config
    private let speed: Float = 25.0
    private let hoverDuration: Float = 0.5
    private var hoverTimers: [UUID: Float] = [:]
    private var lastUpdateTime: CFTimeInterval = 0
    
    func spawn(at target: SIMD3<Float>, textureIndex: Int32) {
        // Spawn high up and away
        let angle = Float.random(in: 0...Float.pi * 2)
        let distance: Float = 100.0
        let height: Float = 40.0
        let startPos = target + SIMD3<Float>(cos(angle) * distance, height, sin(angle) * distance)
        let hoverHeight: Float = 12.0
        
        let heli = Helicopter(
            position: startPos,
            target: target + SIMD3<Float>(0, hoverHeight, 0),
            textureIndex: textureIndex
        )
        helicopters.append(heli)
    }
    
    func update() {
        let now = CACurrentMediaTime()
        if lastUpdateTime == 0 {
            lastUpdateTime = now
            return
        }
        let dt = Float(min(0.1, now - lastUpdateTime))
        lastUpdateTime = now
        
        // Update Helicopters
        for i in (0..<helicopters.count).reversed() {
            var heli = helicopters[i]
            let toTarget = heli.target - heli.position
            let dist = simd_length(toTarget)
            
            switch heli.state {
            case .inbound:
                if dist < 0.5 {
                    heli.state = .hovering
                    hoverTimers[heli.id] = 0
                    // Drop package
                    packages.append(Package(
                        position: heli.position - SIMD3<Float>(0, 1.0, 0),
                        velocity: SIMD3<Float>(0, -5.0, 0),
                        targetY: heli.target.y - 12.0 // Approx building top
                    ))
                } else {
                    let dir = simd_normalize(toTarget)
                    heli.position += dir * speed * dt
                    heli.velocity = dir * speed
                }
            case .hovering:
                hoverTimers[heli.id, default: 0] += dt
                heli.velocity = .zero
                if hoverTimers[heli.id, default: 0] > hoverDuration {
                    heli.state = .outbound
                    // Pick a random exit point (continue in roughly same direction or random)
                    let angle = Float.random(in: 0...Float.pi * 2)
                    let exitDest = heli.position + SIMD3<Float>(cos(angle) * 150, 20, sin(angle) * 150)
                    
                    // We hijack target to store exit destination
                    // Re-construct with new target
                    heli = Helicopter(
                        position: heli.position,
                        target: exitDest,
                        state: .outbound,
                        velocity: heli.velocity,
                        textureIndex: heli.textureIndex
                    )
                }
            case .outbound:
                 let dir = simd_normalize(toTarget)
                 heli.position += dir * speed * dt
                 heli.velocity = dir * speed
                 if dist < 5.0 || dist > 200.0 { // Reached exit or far away
                     helicopters.remove(at: i)
                     hoverTimers.removeValue(forKey: heli.id)
                     continue
                 }
            }
            helicopters[i] = heli
        }
        
        // Update Packages
        for i in (0..<packages.count).reversed() {
            var pkg = packages[i]
            pkg.velocity += SIMD3<Float>(0, -18.0, 0) * dt // Heavy gravity
            pkg.position += pkg.velocity * dt
            
            if pkg.position.y <= pkg.targetY {
                // Explode
                explosions.append(Explosion(position: pkg.position, startTime: now))
                packages.remove(at: i)
            } else {
                packages[i] = pkg
            }
        }
        
        // Update Explosions (remove old)
        explosions.removeAll { now - $0.startTime > 0.8 }
    }
    
    func buildInstances() -> [VoxelInstance] {
        var instances: [VoxelInstance] = []
        let now = CACurrentMediaTime()
        
        // Helicopters
        for heli in helicopters {
            let rotationY: Float
            if simd_length_squared(heli.velocity) > 0.1 {
                let dir = simd_normalize(heli.velocity)
                rotationY = atan2(dir.x, dir.z)
            } else {
                rotationY = 0 // Keep previous or default? 0 is fine for hover default if not persisting
            }
            
            // Body
            instances.append(VoxelInstance(
                position: heli.position,
                scale: SIMD3<Float>(1.8, 1.4, 3.5),
                rotationY: rotationY,
                materialID: 0, 
                textureIndex: heli.textureIndex,
                shapeID: 6 // Plane body shape might look okay-ish, or just 0
            ))
            
            // Tail
            let tailOffset = SIMD3<Float>(sin(rotationY), 0, cos(rotationY)) * -2.0
            instances.append(VoxelInstance(
                position: heli.position + tailOffset + SIMD3<Float>(0, 0.5, 0),
                scale: SIMD3<Float>(0.4, 0.4, 2.0),
                rotationY: rotationY,
                materialID: 0,
                textureIndex: heli.textureIndex,
                shapeID: 0
            ))
            
            // Rotor
            instances.append(VoxelInstance(
                position: heli.position + SIMD3<Float>(0, 0.8, 0),
                scale: SIMD3<Float>(7.0, 0.1, 0.5),
                rotationY: Float(now * 25.0),
                materialID: 0,
                textureIndex: -1,
                shapeID: 0
            ))
            instances.append(VoxelInstance(
                position: heli.position + SIMD3<Float>(0, 0.8, 0),
                scale: SIMD3<Float>(0.5, 0.1, 7.0),
                rotationY: Float(now * 25.0),
                materialID: 0,
                textureIndex: -1,
                shapeID: 0
            ))
        }
        
        // Packages
        for pkg in packages {
             instances.append(VoxelInstance(
                position: pkg.position,
                scale: SIMD3<Float>(0.8, 0.8, 0.8),
                rotationY: Float(now * 5.0),
                materialID: 0,
                textureIndex: -1,
                shapeID: 0
            ))
        }
        
        // Explosions (Particles)
        for exp in explosions {
            let age = Float(now - exp.startTime)
            let progress = age / 0.8
            let count = 25
            for i in 0..<count {
                let seed = exp.id.hashValue &+ i
                var rng = SimpleRNG(seed: UInt64(bitPattern: Int64(seed)))
                let dir = SIMD3<Float>(rng.nextFloat() - 0.5, rng.nextFloat() - 0.5, rng.nextFloat() - 0.5)
                let normDir = simd_normalize(dir)
                let speed: Float = 8.0 * (1.0 - progress * 0.5)
                let pos = exp.position + normDir * speed * progress
                
                let scale = (1.0 - progress) * 0.8
                
                instances.append(VoxelInstance(
                    position: pos,
                    scale: SIMD3<Float>(scale, scale, scale),
                    rotationY: 0,
                    materialID: 0,
                    highlight: 1.0,
                    textureIndex: -1,
                    shapeID: 7 // Flame shape if available, else 0
                ))
            }
        }
        
        return instances
    }
    
    private struct SimpleRNG {
        var seed: UInt64
        mutating func nextFloat() -> Float {
            seed = (seed &* 1103515245 &+ 12345) & 0x7fffffff
            return Float(seed) / Float(0x7fffffff)
        }
    }
}
