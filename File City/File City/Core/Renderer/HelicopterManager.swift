import Foundation
import simd
import QuartzCore
import Combine

final class HelicopterManager {
    /// Published when a package lands on a building (sends the target node ID)
    let packageLandedSubject = PassthroughSubject<UUID, Never>()
    private struct Helicopter {
        let id = UUID()
        var position: SIMD3<Float>
        let target: SIMD3<Float>
        let buildingTopY: Float
        let targetID: UUID
        var state: State = .inbound
        var velocity: SIMD3<Float> = .zero
        let textureIndex: Int32
        let blockInfo: BlockInfo?

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
        let targetID: UUID
        let blockInfo: BlockInfo?
    }

    private struct Explosion {
        let id = UUID()
        let position: SIMD3<Float>
        let startTime: CFTimeInterval
        var spawnedWorker: Bool = false
        let blockInfo: BlockInfo?
    }

    private struct BlockInfo {
        let position: SIMD3<Float>
        let footprint: SIMD2<Float>
        let height: Float
        let isFile: Bool  // Files have 1x1 footprint, workers stand on top
    }

    private struct ConstructionWorker {
        let id = UUID()
        var position: SIMD3<Float>
        var targetPosition: SIMD3<Float>
        let blockInfo: BlockInfo
        var state: State = .sliding
        let spawnTime: CFTimeInterval
        var idleTime: CFTimeInterval = 0
        var rotationY: Float = 0

        enum State {
            case sliding
            case idle
            case walking
        }
    }
    
    private var helicopters: [Helicopter] = []
    private var packages: [Package] = []
    private var explosions: [Explosion] = []
    private var workers: [ConstructionWorker] = []
    private var recentDeliveries: [UUID: CFTimeInterval] = [:]

    private let maxWorkers = 100
    
    // Config
    private let speed: Float = 25.0
    private let hoverDuration: Float = 0.5
    private var hoverTimers: [UUID: Float] = [:]
    private var lastUpdateTime: CFTimeInterval = 0
    
    func spawn(at target: SIMD3<Float>, targetID: UUID, textureIndex: Int32, footprint: SIMD2<Int32>, height: Int32) {
        // Spawn high up and away
        let angle = Float.random(in: 0...Float.pi * 2)
        let distance: Float = 100.0
        let hoverHeight = Float.random(in: 12.0...35.0)
        let startHeight = Float.random(in: 40.0...70.0)
        let startPos = target + SIMD3<Float>(cos(angle) * distance, startHeight, sin(angle) * distance)

        let blockInfo = BlockInfo(
            position: target,
            footprint: SIMD2<Float>(Float(footprint.x), Float(footprint.y)),
            height: Float(height),
            isFile: footprint.x == 1 && footprint.y == 1
        )

        let heli = Helicopter(
            position: startPos,
            target: target + SIMD3<Float>(0, hoverHeight, 0),
            buildingTopY: target.y,
            targetID: targetID,
            textureIndex: textureIndex,
            blockInfo: blockInfo
        )
        helicopters.append(heli)
    }

    func getActiveConstructionTargetIDs() -> Set<UUID> {
        var targets = Set<UUID>()
        let now = CACurrentMediaTime()

        // Inbound helicopters (construction in progress)
        for heli in helicopters where heli.state == .inbound {
            targets.insert(heli.targetID)
        }

        // Recent deliveries (construction wrapping up)
        for (id, time) in recentDeliveries {
            if now - time < 2.0 {
                targets.insert(id)
            }
        }

        return targets
    }

    /// Get helicopter positions and radii for hit testing
    func getHelicopterHitTargets() -> [(position: SIMD3<Float>, radius: Float)] {
        return helicopters.map { ($0.position, Float(4.0)) }  // Radius covers body + rotors
    }
    
    func clear() {
        helicopters.removeAll()
        packages.removeAll()
        explosions.removeAll()
        workers.removeAll()
        recentDeliveries.removeAll()
        hoverTimers.removeAll()
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
                        targetY: heli.buildingTopY,
                        targetID: heli.targetID,
                        blockInfo: heli.blockInfo
                    ))
                    recentDeliveries[heli.targetID] = now
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
                    let exitClimb = Float.random(in: 15.0...45.0)
                    let exitDest = heli.position + SIMD3<Float>(cos(angle) * 150, exitClimb, sin(angle) * 150)
                    
                    // We hijack target to store exit destination
                    // Re-construct with new target
                    heli = Helicopter(
                        position: heli.position,
                        target: exitDest,
                        buildingTopY: heli.buildingTopY,
                        targetID: heli.targetID,
                        state: .outbound,
                        velocity: heli.velocity,
                        textureIndex: heli.textureIndex,
                        blockInfo: heli.blockInfo
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
        
        // Cleanup old deliveries
        for (id, time) in recentDeliveries {
            if now - time > 3.0 {
                recentDeliveries.removeValue(forKey: id)
            }
        }
        
        // Update Packages
        for i in (0..<packages.count).reversed() {
            var pkg = packages[i]
            pkg.velocity += SIMD3<Float>(0, -18.0, 0) * dt // Heavy gravity
            pkg.position += pkg.velocity * dt
            
            if pkg.position.y <= pkg.targetY {
                // Explode and notify
                explosions.append(Explosion(position: pkg.position, startTime: now, blockInfo: pkg.blockInfo))
                packageLandedSubject.send(pkg.targetID)
                packages.remove(at: i)
            } else {
                packages[i] = pkg
            }
        }
        
        // Update Workers
        let slideSpeed: Float = 12.0
        let walkSpeed: Float = 2.0
        for i in 0..<workers.count {
            var worker = workers[i]
            let block = worker.blockInfo

            switch worker.state {
            case .sliding:
                // Slide down the building face (staying on the outside)
                worker.position.y -= slideSpeed * dt

                // Ensure worker stays outside building while sliding
                if !block.isFile {
                    let pushed = pushOutsideBuilding(worker.position, block: block)
                    worker.position.x = pushed.x
                    worker.position.z = pushed.z
                }

                let groundLevel: Float = block.isFile ? block.position.y : 0.0
                if worker.position.y <= groundLevel + 1.0 {
                    worker.position.y = groundLevel + 1.0
                    worker.state = .idle
                    worker.idleTime = now
                    // Set initial target position
                    worker.targetPosition = pickWorkerTarget(for: block)
                }

            case .idle:
                // Wait a bit then pick a new destination
                if now - worker.idleTime > Double.random(in: 1.5...4.0) {
                    worker.targetPosition = pickWorkerTarget(for: block)
                    worker.state = .walking
                }

            case .walking:
                let toTarget = worker.targetPosition - worker.position
                let horizDist = sqrt(toTarget.x * toTarget.x + toTarget.z * toTarget.z)
                if horizDist < 0.2 {
                    worker.state = .idle
                    worker.idleTime = now
                } else {
                    let dir = SIMD2<Float>(toTarget.x, toTarget.z) / horizDist
                    let moveX = dir.x * walkSpeed * dt
                    let moveZ = dir.y * walkSpeed * dt

                    var newPos = worker.position

                    if !block.isFile {
                        // Try to move, but slide along building walls
                        let halfX = block.footprint.x / 2.0 + 0.5
                        let halfZ = block.footprint.y / 2.0 + 0.5

                        // Try X movement
                        let testX = worker.position.x + moveX
                        let localX = testX - block.position.x
                        let localZ = worker.position.z - block.position.z
                        if abs(localX) >= halfX || abs(localZ) >= halfZ {
                            newPos.x = testX
                        }

                        // Try Z movement
                        let testZ = worker.position.z + moveZ
                        let localX2 = newPos.x - block.position.x
                        let localZ2 = testZ - block.position.z
                        if abs(localX2) >= halfX || abs(localZ2) >= halfZ {
                            newPos.z = testZ
                        }
                    } else {
                        newPos.x += moveX
                        newPos.z += moveZ
                    }

                    worker.position = newPos
                    worker.rotationY = atan2(-dir.x, dir.y)
                }
            }

            workers[i] = worker
        }

        // Update Explosions - spawn workers when explosions finish
        for i in (0..<explosions.count).reversed() {
            let age = now - explosions[i].startTime
            if age > 0.6 && !explosions[i].spawnedWorker {
                // Spawn a worker as the explosion finishes
                let exp = explosions[i]
                if let blockInfo = exp.blockInfo {
                    // Spawn at the edge of the building top, not center
                    let edgePos = pickBuildingEdgePosition(for: blockInfo, atTop: true)
                    let worker = ConstructionWorker(
                        position: edgePos,
                        targetPosition: edgePos,
                        blockInfo: blockInfo,
                        spawnTime: now
                    )
                    workers.append(worker)

                    // Remove oldest workers if over limit
                    while workers.count > maxWorkers {
                        workers.removeFirst()
                    }
                }
                explosions[i].spawnedWorker = true
            }
            if age > 0.8 {
                explosions.remove(at: i)
            }
        }
    }
    
    /// Pick a position at the edge of the building
    private func pickBuildingEdgePosition(for block: BlockInfo, atTop: Bool) -> SIMD3<Float> {
        let halfX = block.footprint.x / 2.0
        let halfZ = block.footprint.y / 2.0
        let margin: Float = 0.5  // Distance from building face

        let y: Float
        if atTop {
            y = block.position.y + 1.0  // Top of building
        } else if block.isFile {
            y = block.position.y + 1.0  // Files: stay on top
        } else {
            y = 1.0  // Ground level for folders
        }

        // Pick a random side
        let side = Int.random(in: 0...3)
        var x: Float
        var z: Float

        switch side {
        case 0: // Front (+Z side)
            x = Float.random(in: -halfX...halfX)
            z = halfZ + margin
        case 1: // Back (-Z side)
            x = Float.random(in: -halfX...halfX)
            z = -halfZ - margin
        case 2: // Right (+X side)
            x = halfX + margin
            z = Float.random(in: -halfZ...halfZ)
        default: // Left (-X side)
            x = -halfX - margin
            z = Float.random(in: -halfZ...halfZ)
        }

        return SIMD3<Float>(block.position.x + x, y, block.position.z + z)
    }

    /// Check if a position is inside the building footprint
    private func isInsideBuilding(_ pos: SIMD3<Float>, block: BlockInfo) -> Bool {
        let halfX = block.footprint.x / 2.0
        let halfZ = block.footprint.y / 2.0
        let localX = pos.x - block.position.x
        let localZ = pos.z - block.position.z
        return abs(localX) < halfX && abs(localZ) < halfZ
    }

    /// Push a position outside the building if it's inside
    private func pushOutsideBuilding(_ pos: SIMD3<Float>, block: BlockInfo) -> SIMD3<Float> {
        let halfX = block.footprint.x / 2.0
        let halfZ = block.footprint.y / 2.0
        let margin: Float = 0.5

        let localX = pos.x - block.position.x
        let localZ = pos.z - block.position.z

        // If outside, return as-is
        if abs(localX) >= halfX || abs(localZ) >= halfZ {
            return pos
        }

        // Find nearest edge and push to it
        let distToRight = halfX - localX
        let distToLeft = halfX + localX
        let distToFront = halfZ - localZ
        let distToBack = halfZ + localZ

        let minDist = min(distToRight, distToLeft, distToFront, distToBack)

        var newX = pos.x
        var newZ = pos.z

        if minDist == distToRight {
            newX = block.position.x + halfX + margin
        } else if minDist == distToLeft {
            newX = block.position.x - halfX - margin
        } else if minDist == distToFront {
            newZ = block.position.z + halfZ + margin
        } else {
            newZ = block.position.z - halfZ - margin
        }

        return SIMD3<Float>(newX, pos.y, newZ)
    }

    private func pickWorkerTarget(for block: BlockInfo) -> SIMD3<Float> {
        if block.isFile {
            // Files: workers stand on top, small meander area
            let y = block.position.y + 1.0
            let offsetX = Float.random(in: -0.3...0.3)
            let offsetZ = Float.random(in: -0.3...0.3)
            return SIMD3<Float>(block.position.x + offsetX, y, block.position.z + offsetZ)
        } else {
            // Folders: pick a position at ground level around the building
            return pickBuildingEdgePosition(for: block, atTop: false)
        }
    }

    func buildInstances() -> [VoxelInstance] {
        var instances: [VoxelInstance] = []
        let now = CACurrentMediaTime()
        
        // Helicopters
        for heli in helicopters {
            let rotationY: Float
            if simd_length_squared(heli.velocity) > 0.1 {
                let dir = simd_normalize(heli.velocity)
                // Shader rotates (0,0,1) to (-sin, 0, cos). To face dir, we need correct angle.
                // atan2(-x, z) gives us the angle that results in proper orientation
                rotationY = atan2(-dir.x, dir.z)
            } else {
                rotationY = 0
            }
            
            // Calculate forward vector based on shader's rotation logic:
            // x' = x*c - z*s
            // z' = x*s + z*c
            // Local forward (0,0,1) becomes (-sin(r), 0, cos(r))
            let s = sin(rotationY)
            let c = cos(rotationY)
            let forward = SIMD3<Float>(-s, 0, c)
            let right = SIMD3<Float>(c, 0, s) // Local (1,0,0) -> (c, 0, s)
            
            // Body (standard box, not plane shape which creates wings wider than rotors)
            instances.append(VoxelInstance(
                position: heli.position,
                scale: SIMD3<Float>(1.8, 1.4, 3.5),
                rotationY: rotationY,
                rotationX: 0,
                rotationZ: 0,
                materialID: 0,
                textureIndex: heli.textureIndex,
                shapeID: 0
            ))
            
            // Tail
            // Tail is behind, so -forward. Shortened and moved inward to maintain connection.
            let tailOffset = forward * -2.1
            instances.append(VoxelInstance(
                position: heli.position + tailOffset + SIMD3<Float>(0, 0.5, 0),
                scale: SIMD3<Float>(0.4, 0.4, 3.2),
                rotationY: rotationY,
                rotationX: 0,
                rotationZ: 0,
                materialID: 0,
                textureIndex: heli.textureIndex,
                shapeID: 0
            ))

            // Tail Rotor (perpendicular to main)
            // Position at the end of the tail boom (-2.1 - 1.6 = -3.7)
            let tailRotorPos = heli.position + forward * -3.7 + right * 0.25 + SIMD3<Float>(0, 0.6, 0)
            // Use fmod to keep spin angle small for GPU sin/cos precision
            let tailRotorSpin = Float(now.truncatingRemainder(dividingBy: 1000.0) * 40.0)

            instances.append(VoxelInstance(
                position: tailRotorPos,
                scale: SIMD3<Float>(0.1, 1.5, 0.2),
                rotationY: rotationY,
                rotationX: tailRotorSpin,
                rotationZ: 0,
                materialID: 0,
                textureIndex: -1,
                shapeID: 0
            ))
            instances.append(VoxelInstance(
                position: tailRotorPos,
                scale: SIMD3<Float>(0.1, 0.2, 1.5),
                rotationY: rotationY,
                rotationX: tailRotorSpin,
                rotationZ: 0,
                materialID: 0,
                textureIndex: -1,
                shapeID: 0
            ))

            // Main Rotor
            // Use fmod to keep spin angle small for GPU sin/cos precision
            let mainRotorSpin = Float(now.truncatingRemainder(dividingBy: 1000.0) * 25.0)
            let rotorY = heli.position.y + 1.0
            instances.append(VoxelInstance(
                position: SIMD3<Float>(heli.position.x, rotorY, heli.position.z),
                scale: SIMD3<Float>(7.0, 0.15, 0.5),
                rotationY: mainRotorSpin,
                rotationX: 0,
                rotationZ: 0,
                materialID: 0,
                textureIndex: -1,
                shapeID: 0
            ))
            instances.append(VoxelInstance(
                position: SIMD3<Float>(heli.position.x, rotorY, heli.position.z),
                scale: SIMD3<Float>(0.5, 0.15, 7.0),
                rotationY: mainRotorSpin,
                rotationX: 0,
                rotationZ: 0,
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
                rotationY: Float(now.truncatingRemainder(dividingBy: 1000.0) * 5.0),
                rotationX: 0,
                rotationZ: 0,
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
                    rotationX: 0,
                    rotationZ: 0,
                    materialID: 0,
                    highlight: 1.0,
                    textureIndex: -1,
                    shapeID: 7 // Flame shape if available, else 0
                ))
            }
        }

        // Construction Workers
        for worker in workers {
            // Body (blue overalls)
            instances.append(VoxelInstance(
                position: worker.position,
                scale: SIMD3<Float>(0.6, 1.0, 0.4),
                rotationY: worker.rotationY,
                rotationX: 0,
                rotationZ: 0,
                materialID: 4, // Blue-ish material
                highlight: 0,
                textureIndex: -1,
                shapeID: 0
            ))

            // Head
            instances.append(VoxelInstance(
                position: worker.position + SIMD3<Float>(0, 0.7, 0),
                scale: SIMD3<Float>(0.4, 0.4, 0.4),
                rotationY: worker.rotationY,
                rotationX: 0,
                rotationZ: 0,
                materialID: 9, // Skin tone
                highlight: 0,
                textureIndex: -1,
                shapeID: 0
            ))

            // Hard hat (yellow highlight)
            instances.append(VoxelInstance(
                position: worker.position + SIMD3<Float>(0, 1.0, 0),
                scale: SIMD3<Float>(0.5, 0.15, 0.5),
                rotationY: worker.rotationY,
                rotationX: 0,
                rotationZ: 0,
                materialID: 0,
                highlight: 0.8, // Yellow glow for hard hat
                textureIndex: -1,
                shapeID: 0
            ))
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
