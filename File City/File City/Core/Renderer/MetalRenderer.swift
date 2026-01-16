import Metal
import MetalKit
import simd
import CryptoKit
import Combine

final class MetalRenderer: NSObject, MTKViewDelegate {
    private let device: MTLDevice
    private let commandQueue: MTLCommandQueue
    private let pipelineState: MTLRenderPipelineState
    private let depthState: MTLDepthStencilState
    private let samplerState: MTLSamplerState
    private let cubeVertexBuffer: MTLBuffer

    // Sky rendering
    private let skyPipelineState: MTLRenderPipelineState
    private let skyDepthState: MTLDepthStencilState
    private let skyVertexBuffer: MTLBuffer

    struct SkyUniforms {
        var inverseViewProjection: simd_float4x4
        var time: Float
        var sunDirection: SIMD3<Float>
    }

    // Ground plane rendering
    private let groundPipelineState: MTLRenderPipelineState

    struct GroundUniforms {
        var viewProjection: simd_float4x4
        var cameraPosition: SIMD3<Float>
        var groundSize: Float
        var time: Float
        var fogDensity: Float
        var _pad: Float = 0
        var cityBoundsMin: SIMD2<Float>
        var cityBoundsMax: SIMD2<Float>
        var cityCenter: SIMD2<Float>
    }

    // City bounds for ground shader (updated when blocks change)
    private var cityBoundsMin: SIMD2<Float> = .zero
    private var cityBoundsMax: SIMD2<Float> = .zero
    private var cityCenter: SIMD2<Float> = .zero

    // Fog settings (0 = disabled)
    private let fogDensity: Float = 0.0
    private var textureArray: MTLTexture?
    private var instanceBuffer: MTLBuffer?
    private var instanceCount: Int = 0
    private let roadTextureIndex: Int32 = 32
    private let carTextureIndex: Int32 = 33
    private let planeTextureIndex: Int32 = 34
    private let fontTextureIndex: Int32 = 35
    private var signpostInstanceBuffer: MTLBuffer?
    private var signpostInstanceCount: Int = 0
    private var signLabelTextureArray: MTLTexture?
    private var signLabelIndexByNodeID: [UUID: Int] = [:]
    private let gitTowerMaterialID: UInt32 = 8
    private let gitCleanMaterialID: UInt32 = 6
    private var roadInstanceBuffer: MTLBuffer?
    private var roadInstanceCount: Int = 0
    private var carInstanceBuffer: MTLBuffer?
    private var carInstanceCount: Int = 0
    private var carPaths: [CarPath] = []
    private var planeInstanceBuffer: MTLBuffer?
    private var planeInstanceCount: Int = 0
    private var planePaths: [PlanePath] = []
    private var planeOffsets: [Float] = []
    private var lastPlaneUpdateTime: CFTimeInterval = CACurrentMediaTime()
    private var hoveredPlaneIndex: Int?

    // Plane piloting
    private(set) var pilotedPlaneIndex: Int?
    var pilotedPlaneFlightState: Camera.PlaneFlightState?
    private let helicopterManager = HelicopterManager()

    /// Expose package landing events for LOC counting
    var packageLandedPublisher: AnyPublisher<UUID, Never> {
        helicopterManager.packageLandedSubject.eraseToAnyPublisher()
    }
    private let beamManager = BeamManager()
    private let satelliteManager = SatelliteManager()
    private var helicopterInstanceBuffer: MTLBuffer?
    private var helicopterInstanceCount: Int = 0
    private var beamInstanceBuffer: MTLBuffer?
    private var beamInstanceCount: Int = 0
    private var satelliteInstanceBuffer: MTLBuffer?
    private var satelliteInstanceCount: Int = 0
    private var gitBeaconBoxes: [BeaconPicker.Box] = []
    private let beaconHitInflation: Float = 1.0
    private var blocks: [CityBlock] = []

    // Plane explosions
    private var planeExplosions: [PlaneExplosion] = []
    private var explodedPlaneIndices: Set<Int> = []
    private var explosionDebrisBuffer: MTLBuffer?
    private var explosionDebrisCount: Int = 0
    
    // Banner
    private var bannerText: String = ""
    private var bannerTextureIndex: Int = -1

    // Cached state for continuous updates
    private var lastSelectedNodeIDs: Set<UUID> = []
    private var lastHoveredNodeID: UUID?
    private var lastHoveredBeaconNodeID: UUID?
    private var lastActivityByNodeID: [UUID: NodeActivityPulse] = [:]
    private var lastActivityNow: CFTimeInterval = 0
    private var lastActivityDuration: CFTimeInterval = 0
    private var lastTargetedNodeIDs: Set<UUID> = []
    private var lastLocByNodeID: [UUID: Int] = [:]

    // LOC Flag textures
    private var locFlagTextureArray: MTLTexture?
    private var locFlagIndexByNodeID: [UUID: Int] = [:]
    private var locFlagTextureIndexByLOC: [Int: Int] = [:]  // LOC value -> texture array index

    let camera = Camera()

    struct Vertex {
        let position: SIMD3<Float>
        let normal: SIMD3<Float>
        let uv: SIMD2<Float>
    }

    struct Uniforms {
        var viewProjection: simd_float4x4
        var time: Float
        var fogDensity: Float
        var _pad: SIMD2<Float> = .zero
        var cameraPosition: SIMD3<Float>
        var _pad2: Float = 0
    }

    private struct CarPath {
        let start: SIMD3<Float>
        let end: SIMD3<Float>
        let speed: Float
        let phase: Float
        let scale: SIMD3<Float>
        let colorIndex: UInt32  // Index into car color palette (0-11)
    }

    // Number of instances per car: body + glass + 4 wheels + headlights + taillights = 8
    private let instancesPerCar = 8

    private struct PlanePath {
        let waypoints: [SIMD3<Float>]
        let segmentLengths: [Float]
        let totalLength: Float
        let speed: Float
        let phase: Float
        let scale: SIMD3<Float>
    }

    private struct PlaneDebris {
        var position: SIMD3<Float>
        var velocity: SIMD3<Float>
        var rotationY: Float
        var rotationVelocity: Float
        var scale: SIMD3<Float>
        var textureIndex: Int32
        var shapeID: Int32
        var life: Float  // 0 to 1, decreasing
    }

    private struct PlaneExplosion {
        var debris: [PlaneDebris]
        var startTime: CFTimeInterval
        let duration: CFTimeInterval = 2.5
        let planeIndex: Int
    }

    // Crashing planes (abandoned after player exits)
    private struct CrashingPlane {
        var position: SIMD3<Float>
        var velocity: SIMD3<Float>
        var pitch: Float
        var roll: Float
        var yaw: Float
        let scale: SIMD3<Float>
        let planeIndex: Int
    }
    private var crashingPlanes: [CrashingPlane] = []

    init?(view: MTKView) {
        guard let device = MTLCreateSystemDefaultDevice(),
              let commandQueue = device.makeCommandQueue(),
              let library = device.makeDefaultLibrary() else {
            return nil
        }
        self.device = device
        self.commandQueue = commandQueue

        let descriptor = MTLRenderPipelineDescriptor()
        descriptor.vertexFunction = library.makeFunction(name: "vertex_main")
        descriptor.fragmentFunction = library.makeFunction(name: "fragment_main_v2")
        descriptor.colorAttachments[0].pixelFormat = view.colorPixelFormat
        descriptor.depthAttachmentPixelFormat = view.depthStencilPixelFormat
        
        // Enable blending
        descriptor.colorAttachments[0].isBlendingEnabled = true
        descriptor.colorAttachments[0].sourceRGBBlendFactor = .sourceAlpha
        descriptor.colorAttachments[0].destinationRGBBlendFactor = .oneMinusSourceAlpha
        descriptor.colorAttachments[0].rgbBlendOperation = .add
        descriptor.colorAttachments[0].sourceAlphaBlendFactor = .sourceAlpha
        descriptor.colorAttachments[0].destinationAlphaBlendFactor = .oneMinusSourceAlpha
        descriptor.colorAttachments[0].alphaBlendOperation = .add
        
        descriptor.vertexDescriptor = MetalRenderer.vertexDescriptor()

        do {
            pipelineState = try device.makeRenderPipelineState(descriptor: descriptor)
        } catch {
            return nil
        }

        let depthDescriptor = MTLDepthStencilDescriptor()
        depthDescriptor.depthCompareFunction = .less
        depthDescriptor.isDepthWriteEnabled = true
        guard let depthState = device.makeDepthStencilState(descriptor: depthDescriptor) else {
            return nil
        }
        self.depthState = depthState
        
        let samplerDescriptor = MTLSamplerDescriptor()
        samplerDescriptor.minFilter = .linear
        samplerDescriptor.magFilter = .linear
        samplerDescriptor.mipFilter = .linear
        samplerDescriptor.sAddressMode = .repeat
        samplerDescriptor.tAddressMode = .repeat
        guard let samplerState = device.makeSamplerState(descriptor: samplerDescriptor) else {
            return nil
        }
        self.samplerState = samplerState

        let cubeVertices = MetalRenderer.buildCubeVertices()
        guard let cubeVertexBuffer = device.makeBuffer(bytes: cubeVertices, length: MemoryLayout<Vertex>.stride * cubeVertices.count, options: []) else {
            return nil
        }
        self.cubeVertexBuffer = cubeVertexBuffer

        // Sky pipeline setup
        let skyDescriptor = MTLRenderPipelineDescriptor()
        skyDescriptor.vertexFunction = library.makeFunction(name: "sky_vertex")
        skyDescriptor.fragmentFunction = library.makeFunction(name: "sky_fragment")
        skyDescriptor.colorAttachments[0].pixelFormat = view.colorPixelFormat
        skyDescriptor.depthAttachmentPixelFormat = view.depthStencilPixelFormat

        let skyVertexDescriptor = MTLVertexDescriptor()
        skyVertexDescriptor.attributes[0].format = .float2
        skyVertexDescriptor.attributes[0].offset = 0
        skyVertexDescriptor.attributes[0].bufferIndex = 0
        skyVertexDescriptor.layouts[0].stride = MemoryLayout<SIMD2<Float>>.stride
        skyDescriptor.vertexDescriptor = skyVertexDescriptor

        do {
            skyPipelineState = try device.makeRenderPipelineState(descriptor: skyDescriptor)
        } catch {
            return nil
        }

        // Sky depth state: always pass, no write (sky is always behind everything)
        let skyDepthDescriptor = MTLDepthStencilDescriptor()
        skyDepthDescriptor.depthCompareFunction = .always
        skyDepthDescriptor.isDepthWriteEnabled = false
        guard let skyDepthState = device.makeDepthStencilState(descriptor: skyDepthDescriptor) else {
            return nil
        }
        self.skyDepthState = skyDepthState

        // Fullscreen quad for sky (clip space coordinates)
        let skyQuadVertices: [SIMD2<Float>] = [
            SIMD2<Float>(-1, -1), SIMD2<Float>(1, -1), SIMD2<Float>(-1, 1),
            SIMD2<Float>(-1, 1), SIMD2<Float>(1, -1), SIMD2<Float>(1, 1)
        ]
        guard let skyVertexBuffer = device.makeBuffer(bytes: skyQuadVertices, length: MemoryLayout<SIMD2<Float>>.stride * skyQuadVertices.count, options: []) else {
            return nil
        }
        self.skyVertexBuffer = skyVertexBuffer

        // Ground plane pipeline (uses same vertex descriptor as sky)
        let groundDescriptor = MTLRenderPipelineDescriptor()
        groundDescriptor.vertexFunction = library.makeFunction(name: "ground_vertex")
        groundDescriptor.fragmentFunction = library.makeFunction(name: "ground_fragment")
        groundDescriptor.colorAttachments[0].pixelFormat = view.colorPixelFormat
        groundDescriptor.depthAttachmentPixelFormat = view.depthStencilPixelFormat
        groundDescriptor.vertexDescriptor = skyVertexDescriptor  // Same 2D position layout

        do {
            groundPipelineState = try device.makeRenderPipelineState(descriptor: groundDescriptor)
        } catch {
            return nil
        }

        super.init()
        loadTextures()
        view.device = device
        view.delegate = self
    }

    private func loadTextures() {
        var sourceTextures: [MTLTexture] = []
        let textureCount = 36  // +1 for font atlas

        // Semantic names we want to ensure are in the palette
        let semanticNames = [
            "File City", "AppShell", "Core",
            "tiktok-peter", "imsg", "pokemon-red-rust", "bloom-filter-python", "rust",
            "ai-bot", "bank-finance", "real-estate", "audio-voice", "camera-photo", "web-chrome",
            "swift-file", "code-json", "text-doc", "image-file-png",
            "audio_file_mp3", "video_file_mp4", "archive_file_zip", "db_file_sql"
        ]

        for i in 0..<textureCount {
            let seed: String
            if i < semanticNames.count {
                seed = semanticNames[i]
            } else if i == Int(roadTextureIndex) {
                seed = "road-asphalt"
            } else if i == Int(carTextureIndex) {
                seed = "car-paint"
            } else if i == Int(planeTextureIndex) {
                seed = "plane-body"
            } else if i == Int(fontTextureIndex) {
                // Font atlas - generate separately
                if let fontTex = TextureGenerator.generateFontAtlas(device: device) {
                    sourceTextures.append(fontTex)
                }
                continue
            } else {
                seed = "Style \(i)"
            }

            if let tex = TextureGenerator.generateTexture(device: device, seed: seed) {
                sourceTextures.append(tex)
            }
        }
        
        guard !sourceTextures.isEmpty, let first = sourceTextures.first else { return }

        // Calculate mipmap levels
        let maxDim = max(first.width, first.height)
        let mipmapLevels = Int(log2(Double(maxDim))) + 1

        let descriptor = MTLTextureDescriptor()
        descriptor.textureType = .type2DArray
        descriptor.pixelFormat = first.pixelFormat
        descriptor.width = first.width
        descriptor.height = first.height
        descriptor.arrayLength = sourceTextures.count
        descriptor.mipmapLevelCount = mipmapLevels
        descriptor.usage = [.shaderRead, .shaderWrite]  // shaderWrite for mipmap generation

        guard let arrayTex = device.makeTexture(descriptor: descriptor) else { return }

        guard let commandBuffer = commandQueue.makeCommandBuffer(),
              let blitEncoder = commandBuffer.makeBlitCommandEncoder() else { return }

        for (i, tex) in sourceTextures.enumerated() {
            blitEncoder.copy(from: tex, sourceSlice: 0, sourceLevel: 0,
                             sourceOrigin: MTLOrigin(x: 0, y: 0, z: 0),
                             sourceSize: MTLSize(width: tex.width, height: tex.height, depth: 1),
                             to: arrayTex, destinationSlice: i, destinationLevel: 0,
                             destinationOrigin: MTLOrigin(x: 0, y: 0, z: 0))
        }

        // Generate mipmaps for the entire texture array
        blitEncoder.generateMipmaps(for: arrayTex)

        blitEncoder.endEncoding()
        commandBuffer.commit()

        self.textureArray = arrayTex
    }

    func updateInstances(blocks: [CityBlock],
                         selectedNodeIDs: Set<UUID>,
                         hoveredNodeID: UUID?,
                         hoveredBeaconNodeID: UUID?,
                         activityByNodeID: [UUID: NodeActivityPulse],
                         activityNow: CFTimeInterval,
                         activityDuration: CFTimeInterval,
                         locByNodeID: [UUID: Int] = [:]) {
        // Cache state
        self.lastSelectedNodeIDs = selectedNodeIDs
        self.lastHoveredNodeID = hoveredNodeID
        self.lastHoveredBeaconNodeID = hoveredBeaconNodeID
        self.lastActivityByNodeID = activityByNodeID
        self.lastActivityNow = activityNow
        self.lastActivityDuration = activityDuration
        self.lastLocByNodeID = locByNodeID

        let blocksChanged = blocks != self.blocks
        self.blocks = blocks

        // Update city bounds for ground shader
        if blocksChanged && !blocks.isEmpty {
            var minX: Float = .greatestFiniteMagnitude
            var maxX: Float = -.greatestFiniteMagnitude
            var minZ: Float = .greatestFiniteMagnitude
            var maxZ: Float = -.greatestFiniteMagnitude
            for block in blocks {
                let halfX = Float(block.footprint.x) / 2
                let halfZ = Float(block.footprint.y) / 2
                minX = min(minX, block.position.x - halfX)
                maxX = max(maxX, block.position.x + halfX)
                minZ = min(minZ, block.position.z - halfZ)
                maxZ = max(maxZ, block.position.z + halfZ)
            }
            // Add some padding around the city
            let padding: Float = 5.0
            cityBoundsMin = SIMD2<Float>(minX - padding, minZ - padding)
            cityBoundsMax = SIMD2<Float>(maxX + padding, maxZ + padding)
            cityCenter = SIMD2<Float>((minX + maxX) / 2, (minZ + maxZ) / 2)

            // Update satellite orbit center
            let radius = max(maxX - minX, maxZ - minZ) / 2
            satelliteManager.setCityBounds(
                center: SIMD3<Float>(cityCenter.x, 0, cityCenter.y),
                radius: radius
            )
        }

        let cameraYaw = camera.wedgeYaw  // Use fixed yaw for wedge rotation
        let inboundTargets = helicopterManager.getActiveConstructionTargetIDs()
        let beamTargets = beamManager.getActiveBeamTargetIDs()
        self.lastTargetedNodeIDs = inboundTargets.union(beamTargets)
        
        var instances: [VoxelInstance] = blocks.map { block in
            let rotationY = rotationYForWedge(block: block, cameraYaw: cameraYaw)
            let isHovering = block.nodeID == hoveredNodeID || block.nodeID == hoveredBeaconNodeID
            let activity = activityByNodeID[block.nodeID]
            let activityStrength: Float
            let activityKind: Int32
            
            let isTargeted = inboundTargets.contains(block.nodeID)
            let isBeaming = beamTargets.contains(block.nodeID)
            
            if let activity {
                let elapsed = max(0, activityNow - activity.startedAt)
                let normalized = max(0, 1.0 - (elapsed / max(0.001, activityDuration)))
                activityStrength = Float(normalized)
                activityKind = activity.kind.rawValue
            } else if isTargeted {
                activityStrength = 1.0
                activityKind = 2 // Write/Orange/Construction
            } else if isBeaming {
                activityStrength = 1.0
                activityKind = 1 // Read/Blue
            } else {
                activityStrength = 0
                activityKind = 0
            }
            return VoxelInstance(
                position: SIMD3<Float>(block.position.x, block.position.y + Float(block.height) * 0.5, block.position.z),
                scale: SIMD3<Float>(Float(block.footprint.x), Float(block.height), Float(block.footprint.y)),
                rotationY: rotationY,
                rotationX: 0,
                rotationZ: 0,
                materialID: UInt32(block.materialID),
                highlight: selectedNodeIDs.contains(block.nodeID) ? 1.0 : 0.0,
                hover: isHovering ? 1.0 : 0.0,
                activity: activityStrength,
                activityKind: activityKind,
                textureIndex: block.textureIndex,
                shapeID: block.shapeID
            )
        }
        let gitTowerInstances = buildGitTowerInstances(blocks: blocks, selectedNodeIDs: selectedNodeIDs, hoveredBeaconNodeID: hoveredBeaconNodeID, locByNodeID: lastLocByNodeID)
        if !gitTowerInstances.isEmpty {
            instances.append(contentsOf: gitTowerInstances)
        }
        instanceCount = instances.count
        if instances.isEmpty {
            instanceBuffer = nil
            return
        }
        if blocksChanged {
            rebuildRoadsAndCars(blocks: blocks)
        }
        instanceBuffer = device.makeBuffer(bytes: instances, length: MemoryLayout<VoxelInstance>.stride * instances.count, options: [])
    }

    private func rebuildInstancesUsingCache() {
        updateInstances(blocks: self.blocks,
                        selectedNodeIDs: self.lastSelectedNodeIDs,
                        hoveredNodeID: self.lastHoveredNodeID,
                        hoveredBeaconNodeID: self.lastHoveredBeaconNodeID,
                        activityByNodeID: self.lastActivityByNodeID,
                        activityNow: self.lastActivityNow,
                        activityDuration: self.lastActivityDuration)
    }

    // Note: rotationYForWedge moved to GeometryHelpers.swift

    private func buildGitTowerInstances(blocks: [CityBlock], selectedNodeIDs: Set<UUID>, hoveredBeaconNodeID: UUID?, locByNodeID: [UUID: Int]) -> [VoxelInstance] {
        var topBlocks: [UUID: CityBlock] = [:]
        var topHeights: [UUID: Float] = [:]
        gitBeaconBoxes.removeAll()
        for block in blocks where block.isGitRepo {
            let topY = block.visualTopY
            if let existing = topHeights[block.nodeID], existing >= topY {
                continue
            }
            topHeights[block.nodeID] = topY
            topBlocks[block.nodeID] = block
        }
        guard !topBlocks.isEmpty else { return [] }

        // Rebuild LOC flag textures if LOC data changed
        rebuildLOCFlagTextures(blocks: Array(topBlocks.values), locByNodeID: locByNodeID)

        var instances: [VoxelInstance] = []
        instances.reserveCapacity(topBlocks.count * 5)  // 4 tower parts + 1 flag
        for block in topBlocks.values {
            let isSelected = selectedNodeIDs.contains(block.nodeID)
            let beaconHighlight: Float = (block.nodeID == hoveredBeaconNodeID || isSelected) ? 1.0 : 0.0
            let towerMaterialID = block.isGitClean ? gitCleanMaterialID : gitTowerMaterialID
            let footprintX = Float(block.footprint.x)
            let footprintZ = Float(block.footprint.y)
            let baseTopY = block.baseTopY
            let blockVisualTop = block.visualTopY
            var roofY = blockVisualTop
            if block.shapeID == 2 {
                roofY = baseTopY + (blockVisualTop - baseTopY) * 0.42
            }
            let baseX = block.position.x
            let baseZ = block.position.z
            let towerSize: Float = max(1.2, min(2.6, min(footprintX, footprintZ) * 0.35))
            var towerHeight: Float = max(2.0, towerSize * 2.2)
            let basePad: Float = 0.15
            var baseY = roofY + basePad
            let beaconSize = towerSize * 0.16
            var beaconOffsetX: Float = 0
            var beaconOffsetZ: Float = 0
            let rotationY = rotationYForWedge(block: block, cameraYaw: camera.wedgeYaw)
            if block.shapeID == 3 {
                beaconOffsetX = footprintX * 0.45
            } else if block.shapeID == 4 {
                beaconOffsetZ = footprintZ * 0.45
            }
            if block.shapeID == 3 || block.shapeID == 4 {
                let c = cos(rotationY)
                let s = sin(rotationY)
                let rotatedX = beaconOffsetX * c - beaconOffsetZ * s
                let rotatedZ = beaconOffsetX * s + beaconOffsetZ * c
                beaconOffsetX = rotatedX
                beaconOffsetZ = rotatedZ
                towerHeight *= 1.25
                // Adjust roofY to actual height at beacon offset (0.45 vs 0.5 edge)
                // The wedge slopes, so at 0.45 offset the roof is lower than at the edge
                let offsetRatio: Float = 0.45 / 0.5  // 0.9
                roofY = baseTopY + (blockVisualTop - baseTopY) * offsetRatio
                baseY = roofY + basePad
            }
            if block.shapeID == 2 {
                let tipY = blockVisualTop
                towerHeight = max(0.8, tipY - baseY)
            }
            let mastY = baseY + towerHeight * 0.5
            let crossbarY = baseY + towerHeight * 0.8
            var beaconY = baseY + towerHeight + beaconSize * 0.5
            if block.shapeID == 2 {
                beaconY = blockVisualTop + beaconSize * 0.5
            }
            let towerBaseX = baseX + beaconOffsetX
            let towerBaseZ = baseZ + beaconOffsetZ

            instances.append(VoxelInstance(
                position: SIMD3<Float>(towerBaseX, baseY, towerBaseZ),
                scale: SIMD3<Float>(towerSize * 0.55, towerSize * 0.2, towerSize * 0.55),
                rotationY: 0,
                rotationX: 0,
                rotationZ: 0,
                materialID: towerMaterialID,
                highlight: beaconHighlight,
                textureIndex: -1,
                shapeID: 5
            ))

            instances.append(VoxelInstance(
                position: SIMD3<Float>(towerBaseX, mastY, towerBaseZ),
                scale: SIMD3<Float>(towerSize * 0.18, towerHeight, towerSize * 0.18),
                rotationY: 0,
                rotationX: 0,
                rotationZ: 0,
                materialID: towerMaterialID,
                highlight: beaconHighlight,
                textureIndex: -1,
                shapeID: 5
            ))

            let crossbarX = baseX + beaconOffsetX
            let crossbarZ = baseZ + beaconOffsetZ
            instances.append(VoxelInstance(
                position: SIMD3<Float>(crossbarX, crossbarY, crossbarZ),
                scale: SIMD3<Float>(towerSize * 0.55, towerSize * 0.06, towerSize * 0.55),
                rotationY: 0,
                rotationX: 0,
                rotationZ: 0,
                materialID: towerMaterialID,
                highlight: beaconHighlight,
                textureIndex: -1,
                shapeID: 0
            ))

            instances.append(VoxelInstance(
                position: SIMD3<Float>(crossbarX, beaconY, crossbarZ),
                scale: SIMD3<Float>(beaconSize, beaconSize, beaconSize),
                rotationY: 0,
                rotationX: 0,
                rotationZ: 0,
                materialID: towerMaterialID,
                highlight: beaconHighlight,
                textureIndex: -1,
                shapeID: block.isGitClean ? 9 : 8
            ))

            // LOC Flag - positioned just below the beacon, flying to the side
            if let flagTexIndex = locFlagIndexByNodeID[block.nodeID] {
                let flagY = beaconY - beaconSize * 0.5 - towerSize * 0.3
                let flagWidth = towerSize * 1.8
                let flagHeight = towerSize * 0.9
                // Flag extends to the right of the mast
                let flagOffsetX = flagWidth * 0.5 + towerSize * 0.1
                instances.append(VoxelInstance(
                    position: SIMD3<Float>(towerBaseX + flagOffsetX, flagY, towerBaseZ),
                    scale: SIMD3<Float>(flagWidth, flagHeight, 0.05),
                    rotationY: 0,
                    rotationX: 0,
                    rotationZ: 0,
                    materialID: 0,
                    highlight: 0,
                    textureIndex: Int32(flagTexIndex),
                    shapeID: Constants.Shapes.locFlag
                ))
            }

            let nodeID = block.nodeID
            func addBeaconBox(x: Float, y: Float, z: Float, scale: SIMD3<Float>) {
                let half = scale * 0.5 * beaconHitInflation
                let minBounds = SIMD3<Float>(x, y, z) - half
                let maxBounds = SIMD3<Float>(x, y, z) + half
                gitBeaconBoxes.append(BeaconPicker.Box(
                    nodeID: nodeID,
                    min: minBounds,
                    max: maxBounds
                ))
            }
            addBeaconBox(x: towerBaseX, y: baseY, z: towerBaseZ,
                         scale: SIMD3<Float>(towerSize * 0.55, towerSize * 0.2, towerSize * 0.55))
            addBeaconBox(x: towerBaseX, y: mastY, z: towerBaseZ,
                         scale: SIMD3<Float>(towerSize * 0.18, towerHeight, towerSize * 0.18))
            addBeaconBox(x: crossbarX, y: crossbarY, z: crossbarZ,
                         scale: SIMD3<Float>(towerSize * 0.55, towerSize * 0.06, towerSize * 0.55))
            addBeaconBox(x: crossbarX, y: beaconY, z: crossbarZ,
                         scale: SIMD3<Float>(beaconSize, beaconSize, beaconSize))
        }

        return instances
    }

    // Note: visualTopY moved to CityBlock.visualTopY computed property

    private func rebuildLOCFlagTextures(blocks: [CityBlock], locByNodeID: [UUID: Int]) {
        // Collect all LOC values we need textures for
        var locValuesNeeded: Set<Int> = []
        for block in blocks {
            if let loc = locByNodeID[block.nodeID], loc > 0 {
                locValuesNeeded.insert(loc)
            }
        }

        // Check if we have all needed textures already (fast path for UUID changes without LOC changes)
        let missingLOCValues = locValuesNeeded.subtracting(Set(locFlagTextureIndexByLOC.keys))
        if missingLOCValues.isEmpty && locFlagTextureArray != nil {
            // All textures exist - just update nodeID mapping for current UUIDs
            var newIndexByNodeID: [UUID: Int] = [:]
            for block in blocks {
                guard let loc = locByNodeID[block.nodeID], loc > 0,
                      let texIndex = locFlagTextureIndexByLOC[loc] else { continue }
                newIndexByNodeID[block.nodeID] = texIndex
            }
            // Only update mapping if we found matches - avoids clearing when blocks/locByNodeID are out of sync
            // (can happen when $locByPath fires during a rescan that changes UUIDs)
            if !newIndexByNodeID.isEmpty || locFlagIndexByNodeID.isEmpty {
                locFlagIndexByNodeID = newIndexByNodeID
            }
            return
        }

        // Need to rebuild texture array - generate one texture per unique LOC value
        var newTextureIndexByLOC: [Int: Int] = [:]
        var textures: [MTLTexture] = []

        // Generate textures for unique LOC values
        for loc in locValuesNeeded.sorted() {
            guard let tex = TextureGenerator.generateLOCFlag(device: device, loc: loc) else { continue }
            newTextureIndexByLOC[loc] = textures.count
            textures.append(tex)
        }

        guard !textures.isEmpty, let first = textures.first else {
            // No textures generated - only clear if we genuinely have no LOC data
            // (Don't clear if this is just a blocks/locByNodeID sync issue)
            if locFlagTextureIndexByLOC.isEmpty {
                locFlagTextureArray = nil
                locFlagIndexByNodeID.removeAll()
            }
            return
        }

        // Build nodeID mapping
        var newIndexByNodeID: [UUID: Int] = [:]
        for block in blocks {
            guard let loc = locByNodeID[block.nodeID], loc > 0,
                  let texIndex = newTextureIndexByLOC[loc] else { continue }
            newIndexByNodeID[block.nodeID] = texIndex
        }

        let descriptor = MTLTextureDescriptor()
        descriptor.textureType = .type2DArray
        descriptor.pixelFormat = first.pixelFormat
        descriptor.width = first.width
        descriptor.height = first.height
        descriptor.arrayLength = textures.count
        descriptor.usage = .shaderRead

        guard let arrayTex = device.makeTexture(descriptor: descriptor) else { return }
        guard let commandBuffer = commandQueue.makeCommandBuffer(),
              let blitEncoder = commandBuffer.makeBlitCommandEncoder() else { return }

        for (i, tex) in textures.enumerated() {
            blitEncoder.copy(from: tex, sourceSlice: 0, sourceLevel: 0,
                             sourceOrigin: MTLOrigin(x: 0, y: 0, z: 0),
                             sourceSize: MTLSize(width: tex.width, height: tex.height, depth: 1),
                             to: arrayTex, destinationSlice: i, destinationLevel: 0,
                             destinationOrigin: MTLOrigin(x: 0, y: 0, z: 0))
        }

        blitEncoder.endEncoding()
        commandBuffer.commit()

        // Atomic swap - update all at once to prevent flashing
        // Only update nodeID mapping if we found matches (avoid clearing during sync issues)
        locFlagTextureIndexByLOC = newTextureIndexByLOC
        if !newIndexByNodeID.isEmpty || locFlagIndexByNodeID.isEmpty {
            locFlagIndexByNodeID = newIndexByNodeID
        }
        locFlagTextureArray = arrayTex
    }

    func setBannerText(_ text: String) {
        guard text != bannerText else { return }
        bannerText = text
        // Rebuild textures to include the new banner
        if !blocks.isEmpty {
            rebuildRoadsAndCars(blocks: blocks)
        }
    }

    func setHoveredPlane(index: Int?) {
        hoveredPlaneIndex = index
    }

    func explodePlane(index: Int) {
        guard index >= 0, index < planePaths.count else { return }
        guard !explodedPlaneIndices.contains(index) else { return }

        let path = planePaths[index]
        let now = CACurrentMediaTime()

        // Calculate current plane position
        let baseDistance = fmod(Float(now) * path.speed + path.phase, path.totalLength)
        let offset = index < planeOffsets.count ? planeOffsets[index] : 0
        let distance = fmod(baseDistance + offset, path.totalLength)
        let position = positionAlongPath(path: path, distance: distance)
        let nextDistance = fmod(distance + 1.0, path.totalLength)
        let nextPosition = positionAlongPath(path: path, distance: nextDistance)
        let direction = simd_normalize(nextPosition - position)
        let right = simd_normalize(SIMD3<Float>(-direction.z, 0, direction.x))
        let rotationY = atan2(direction.z, direction.x)

        var debris: [PlaneDebris] = []

        // Helper to create debris with random outward velocity
        func addDebris(pos: SIMD3<Float>, scale: SIMD3<Float>, texIndex: Int32, shape: Int32) {
            let randomAngle = Float.random(in: 0...(2 * .pi))
            let randomSpeed = Float.random(in: 8...20)
            let upSpeed = Float.random(in: 5...15)
            let velocity = SIMD3<Float>(
                cos(randomAngle) * randomSpeed,
                upSpeed,
                sin(randomAngle) * randomSpeed
            )
            let rotVel = Float.random(in: -8...8)
            debris.append(PlaneDebris(
                position: pos,
                velocity: velocity,
                rotationY: rotationY + Float.random(in: -0.5...0.5),
                rotationVelocity: rotVel,
                scale: scale * Float.random(in: 0.6...1.0),
                textureIndex: texIndex,
                shapeID: shape,
                life: 1.0
            ))
        }

        // Main fuselage - breaks into multiple pieces
        let bodyOffset = direction * (path.scale.x * 0.1)
        for _ in 0..<3 {
            let fragmentOffset = SIMD3<Float>(
                Float.random(in: -2...2),
                Float.random(in: -0.5...0.5),
                Float.random(in: -1...1)
            )
            addDebris(
                pos: position - bodyOffset + fragmentOffset,
                scale: SIMD3<Float>(path.scale.x * 0.3, path.scale.y, path.scale.z * 0.8),
                texIndex: planeTextureIndex,
                shape: 0
            )
        }

        // Wings
        addDebris(
            pos: position + SIMD3<Float>(0, 0.1, 0),
            scale: SIMD3<Float>(1.4, 0.08, 3.0),
            texIndex: planeTextureIndex,
            shape: 0
        )
        addDebris(
            pos: position + SIMD3<Float>(0, 0.1, 0),
            scale: SIMD3<Float>(1.4, 0.08, 3.0),
            texIndex: planeTextureIndex,
            shape: 0
        )

        // Thrusters
        let thrusterOffset = path.scale.z * 0.35
        addDebris(
            pos: position + right * thrusterOffset - SIMD3<Float>(0, 0.12, 0),
            scale: SIMD3<Float>(0.55, 0.25, 0.55),
            texIndex: planeTextureIndex,
            shape: 0
        )
        addDebris(
            pos: position - right * thrusterOffset - SIMD3<Float>(0, 0.12, 0),
            scale: SIMD3<Float>(0.55, 0.25, 0.55),
            texIndex: planeTextureIndex,
            shape: 0
        )

        // Tail pieces
        let tailBack = path.scale.x * 0.42
        addDebris(
            pos: position - bodyOffset - direction * tailBack + SIMD3<Float>(0, 0.15, 0),
            scale: SIMD3<Float>(1.0, 0.06, 2.8),
            texIndex: planeTextureIndex,
            shape: 0
        )
        addDebris(
            pos: position - bodyOffset - direction * tailBack + SIMD3<Float>(0, 0.55, 0),
            scale: SIMD3<Float>(1.2, 0.9, 0.08),
            texIndex: planeTextureIndex,
            shape: 0
        )

        // Banner segments - each becomes debris
        if bannerTextureIndex >= 0 {
            let ropeLen: Float = 2.5
            let segmentCount = 8
            let segmentLen: Float = 1.5
            let tailDist = distance - tailBack - ropeLen

            for i in 0..<segmentCount {
                let segDist = tailDist - Float(i) * segmentLen - segmentLen * 0.5
                var d = segDist
                if d < 0 { d += path.totalLength }
                let pos = positionAlongPath(path: path, distance: d)

                addDebris(
                    pos: pos,
                    scale: SIMD3<Float>(segmentLen, 3.0, 0.1),
                    texIndex: Int32(bannerTextureIndex),
                    shape: 0  // Use plain cube for debris, not banner shape
                )
            }
        }

        explodedPlaneIndices.insert(index)
        planeExplosions.append(PlaneExplosion(debris: debris, startTime: now, planeIndex: index))

        // Clear hover if this plane was hovered
        if hoveredPlaneIndex == index {
            hoveredPlaneIndex = nil
        }
    }

    private func updateExplosions(deltaTime: Float) {
        let now = CACurrentMediaTime()
        let gravity: Float = -25.0

        // Update each explosion
        for i in (0..<planeExplosions.count).reversed() {
            let elapsed = Float(now - planeExplosions[i].startTime)
            let progress = elapsed / Float(planeExplosions[i].duration)

            if progress >= 1.0 {
                // Respawn the plane on a new flight path
                let planeIndex = planeExplosions[i].planeIndex
                regeneratePlanePath(index: planeIndex)
                explodedPlaneIndices.remove(planeIndex)
                planeExplosions.remove(at: i)
                continue
            }

            // Update each debris piece
            for j in 0..<planeExplosions[i].debris.count {
                // Apply gravity
                planeExplosions[i].debris[j].velocity.y += gravity * deltaTime

                // Update position
                planeExplosions[i].debris[j].position += planeExplosions[i].debris[j].velocity * deltaTime

                // Update rotation
                planeExplosions[i].debris[j].rotationY += planeExplosions[i].debris[j].rotationVelocity * deltaTime

                // Fade out life
                planeExplosions[i].debris[j].life = 1.0 - progress
            }
        }
    }

    private func updateCrashingPlanes(deltaTime: Float) {
        let gravity: Float = Constants.Movement.gravity  // Same as player: -30.0
        let groundLevel: Float = 0.0

        for i in (0..<crashingPlanes.count).reversed() {
            let speed = simd_length(crashingPlanes[i].velocity)

            // Wing physics - lift based on speed and roll (reduced effectiveness, plane is damaged)
            let liftCoefficient: Float = 0.15  // Half of normal plane lift
            let roll = crashingPlanes[i].roll
            let liftMagnitude = speed * liftCoefficient * cos(roll)
            let lift = SIMD3<Float>(0, liftMagnitude, 0)

            // Drag (opposes velocity)
            let dragCoefficient: Float = 0.015
            var drag = SIMD3<Float>.zero
            if speed > 0.1 {
                drag = -simd_normalize(crashingPlanes[i].velocity) * speed * speed * dragCoefficient
            }

            // Apply gravity + lift + drag (no thrust - engines dead)
            let gravityForce = SIMD3<Float>(0, gravity, 0)
            crashingPlanes[i].velocity += (gravityForce + lift + drag) * deltaTime

            // Update position
            crashingPlanes[i].position += crashingPlanes[i].velocity * deltaTime

            // Nose down as it falls (pitch toward ground)
            crashingPlanes[i].pitch -= deltaTime * 0.8

            // Spiral out of control - roll increases
            crashingPlanes[i].roll += deltaTime * 2.0

            // Check for ground collision
            if crashingPlanes[i].position.y <= groundLevel {
                // Explode the plane
                explodePlaneAt(
                    position: crashingPlanes[i].position,
                    velocity: crashingPlanes[i].velocity,
                    yaw: crashingPlanes[i].yaw,
                    scale: crashingPlanes[i].scale,
                    planeIndex: crashingPlanes[i].planeIndex
                )
                crashingPlanes.remove(at: i)
            }
        }
    }

    /// Explode a plane at a specific position (for crashing planes)
    private func explodePlaneAt(position: SIMD3<Float>, velocity: SIMD3<Float>, yaw: Float, scale: SIMD3<Float>, planeIndex: Int) {
        let now = CACurrentMediaTime()

        // Create debris pieces
        var debris: [PlaneDebris] = []

        // Body debris
        let bodyPieces = 6
        for _ in 0..<bodyPieces {
            let randomDir = SIMD3<Float>(
                Float.random(in: -1...1),
                Float.random(in: 0.5...2.0),
                Float.random(in: -1...1)
            )
            let explosionVelocity = simd_normalize(randomDir) * Float.random(in: 15...35) + velocity * 0.3
            debris.append(PlaneDebris(
                position: position + randomDir * 0.5,
                velocity: explosionVelocity,
                rotationY: yaw + Float.random(in: -0.5...0.5),
                rotationVelocity: Float.random(in: -8...8),
                scale: scale * Float.random(in: 0.2...0.5),
                textureIndex: -1,
                shapeID: 0,
                life: 1.0
            ))
        }

        // Wing debris
        let wingPieces = 4
        for _ in 0..<wingPieces {
            let randomDir = SIMD3<Float>(
                Float.random(in: -2...2),
                Float.random(in: 0.3...1.5),
                Float.random(in: -1...1)
            )
            let explosionVelocity = simd_normalize(randomDir) * Float.random(in: 20...40) + velocity * 0.2
            debris.append(PlaneDebris(
                position: position + randomDir,
                velocity: explosionVelocity,
                rotationY: yaw + Float.random(in: -1...1),
                rotationVelocity: Float.random(in: -10...10),
                scale: SIMD3<Float>(Float.random(in: 0.3...0.8), 0.1, Float.random(in: 0.5...1.5)),
                textureIndex: -1,
                shapeID: 0,
                life: 1.0
            ))
        }

        planeExplosions.append(PlaneExplosion(debris: debris, startTime: now, planeIndex: planeIndex))
    }

    private func buildExplosionInstances() -> [VoxelInstance] {
        var instances: [VoxelInstance] = []

        for explosion in planeExplosions {
            for debris in explosion.debris {
                // Skip if faded out
                guard debris.life > 0.01 else { continue }

                // Scale down as life decreases
                let fadeScale = debris.scale * max(0.3, debris.life)

                instances.append(VoxelInstance(
                    position: debris.position,
                    _pad0: 0,
                    scale: fadeScale,
                    _pad1: 0,
                    rotationY: debris.rotationY,
                    rotationX: Float.random(in: -0.3...0.3),  // Tumble effect
                    rotationZ: Float.random(in: -0.3...0.3),
                    _pad2: 0,
                    materialID: 0,
                    highlight: 0,
                    hover: debris.life * 0.8,  // Glow effect during explosion
                    activity: 0,
                    activityKind: 0,
                    textureIndex: debris.textureIndex,
                    shapeID: debris.shapeID
                ))
            }
        }

        return instances
    }

    private func buildCrashingPlaneInstances() -> [VoxelInstance] {
        var instances: [VoxelInstance] = []
        let now = CACurrentMediaTime()

        for plane in crashingPlanes {
            let position = plane.position
            let pitch = plane.pitch
            let roll = plane.roll
            let yaw = plane.yaw
            let scale = plane.scale

            // Compute orientation vectors (same as piloted plane rendering)
            let cosY = cos(yaw)
            let sinY = sin(yaw)
            let cosP = cos(pitch)
            let sinP = sin(pitch)
            let cosR = cos(roll)
            let sinR = sin(roll)

            let forward = SIMD3<Float>(cosP * sinY, sinP, cosP * cosY)
            let flatRight = SIMD3<Float>(cosY, 0, -sinY)
            let pitchedUp = SIMD3<Float>(-sinP * sinY, cosP, -sinP * cosY)
            let rightVec = flatRight * cosR + pitchedUp * sinR
            let upVec = -flatRight * sinR + pitchedUp * cosR

            let flatDir = SIMD3<Float>(sin(yaw), 0, cos(yaw))
            let rotationY = atan2(flatDir.z, flatDir.x)
            let rotationX = roll
            let rotationZ = pitch

            // Flickering glow for distressed plane
            let glow: Float = 0.4 + 0.3 * sin(Float(now) * 15.0)

            let bodyOffset = forward * (scale.x * 0.1)

            // Main body
            instances.append(VoxelInstance(
                position: position - bodyOffset,
                _pad0: 0,
                scale: scale,
                _pad1: 0,
                rotationY: rotationY,
                rotationX: rotationX,
                rotationZ: rotationZ,
                _pad2: 0,
                materialID: 0,
                highlight: 0,
                hover: glow,
                textureIndex: -1,
                shapeID: 6
            ))

            // Wings
            instances.append(VoxelInstance(
                position: position,
                _pad0: 0,
                scale: SIMD3<Float>(1.6, 0.12, scale.z * 2.8),
                _pad1: 0,
                rotationY: rotationY,
                rotationX: rotationX,
                rotationZ: rotationZ,
                _pad2: 0,
                materialID: 0,
                highlight: 0,
                hover: glow,
                textureIndex: -1,
                shapeID: 0
            ))

            // Thrusters with flames (on fire as it crashes)
            let thrusterOffset = scale.z * 0.35
            let thrusterBack = scale.x * 0.05

            // Left thruster
            instances.append(VoxelInstance(
                position: position - forward * thrusterBack + rightVec * thrusterOffset - upVec * 0.12,
                _pad0: 0,
                scale: SIMD3<Float>(1.0, 0.35, 0.35),
                _pad1: 0,
                rotationY: rotationY,
                rotationX: rotationX,
                rotationZ: rotationZ,
                _pad2: 0,
                materialID: 0,
                highlight: 0,
                hover: glow,
                textureIndex: -1,
                shapeID: 5
            ))

            // Right thruster
            instances.append(VoxelInstance(
                position: position - forward * thrusterBack - rightVec * thrusterOffset - upVec * 0.12,
                _pad0: 0,
                scale: SIMD3<Float>(1.0, 0.35, 0.35),
                _pad1: 0,
                rotationY: rotationY,
                rotationX: rotationX,
                rotationZ: rotationZ,
                _pad2: 0,
                materialID: 0,
                highlight: 0,
                hover: glow,
                textureIndex: -1,
                shapeID: 5
            ))

            // No flames - engines cut out when pilot ejects
        }

        return instances
    }

    private func regeneratePlanePath(index: Int) {
        guard index >= 0, index < planePaths.count, !blocks.isEmpty else { return }

        let xs = sortedUnique(values: blocks.map { $0.position.x })
        let zs = sortedUnique(values: blocks.map { $0.position.z })
        guard xs.count > 1, zs.count > 1 else { return }

        let stepX = minSpacing(values: xs)
        let stepZ = minSpacing(values: zs)
        guard stepX > 0, stepZ > 0 else { return }

        let xRoadsSource = (0..<(xs.count - 1)).map { xs[$0] + stepX * 0.5 }
        let zRoadsSource = (0..<(zs.count - 1)).map { zs[$0] + stepZ * 0.5 }
        guard !xRoadsSource.isEmpty, !zRoadsSource.isEmpty else { return }

        let outerPadding: Float = 150.0
        let xRoads = [xRoadsSource[0] - outerPadding] + xRoadsSource + [xRoadsSource.last! + outerPadding]
        let zRoads = [zRoadsSource[0] - outerPadding] + zRoadsSource + [zRoadsSource.last! + outerPadding]

        let gridW = xRoads.count
        let gridH = zRoads.count
        guard gridW > 2, gridH > 2 else { return }

        let minX = xs.first ?? 0
        let maxX = xs.last ?? 0
        let minZ = zs.first ?? 0
        let maxZ = zs.last ?? 0
        let spanX = maxX - minX
        let spanZ = maxZ - minZ
        let minPathLength = max(spanX, spanZ) * 0.6

        let maxHeight = blocks.map { $0.position.y + Float($0.height) }.max() ?? 20
        let altitude = maxHeight + 18 + Float(index % 3) * 6.0

        // Use current time to generate a unique seed for a new path
        let timeSeed = UInt64(CACurrentMediaTime() * 1000000) & 0xFFFFFFFF
        let seed = timeSeed ^ UInt64(index * 7919)

        let startEdge = Int(seed % 4)
        let endEdge = (startEdge + 2 + Int((seed >> 8) % 2)) % 4

        var attempts = 0
        while attempts < 10 {
            let attemptSeed = seed &+ UInt64(attempts * 37)
            let start = randomPerimeterPoint(width: gridW, height: gridH, seed: attemptSeed, edge: startEdge)
            let end = randomPerimeterPoint(width: gridW, height: gridH, seed: attemptSeed ^ 0xBEEF, edge: endEdge)
            let mid = randomInteriorPoint(width: gridW, height: gridH, seed: attemptSeed ^ 0xCAFE)

            let first = findPath(start: start, goal: mid, width: gridW, height: gridH)
            let second = findPath(start: mid, goal: end, width: gridW, height: gridH)
            let pathCells = first + second.dropFirst()

            if pathCells.count >= 2 {
                let waypoints = pathCells.map { cell in
                    SIMD3<Float>(xRoads[cell.x], altitude, zRoads[cell.y])
                }
                let smoothed = smoothPath(waypoints: waypoints, iterations: 4)
                let segmentLengths = computeSegmentLengths(waypoints: smoothed)
                let totalLength = segmentLengths.reduce(0, +)

                if totalLength >= minPathLength {
                    let speed = 6.0 + randomUnit(seed: attemptSeed ^ 0xFACE) * 6.0
                    let phase = randomUnit(seed: attemptSeed ^ 0xDEAD) * totalLength
                    let scale = SIMD3<Float>(7.5, 0.6, 2.5)

                    planePaths[index] = PlanePath(
                        waypoints: smoothed,
                        segmentLengths: segmentLengths,
                        totalLength: totalLength,
                        speed: speed,
                        phase: phase,
                        scale: scale
                    )

                    // Reset offset for fresh start
                    if index < planeOffsets.count {
                        planeOffsets[index] = 0
                    }
                    return
                }
            }
            attempts += 1
        }
    }

    func pickPlane(at point: CGPoint, in size: CGSize) -> Int? {
        guard size.width > 1, size.height > 1, !planePaths.isEmpty else { return nil }
        let ray = rayFrom(point: point, in: size)
        let now = CACurrentMediaTime()
        var closest: (index: Int, distance: Float)?

        for (index, path) in planePaths.enumerated() {
            // Skip exploded planes
            guard !explodedPlaneIndices.contains(index) else { continue }

            let baseDistance = fmod(Float(now) * path.speed + path.phase, path.totalLength)
            let offset = index < planeOffsets.count ? planeOffsets[index] : 0
            let distance = fmod(baseDistance + offset, path.totalLength)
            let position = positionAlongPath(path: path, distance: distance)
            let radius = max(path.scale.x, path.scale.z) * 0.75
            if let hit = intersectSphere(ray: ray, center: position, radius: radius) {
                if closest == nil || hit < closest!.distance {
                    closest = (index, hit)
                }
            }
        }

        return closest?.index
    }

    func spawnHelicopter(at block: CityBlock) {
        var maxY = block.visualTopY
        // Find the highest block at this X/Z location to avoid collisions with stacked blocks
        for other in blocks {
            if abs(other.position.x - block.position.x) < 0.1 && abs(other.position.z - block.position.z) < 0.1 {
                let top = other.visualTopY
                if top > maxY {
                    maxY = top
                }
            }
        }
        let target = SIMD3<Float>(block.position.x, maxY, block.position.z)
        helicopterManager.spawn(
            at: target,
            targetID: block.nodeID,
            textureIndex: block.textureIndex,
            footprint: block.footprint,
            height: block.height
        )
    }

    func spawnBeam(at block: CityBlock) {
        // Find the top-most block at this location to ensure we spawn from the roof
        var topBlock = block
        var maxVisualTop = block.visualTopY

        // Scan for higher blocks in the same column
        for other in blocks {
            if abs(other.position.x - block.position.x) < 0.1 && abs(other.position.z - block.position.z) < 0.1 {
                let top = other.visualTopY
                if top > maxVisualTop {
                    maxVisualTop = top
                    topBlock = other
                }
            }
        }
        
        // Calculate position based on the top block's properties
        let footprintX = Float(topBlock.footprint.x)
        let footprintZ = Float(topBlock.footprint.y)
        let baseX = topBlock.position.x
        let baseZ = topBlock.position.z
        let rotationY = rotationYForWedge(block: topBlock, cameraYaw: camera.wedgeYaw)

        var beaconOffsetX: Float = 0
        var beaconOffsetZ: Float = 0

        if topBlock.shapeID == 3 {
            beaconOffsetX = footprintX * 0.45
        } else if topBlock.shapeID == 4 {
            beaconOffsetZ = footprintZ * 0.45
        }
        
        if topBlock.shapeID == 3 || topBlock.shapeID == 4 {
            let c = cos(rotationY)
            let s = sin(rotationY)
            let rotatedX = beaconOffsetX * c - beaconOffsetZ * s
            let rotatedZ = beaconOffsetX * s + beaconOffsetZ * c
            beaconOffsetX = rotatedX
            beaconOffsetZ = rotatedZ
        }
        
        // Target Y: The visual top of the highest block
        let beamY = maxVisualTop
        
        let target = SIMD3<Float>(baseX + beaconOffsetX, beamY, baseZ + beaconOffsetZ)
        
        // Use the original block's nodeID for activity flashing
        beamManager.spawn(at: target, targetID: block.nodeID)
    }

    func spawnElectricityBeam(from sessionID: UUID, to block: CityBlock) {
        // Get satellite position
        guard let (satellitePos, _) = satelliteManager.getSatelliteTarget(sessionID: sessionID) else { return }

        // Find the top-most block at this location for the building
        var topBlock = block
        var maxVisualTop = block.visualTopY

        for other in blocks {
            if abs(other.position.x - block.position.x) < 0.1 && abs(other.position.z - block.position.z) < 0.1 {
                let top = other.visualTopY
                if top > maxVisualTop {
                    maxVisualTop = top
                    topBlock = other
                }
            }
        }

        // Calculate building position at the top
        let footprintX = Float(topBlock.footprint.x)
        let footprintZ = Float(topBlock.footprint.y)
        let baseX = topBlock.position.x
        let baseZ = topBlock.position.z
        let rotationY = rotationYForWedge(block: topBlock, cameraYaw: camera.wedgeYaw)

        var beaconOffsetX: Float = 0
        var beaconOffsetZ: Float = 0

        if topBlock.shapeID == 3 {
            beaconOffsetX = footprintX * 0.45
        } else if topBlock.shapeID == 4 {
            beaconOffsetZ = footprintZ * 0.45
        }

        if topBlock.shapeID == 3 || topBlock.shapeID == 4 {
            let c = cos(rotationY)
            let s = sin(rotationY)
            let rotatedX = beaconOffsetX * c - beaconOffsetZ * s
            let rotatedZ = beaconOffsetX * s + beaconOffsetZ * c
            beaconOffsetX = rotatedX
            beaconOffsetZ = rotatedZ
        }

        let buildingPos = SIMD3<Float>(baseX + beaconOffsetX, maxVisualTop, baseZ + beaconOffsetZ)

        // Spawn electricity beam from satellite to building
        beamManager.spawnElectricity(from: satellitePos, to: buildingPos)
    }

    func clearHelicopters() {
        helicopterManager.clear()
        beamManager.clear()
        rebuildInstancesUsingCache()
    }

    // MARK: - Satellite Management

    func spawnSatellite(sessionID: UUID) {
        satelliteManager.spawn(sessionID: sessionID)
    }

    func updateSatelliteState(sessionID: UUID, state: ClaudeSession.SessionState) {
        satelliteManager.updateState(sessionID: sessionID, state: state)
    }

    func removeSatellite(sessionID: UUID) {
        satelliteManager.remove(sessionID: sessionID)
    }

    func updateSatelliteSelection(sessionID: UUID, selected: Bool) {
        satelliteManager.setSelected(sessionID: sessionID, selected: selected)
    }

    func updateSatelliteHover(sessionID: UUID, hovered: Bool) {
        satelliteManager.setHovered(sessionID: sessionID, hovered: hovered)
    }

    func clearSatellites() {
        satelliteManager.clear()
    }

    private var lastSatelliteDebugLog: CFTimeInterval = 0

    func pickSatellite(at point: CGPoint, in size: CGSize) -> UUID? {
        guard size.width > 1, size.height > 1 else { return nil }

        // Must match pickBlockHit coordinate system
        let ndcX = (2.0 * Float(point.x) / Float(size.width)) - 1.0
        let ndcY = (2.0 * Float(point.y) / Float(size.height)) - 1.0

        let viewMatrix = camera.viewMatrix()
        let projectionMatrix = camera.projectionMatrix()
        let viewProjection = projectionMatrix * viewMatrix
        let inverseViewProjection = simd_inverse(viewProjection)

        let nearPoint = SIMD4<Float>(ndcX, ndcY, -1.0, 1.0)
        let farPoint = SIMD4<Float>(ndcX, ndcY, 1.0, 1.0)
        let worldNear = inverseViewProjection * nearPoint
        let worldFar = inverseViewProjection * farPoint

        let nearWorld = SIMD3<Float>(worldNear.x / worldNear.w, worldNear.y / worldNear.w, worldNear.z / worldNear.w)
        let farWorld = SIMD3<Float>(worldFar.x / worldFar.w, worldFar.y / worldFar.w, worldFar.z / worldFar.w)
        let rayDir = simd_normalize(farWorld - nearWorld)

        let hitBoxes = satelliteManager.getSatelliteHitBoxes()

        // Debug logging (throttled to once per second)
        let now = CACurrentMediaTime()
        if now - lastSatelliteDebugLog > 1.0 && !hitBoxes.isEmpty {
            lastSatelliteDebugLog = now
            NSLog("[pickSatellite] Testing %d hit boxes", hitBoxes.count)
            NSLog("[pickSatellite] Ray origin: (%.1f, %.1f, %.1f), dir: (%.2f, %.2f, %.2f)",
                  nearWorld.x, nearWorld.y, nearWorld.z, rayDir.x, rayDir.y, rayDir.z)
            if let firstBox = hitBoxes.first {
                NSLog("[pickSatellite] First box center: (%.1f, %.1f, %.1f), halfExtents: (%.1f, %.1f, %.1f)",
                      firstBox.center.x, firstBox.center.y, firstBox.center.z,
                      firstBox.halfExtents.x, firstBox.halfExtents.y, firstBox.halfExtents.z)
            }
        }

        var closest: (sessionID: UUID, distance: Float)?

        for box in hitBoxes {
            if let dist = intersectOBB(origin: nearWorld, direction: rayDir, box: box) {
                if closest == nil || dist < closest!.distance {
                    closest = (box.sessionID, dist)
                }
            }
        }

        if let result = closest {
            NSLog("[MetalRenderer] pickSatellite HIT: sessionID=%@, distance=%.2f", result.sessionID.uuidString, result.distance)
        }

        return closest?.sessionID
    }

    /// Ray-OBB (Oriented Bounding Box) intersection using slab method
    /// Transforms ray into local space of the OBB, then does AABB test
    private func intersectOBB(origin: SIMD3<Float>, direction: SIMD3<Float>, box: SatelliteManager.SatelliteHitBox) -> Float? {
        // Rotate ray into box's local space (inverse rotation around Y)
        let cosY = cos(-box.rotationY)
        let sinY = sin(-box.rotationY)

        // Translate ray origin relative to box center
        let relOrigin = origin - box.center

        // Rotate origin and direction into local space
        let localOrigin = SIMD3<Float>(
            relOrigin.x * cosY - relOrigin.z * sinY,
            relOrigin.y,
            relOrigin.x * sinY + relOrigin.z * cosY
        )
        let localDir = SIMD3<Float>(
            direction.x * cosY - direction.z * sinY,
            direction.y,
            direction.x * sinY + direction.z * cosY
        )

        // Now do standard AABB intersection (slab method)
        let invDir = SIMD3<Float>(
            localDir.x != 0 ? 1.0 / localDir.x : .infinity,
            localDir.y != 0 ? 1.0 / localDir.y : .infinity,
            localDir.z != 0 ? 1.0 / localDir.z : .infinity
        )

        let t1 = (-box.halfExtents - localOrigin) * invDir
        let t2 = (box.halfExtents - localOrigin) * invDir

        let tMin = max(max(min(t1.x, t2.x), min(t1.y, t2.y)), min(t1.z, t2.z))
        let tMax = min(min(max(t1.x, t2.x), max(t1.y, t2.y)), max(t1.z, t2.z))

        // If tMax < 0, ray intersects but box is behind
        // If tMin > tMax, ray doesn't intersect
        if tMax < 0 || tMin > tMax {
            return nil
        }

        // Return the nearest positive intersection
        return tMin > 0 ? tMin : tMax > 0 ? tMax : nil
    }

    func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize) {
        camera.aspect = Float(size.width / max(size.height, 1))
    }

    func draw(in view: MTKView) {
        guard let drawable = view.currentDrawable,
              let renderPassDescriptor = view.currentRenderPassDescriptor,
              let commandBuffer = commandQueue.makeCommandBuffer(),
              let instanceBuffer else {
            return
        }
        let encoder = commandBuffer.makeRenderCommandEncoder(descriptor: renderPassDescriptor)

        // Render sky first
        let viewMatrix = camera.viewMatrix()
        let projectionMatrix = camera.projectionMatrix()
        let viewProjection = projectionMatrix * viewMatrix
        let inverseViewProjection = viewProjection.inverse

        encoder?.setRenderPipelineState(skyPipelineState)
        encoder?.setDepthStencilState(skyDepthState)
        encoder?.setVertexBuffer(skyVertexBuffer, offset: 0, index: 0)

        // Sun direction: slightly to the right and high in the sky
        let sunAngle = Float(CACurrentMediaTime()) * 0.02  // Very slow rotation
        var skyUniforms = SkyUniforms(
            inverseViewProjection: inverseViewProjection,
            time: Float(CACurrentMediaTime()),
            sunDirection: normalize(SIMD3<Float>(sin(sunAngle) * 0.5, 0.6, cos(sunAngle) * 0.8))
        )
        encoder?.setVertexBytes(&skyUniforms, length: MemoryLayout<SkyUniforms>.stride, index: 1)
        encoder?.setFragmentBytes(&skyUniforms, length: MemoryLayout<SkyUniforms>.stride, index: 0)
        encoder?.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 6)

        // Render ground plane
        let cameraPos = camera.eyePosition()
        encoder?.setRenderPipelineState(groundPipelineState)
        encoder?.setDepthStencilState(depthState)  // Use regular depth state for ground
        encoder?.setVertexBuffer(skyVertexBuffer, offset: 0, index: 0)  // Reuse same quad

        var groundUniforms = GroundUniforms(
            viewProjection: viewProjection,
            cameraPosition: cameraPos,
            groundSize: 2000.0,  // Large ground plane
            time: Float(CACurrentMediaTime()),
            fogDensity: fogDensity,
            cityBoundsMin: cityBoundsMin,
            cityBoundsMax: cityBoundsMax,
            cityCenter: cityCenter
        )
        encoder?.setVertexBytes(&groundUniforms, length: MemoryLayout<GroundUniforms>.stride, index: 1)
        encoder?.setFragmentBytes(&groundUniforms, length: MemoryLayout<GroundUniforms>.stride, index: 0)
        encoder?.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 6)

        // Switch to main scene rendering
        encoder?.setRenderPipelineState(pipelineState)
        encoder?.setDepthStencilState(depthState)
        encoder?.setVertexBuffer(cubeVertexBuffer, offset: 0, index: 0)

        var uniforms = Uniforms(viewProjection: viewProjection,
                                time: Float(CACurrentMediaTime()),
                                fogDensity: fogDensity,
                                cameraPosition: cameraPos)
        encoder?.setVertexBytes(&uniforms, length: MemoryLayout<Uniforms>.stride, index: 2)
        encoder?.setFragmentBytes(&uniforms, length: MemoryLayout<Uniforms>.stride, index: 2)
        
        if let textureArray = textureArray {
            encoder?.setFragmentTexture(textureArray, index: 0)
        }
        encoder?.setFragmentSamplerState(samplerState, index: 0)

        if let roadInstanceBuffer, roadInstanceCount > 0 {
            encoder?.setVertexBuffer(roadInstanceBuffer, offset: 0, index: 1)
            encoder?.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 36, instanceCount: roadInstanceCount)
        }

        encoder?.setVertexBuffer(instanceBuffer, offset: 0, index: 1)
        // Bind LOC flag texture array for Shape 19
        if let locFlagTextureArray = locFlagTextureArray {
            encoder?.setFragmentTexture(locFlagTextureArray, index: 2)
        }
        if instanceCount > 0 {
            encoder?.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 36, instanceCount: instanceCount)
        }

        updateCarInstances()
        if let carInstanceBuffer, carInstanceCount > 0 {
            encoder?.setVertexBuffer(carInstanceBuffer, offset: 0, index: 1)
            encoder?.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 36, instanceCount: carInstanceCount)
        }

        updatePlaneInstances()
        if let planeInstanceBuffer, planeInstanceCount > 0 {
            // Bind signLabelTextureArray for banner (Shape 13)
            if let signLabelTextureArray = signLabelTextureArray {
                encoder?.setFragmentTexture(signLabelTextureArray, index: 1)
            }
            encoder?.setVertexBuffer(planeInstanceBuffer, offset: 0, index: 1)
            encoder?.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 36, instanceCount: planeInstanceCount)
        }

        // Update and render crashing planes and explosions
        let deltaTime = Float(CACurrentMediaTime() - lastPlaneUpdateTime)
        let clampedDeltaTime = max(0.001, min(deltaTime, 0.1))
        updateCrashingPlanes(deltaTime: clampedDeltaTime)
        updateExplosions(deltaTime: clampedDeltaTime)

        // Render crashing planes
        let crashingInstances = buildCrashingPlaneInstances()
        if !crashingInstances.isEmpty {
            let crashBuffer = device.makeBuffer(bytes: crashingInstances, length: MemoryLayout<VoxelInstance>.stride * crashingInstances.count, options: [])
            if let buffer = crashBuffer {
                encoder?.setVertexBuffer(buffer, offset: 0, index: 1)
                encoder?.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 36, instanceCount: crashingInstances.count)
            }
        }

        // Render explosion debris
        let explosionInstances = buildExplosionInstances()
        explosionDebrisCount = explosionInstances.count
        if explosionDebrisCount > 0 {
            explosionDebrisBuffer = device.makeBuffer(bytes: explosionInstances, length: MemoryLayout<VoxelInstance>.stride * explosionDebrisCount, options: [])
            if let buffer = explosionDebrisBuffer {
                encoder?.setVertexBuffer(buffer, offset: 0, index: 1)
                encoder?.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 36, instanceCount: explosionDebrisCount)
            }
        }

        helicopterManager.update()
        
        beamManager.update()
        let beamTargets = beamManager.getActiveBeamTargetIDs()
        let heliTargets = helicopterManager.getActiveConstructionTargetIDs()
        let currentTargets = heliTargets.union(beamTargets)
        
        if currentTargets != lastTargetedNodeIDs {
            rebuildInstancesUsingCache()
        }
        
        let heliInstances = helicopterManager.buildInstances()
        helicopterInstanceCount = heliInstances.count
        if helicopterInstanceCount > 0 {
            helicopterInstanceBuffer = device.makeBuffer(bytes: heliInstances, length: MemoryLayout<VoxelInstance>.stride * helicopterInstanceCount, options: [])
            if let buffer = helicopterInstanceBuffer {
                encoder?.setVertexBuffer(buffer, offset: 0, index: 1)
                encoder?.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 36, instanceCount: helicopterInstanceCount)
            }
        }
        
        beamManager.update()
        let beamInstances = beamManager.buildInstances()
        beamInstanceCount = beamInstances.count
        if beamInstanceCount > 0 {
            beamInstanceBuffer = device.makeBuffer(bytes: beamInstances, length: MemoryLayout<VoxelInstance>.stride * beamInstanceCount, options: [])
            if let buffer = beamInstanceBuffer {
                encoder?.setVertexBuffer(buffer, offset: 0, index: 1)
                encoder?.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 36, instanceCount: beamInstanceCount)
            }
        }

        // Render satellites
        satelliteManager.update()
        let satelliteInstances = satelliteManager.buildInstances()
        satelliteInstanceCount = satelliteInstances.count
        if satelliteInstanceCount > 0 {
            satelliteInstanceBuffer = device.makeBuffer(bytes: satelliteInstances, length: MemoryLayout<VoxelInstance>.stride * satelliteInstanceCount, options: [])
            if let buffer = satelliteInstanceBuffer {
                encoder?.setVertexBuffer(buffer, offset: 0, index: 1)
                encoder?.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 36, instanceCount: satelliteInstanceCount)
            }
        }

        if let signpostInstanceBuffer, signpostInstanceCount > 0 {
            if let signLabelTextureArray = signLabelTextureArray {
                encoder?.setFragmentTexture(signLabelTextureArray, index: 1)
            }
            encoder?.setVertexBuffer(signpostInstanceBuffer, offset: 0, index: 1)
            encoder?.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 36, instanceCount: signpostInstanceCount)
        }

        encoder?.endEncoding()
        commandBuffer.present(drawable)
        commandBuffer.commit()
    }

    private func rebuildRoadsAndCars(blocks: [CityBlock]) {
        roadInstanceBuffer = nil
        roadInstanceCount = 0
        carInstanceBuffer = nil
        carInstanceCount = 0
        carPaths.removeAll()
        planeInstanceBuffer = nil
        planeInstanceCount = 0
        planePaths.removeAll()
        planeOffsets.removeAll()

        // Clear explosion and crashing plane state when paths are rebuilt
        planeExplosions.removeAll()
        explodedPlaneIndices.removeAll()
        crashingPlanes.removeAll()

        buildSignpostInstances(blocks: blocks)

        guard blocks.count > 3 else { return }

        let xs = sortedUnique(values: blocks.map { $0.position.x })
        let zs = sortedUnique(values: blocks.map { $0.position.z })
        guard xs.count > 1, zs.count > 1 else { return }

        let stepX = minSpacing(values: xs)
        let stepZ = minSpacing(values: zs)
        guard stepX > 0, stepZ > 0 else { return }

        let maxFootX = Int(blocks.map { Int($0.footprint.x) }.max() ?? 0)
        let maxFootZ = Int(blocks.map { Int($0.footprint.y) }.max() ?? 0)
        let roadWidth = max(2, Int(min(stepX, stepZ)) - max(maxFootX, maxFootZ))
        let spanX = (xs.last ?? 0) - (xs.first ?? 0) + Float(maxFootX)
        let spanZ = (zs.last ?? 0) - (zs.first ?? 0) + Float(maxFootZ)
        let centerX = ((xs.first ?? 0) + (xs.last ?? 0)) * 0.5
        let centerZ = ((zs.first ?? 0) + (zs.last ?? 0)) * 0.5

        var roadInstances: [VoxelInstance] = []

        // Horizontal roads (running along X axis) - need rotated UV (materialID 1)
        for zIndex in 0..<(zs.count - 1) {
            let roadZ = zs[zIndex] + stepZ * 0.5
            let instance = VoxelInstance(
                position: SIMD3<Float>(centerX, -0.6, roadZ),
                scale: SIMD3<Float>(spanX, 1.0, Float(roadWidth)),
                rotationY: 0,
                rotationX: 0,
                rotationZ: 0,
                materialID: 1,  // Rotated UV for horizontal roads
                textureIndex: roadTextureIndex,
                shapeID: 0
            )
            roadInstances.append(instance)
        }

        // Vertical roads (running along Z axis) - normal UV (materialID 0)
        // Slightly higher than horizontal roads to prevent Z-fighting at intersections
        for xIndex in 0..<(xs.count - 1) {
            let roadX = xs[xIndex] + stepX * 0.5
            let instance = VoxelInstance(
                position: SIMD3<Float>(roadX, -0.59, centerZ),
                scale: SIMD3<Float>(Float(roadWidth), 1.0, spanZ),
                rotationY: 0,
                rotationX: 0,
                rotationZ: 0,
                materialID: 0,  // Normal UV for vertical roads
                textureIndex: roadTextureIndex,
                shapeID: 0
            )
            roadInstances.append(instance)
        }

        roadInstanceCount = roadInstances.count
        if roadInstanceCount > 0 {
            roadInstanceBuffer = device.makeBuffer(bytes: roadInstances, length: MemoryLayout<VoxelInstance>.stride * roadInstanceCount, options: [])
        }

        buildCarPaths(xs: xs, zs: zs, stepX: stepX, stepZ: stepZ, spanX: spanX, spanZ: spanZ, roadWidth: roadWidth)
        let maxY = maxHeight(blocks: blocks)
        buildPlanePaths(minX: xs.first ?? 0, maxX: xs.last ?? 0, minZ: zs.first ?? 0, maxZ: zs.last ?? 0, maxHeight: maxY)
    }

    private func maxHeight(blocks: [CityBlock]) -> Float {
        let top = blocks.map { $0.position.y + Float($0.height) }.max() ?? 0
        return max(20, top)
    }

    private func buildCarPaths(xs: [Float], zs: [Float], stepX: Float, stepZ: Float, spanX: Float, spanZ: Float, roadWidth: Int) {
        let minX = xs.first ?? 0
        let maxX = xs.last ?? 0
        let minZ = zs.first ?? 0
        let maxZ = zs.last ?? 0
        let laneOffset = Float(roadWidth) * 0.25

        // Tesla Model 3 proportions: ~4.7m long, ~1.85m wide, ~1.44m tall
        // Scaled down for the city: length 3.5, width 1.5, height 1.1
        let carScale = SIMD3<Float>(1.5, 1.1, 3.5)

        for (index, z) in zs.dropLast().enumerated() {
            let roadZ = z + stepZ * 0.5
            let distance = max(1.0, spanX)
            let carCount = max(1, Int(distance / 40.0))
            for carIndex in 0..<carCount {
                let seed = UInt64(index * 73 + carIndex * 17)
                let speed = (2.0 + randomUnit(seed: seed) * 3.0) / distance
                let phase = randomUnit(seed: seed ^ 0xCAFE)
                let forward = (index % 2 == 0)

                // Random color from 12-color palette
                let colorIndex = UInt32(seed % 12)

                // RHT Logic for X-Roads
                // +X (Forward): Right is South (+Z). Offset +
                // -X (Backward): Right is North (-Z). Offset -
                let offsetZ = forward ? laneOffset : -laneOffset

                let start = SIMD3<Float>(forward ? minX - 2.0 : maxX + 2.0, 0.5, roadZ + offsetZ)
                let end = SIMD3<Float>(forward ? maxX + 2.0 : minX - 2.0, 0.5, roadZ + offsetZ)
                carPaths.append(CarPath(start: start, end: end, speed: speed, phase: phase, scale: carScale, colorIndex: colorIndex))
            }
        }

        for (index, x) in xs.dropLast().enumerated() {
            let roadX = x + stepX * 0.5
            let distance = max(1.0, spanZ)
            let carCount = max(1, Int(distance / 40.0))
            for carIndex in 0..<carCount {
                let seed = UInt64(index * 91 + carIndex * 29)
                let speed = (2.0 + randomUnit(seed: seed) * 3.0) / distance
                let phase = randomUnit(seed: seed ^ 0xBEEF)
                let forward = (index % 2 == 0)

                // Random color from 12-color palette
                let colorIndex = UInt32(seed % 12)

                // RHT Logic for Z-Roads
                // +Z (Forward): Right is West (-X). Offset -
                // -Z (Backward): Right is East (+X). Offset +
                let offsetX = forward ? -laneOffset : laneOffset

                let start = SIMD3<Float>(roadX + offsetX, 0.5, forward ? minZ - 2.0 : maxZ + 2.0)
                let end = SIMD3<Float>(roadX + offsetX, 0.5, forward ? maxZ + 2.0 : minZ - 2.0)
                carPaths.append(CarPath(start: start, end: end, speed: speed, phase: phase, scale: carScale, colorIndex: colorIndex))
            }
        }

        // Each car has multiple instances: body, glass, 4 wheels
        carInstanceCount = carPaths.count * instancesPerCar
        if carInstanceCount > 0 {
            carInstanceBuffer = device.makeBuffer(length: MemoryLayout<VoxelInstance>.stride * carInstanceCount, options: [])
        }
    }

    private func buildPlanePaths(minX: Float, maxX: Float, minZ: Float, maxZ: Float, maxHeight: Float) {
        let spanX = maxX - minX
        let spanZ = maxZ - minZ
        let count = max(2, Int((spanX + spanZ) / 120.0))

        let xs = sortedUnique(values: blocks.map { $0.position.x })
        let zs = sortedUnique(values: blocks.map { $0.position.z })
        guard xs.count > 1, zs.count > 1 else { return }

        let stepX = minSpacing(values: xs)
        let stepZ = minSpacing(values: zs)
        guard stepX > 0, stepZ > 0 else { return }

        let xRoadsSource = (0..<(xs.count - 1)).map { xs[$0] + stepX * 0.5 }
        let zRoadsSource = (0..<(zs.count - 1)).map { zs[$0] + stepZ * 0.5 }
        guard !xRoadsSource.isEmpty, !zRoadsSource.isEmpty else { return }

        // Expand the perimeter for planes to fly in from further away
        let outerPadding: Float = 150.0
        let xRoads = [xRoadsSource[0] - outerPadding] + xRoadsSource + [xRoadsSource.last! + outerPadding]
        let zRoads = [zRoadsSource[0] - outerPadding] + zRoadsSource + [zRoadsSource.last! + outerPadding]

        let gridW = xRoads.count
        let gridH = zRoads.count
        guard gridW > 2, gridH > 2 else { return }
        guard gridW > 2, gridH > 2 else { return }
        let minPathLength = max(spanX, spanZ) * 0.6
        for index in 0..<count {
            let seed = UInt64(index * 113)
            let altitude = maxHeight + 18 + Float(index % 3) * 6.0
            let startEdge = Int(seed % 4)
            let endEdge = (startEdge + 2 + Int(seed % 2)) % 4
            var attempts = 0
            var pathCells: [(x: Int, y: Int)] = []

            while attempts < 6 {
                let start = randomPerimeterPoint(width: gridW, height: gridH, seed: seed &+ UInt64(attempts * 31), edge: startEdge)
                let end = randomPerimeterPoint(width: gridW, height: gridH, seed: seed ^ 0xBEEF &+ UInt64(attempts * 17), edge: endEdge)
                let mid = randomInteriorPoint(width: gridW, height: gridH, seed: seed ^ 0xCAFE &+ UInt64(attempts * 29))
                let first = findPath(start: start, goal: mid, width: gridW, height: gridH)
                let second = findPath(start: mid, goal: end, width: gridW, height: gridH)
                pathCells = first + second.dropFirst()
                if pathCells.count < 2 {
                    attempts += 1
                    continue
                }
            let waypoints = pathCells.map { cell in
                SIMD3<Float>(xRoads[cell.x], altitude, zRoads[cell.y])
            }
            let smoothed = smoothPath(waypoints: waypoints, iterations: 4)
            let segmentLengths = computeSegmentLengths(waypoints: smoothed)
            let totalLength = segmentLengths.reduce(0, +)
            if totalLength >= minPathLength {
                let speed = 6.0 + randomUnit(seed: seed ^ 0xFACE) * 6.0
                let phase = randomUnit(seed: seed ^ 0xCAFE) * totalLength
                let scale = SIMD3<Float>(7.5, 0.6, 2.5)
                planePaths.append(PlanePath(waypoints: smoothed, segmentLengths: segmentLengths, totalLength: totalLength, speed: speed, phase: phase, scale: scale))
                break
            }
            attempts += 1
        }
        }

        planeInstanceCount = planePaths.count * 16
        if planeInstanceCount > 0 {
            planeInstanceBuffer = device.makeBuffer(length: MemoryLayout<VoxelInstance>.stride * planeInstanceCount, options: [])
        }
        planeOffsets = Array(repeating: 0, count: planePaths.count)
        lastPlaneUpdateTime = CACurrentMediaTime()
    }

    private func buildSignpostInstances(blocks: [CityBlock]) {
        signpostInstanceBuffer = nil
        signpostInstanceCount = 0
        signLabelTextureArray = nil
        signLabelIndexByNodeID.removeAll()

        guard !blocks.isEmpty else { return }

        // Deduplicate: only one sign per nodeID, use ground-level block
        var groundBlocks: [UUID: CityBlock] = [:]
        for block in blocks {
            guard !block.name.isEmpty else { continue }
            if block.position.y < 1.0 {
                if groundBlocks[block.nodeID] == nil {
                    groundBlocks[block.nodeID] = block
                }
            }
        }

        guard !groundBlocks.isEmpty else { return }

        // Build pre-baked label textures
        var labelTextures: [MTLTexture] = []
        var index = 0
        for (nodeID, block) in groundBlocks {
            if let tex = TextureGenerator.generateSignLabel(device: device, text: block.name) {
                labelTextures.append(tex)
                signLabelIndexByNodeID[nodeID] = index
                index += 1
            }
        }

        guard !labelTextures.isEmpty, let first = labelTextures.first,
              first.width > 0, first.height > 0 else { return }

        // Metal texture arrays have a max arrayLength of 2048
        // Reserve 1 slot for banner, so limit labels to 2047
        let maxLabels = 2047
        if labelTextures.count > maxLabels {
            labelTextures = Array(labelTextures.prefix(maxLabels))
            // Also trim the mapping dictionary to match
            let validNodeIDs = Set(signLabelIndexByNodeID.filter { $0.value < maxLabels }.keys)
            signLabelIndexByNodeID = signLabelIndexByNodeID.filter { validNodeIDs.contains($0.key) }
        }

        // Generate Banner Texture (must match sign label dimensions for texture array)
        if !bannerText.isEmpty {
            if let bannerTex = TextureGenerator.generateBanner(device: device, text: bannerText),
               bannerTex.width == first.width, bannerTex.height == first.height {
                bannerTextureIndex = labelTextures.count
                labelTextures.append(bannerTex)
            } else {
                bannerTextureIndex = -1
            }
        } else {
            bannerTextureIndex = -1
        }

        // Create texture array for sign labels
        // Validate all textures have matching dimensions before creating array
        let expectedWidth = first.width
        let expectedHeight = first.height
        for (i, tex) in labelTextures.enumerated() {
            if tex.width != expectedWidth || tex.height != expectedHeight {
                NSLog("[MetalRenderer] Texture \(i) has mismatched dimensions: \(tex.width)x\(tex.height) vs expected \(expectedWidth)x\(expectedHeight)")
                return
            }
        }

        guard labelTextures.count > 0, expectedWidth > 0, expectedHeight > 0 else { return }

        let descriptor = MTLTextureDescriptor()
        descriptor.textureType = .type2DArray
        descriptor.pixelFormat = first.pixelFormat
        descriptor.width = expectedWidth
        descriptor.height = expectedHeight
        descriptor.arrayLength = labelTextures.count
        descriptor.usage = .shaderRead

        guard let arrayTex = device.makeTexture(descriptor: descriptor),
              let commandBuffer = commandQueue.makeCommandBuffer(),
              let blitEncoder = commandBuffer.makeBlitCommandEncoder() else { return }

        for (i, tex) in labelTextures.enumerated() {
            blitEncoder.copy(from: tex, sourceSlice: 0, sourceLevel: 0,
                             sourceOrigin: MTLOrigin(x: 0, y: 0, z: 0),
                             sourceSize: MTLSize(width: tex.width, height: tex.height, depth: 1),
                             to: arrayTex, destinationSlice: i, destinationLevel: 0,
                             destinationOrigin: MTLOrigin(x: 0, y: 0, z: 0))
        }
        blitEncoder.endEncoding()
        commandBuffer.commit()
        commandBuffer.waitUntilCompleted()
        signLabelTextureArray = arrayTex

        // Build signpost instances (just pole + signboard with pre-baked texture)
        var instances: [VoxelInstance] = []
        instances.reserveCapacity(groundBlocks.count * 2)

        let postHeight: Float = 3.0
        let postWidth: Float = 0.4
        let signboardHeight: Float = 1.5
        let signboardWidth: Float = 6.0

        for block in groundBlocks.values {
            guard let texIndex = signLabelIndexByNodeID[block.nodeID] else { continue }

            let halfFootprintX = Float(block.footprint.x) * 0.5
            let signX = block.position.x + halfFootprintX + 1.5
            let signZ = block.position.z
            let baseY: Float = 0.0

            // Signpost pole
            instances.append(VoxelInstance(
                position: SIMD3<Float>(signX, baseY + postHeight * 0.5, signZ),
                scale: SIMD3<Float>(postWidth, postHeight, postWidth),
                rotationY: 0,
                rotationX: 0,
                rotationZ: 0,
                materialID: 10,
                textureIndex: -1,
                shapeID: 0
            ))

            // Signboard with pre-baked texture (shapeID 11 for sign label)
            let boardY = baseY + postHeight + signboardHeight * 0.5
            instances.append(VoxelInstance(
                position: SIMD3<Float>(signX + 0.1, boardY, signZ),
                scale: SIMD3<Float>(0.1, signboardHeight, signboardWidth),
                rotationY: 0,
                rotationX: 0,
                rotationZ: 0,
                materialID: 0,
                textureIndex: Int32(texIndex),
                shapeID: 11
            ))
        }

        signpostInstanceCount = instances.count
        if signpostInstanceCount > 0 {
            signpostInstanceBuffer = device.makeBuffer(bytes: instances, length: MemoryLayout<VoxelInstance>.stride * signpostInstanceCount, options: [])
        }
    }

    private func updateCarInstances() {
        guard let carInstanceBuffer, !carPaths.isEmpty else { return }
        let now = CACurrentMediaTime()
        let pointer = carInstanceBuffer.contents().bindMemory(to: VoxelInstance.self, capacity: carInstanceCount)

        for (carIndex, path) in carPaths.enumerated() {
            let baseIndex = carIndex * instancesPerCar
            let t = fmod(Float(now) * path.speed + path.phase, 1.0)
            let position = path.start + (path.end - path.start) * t
            let direction = normalize(path.end - path.start)
            let rotationY = atan2(direction.x, direction.z)

            // Car body dimensions
            let bodyScale = path.scale
            let bodyY: Float = 0.35  // Lift body slightly off ground

            // Instance 0: Car body (shapeID 14)
            pointer[baseIndex] = VoxelInstance(
                position: SIMD3<Float>(position.x, position.y + bodyY, position.z),
                scale: bodyScale,
                rotationY: rotationY,
                rotationX: 0,
                rotationZ: 0,
                materialID: path.colorIndex,
                textureIndex: -1,  // No texture, use shader color
                shapeID: 14
            )

            // Instance 1: Glass canopy (shapeID 15)
            // Glass sits on top rear-center of body
            let glassScale = SIMD3<Float>(bodyScale.x * 0.88, bodyScale.y * 0.45, bodyScale.z * 0.48)
            let glassOffsetY = bodyY + bodyScale.y * 0.45
            let glassOffsetZ: Float = -bodyScale.z * 0.08  // Slightly toward rear
            // Rotate offset by car direction
            let cosR = cos(rotationY)
            let sinR = sin(rotationY)
            let glassWorldOffsetX = glassOffsetZ * sinR
            let glassWorldOffsetZ = glassOffsetZ * cosR
            pointer[baseIndex + 1] = VoxelInstance(
                position: SIMD3<Float>(position.x + glassWorldOffsetX, position.y + glassOffsetY, position.z + glassWorldOffsetZ),
                scale: glassScale,
                rotationY: rotationY,
                rotationX: 0,
                rotationZ: 0,
                materialID: 0,
                textureIndex: -1,
                shapeID: 15
            )

            // Wheels (shapeID 16)
            let wheelRadius: Float = 0.32
            let wheelWidth: Float = 0.22
            let wheelScale = SIMD3<Float>(wheelWidth, wheelRadius * 2, wheelRadius * 2)
            let wheelY = wheelRadius * 0.9  // Slightly embedded in ground
            let wheelXOffset = bodyScale.x * 0.42  // Side offset
            let wheelZFront = bodyScale.z * 0.32   // Front wheels
            let wheelZRear = -bodyScale.z * 0.35   // Rear wheels

            // Wheel positions in local space (relative to car center)
            let wheelPositions: [(Float, Float)] = [
                (-wheelXOffset, wheelZFront),   // Front left
                (wheelXOffset, wheelZFront),    // Front right
                (-wheelXOffset, wheelZRear),    // Rear left
                (wheelXOffset, wheelZRear),     // Rear right
            ]

            for (wheelIndex, (localX, localZ)) in wheelPositions.enumerated() {
                // Rotate local position by car direction
                let worldX = localX * cosR + localZ * sinR
                let worldZ = -localX * sinR + localZ * cosR
                pointer[baseIndex + 2 + wheelIndex] = VoxelInstance(
                    position: SIMD3<Float>(position.x + worldX, wheelY, position.z + worldZ),
                    scale: wheelScale,
                    rotationY: rotationY,
                    rotationX: 0,
                    rotationZ: 0,
                    materialID: 0,
                    textureIndex: -1,
                    shapeID: 16
                )
            }

            // Instance 6: Headlights (shapeID 17)
            // Positioned at front of car, spans width
            let headlightScale = SIMD3<Float>(bodyScale.x * 0.85, 0.12, 0.15)
            let headlightLocalZ = bodyScale.z * 0.48  // At front
            let headlightLocalY = bodyY + 0.15  // Low on the nose
            let headlightWorldX = headlightLocalZ * sinR
            let headlightWorldZ = headlightLocalZ * cosR
            pointer[baseIndex + 6] = VoxelInstance(
                position: SIMD3<Float>(position.x + headlightWorldX, headlightLocalY, position.z + headlightWorldZ),
                scale: headlightScale,
                rotationY: rotationY,
                rotationX: 0,
                rotationZ: 0,
                materialID: 0,
                textureIndex: -1,
                shapeID: 17
            )

            // Instance 7: Taillights (shapeID 18)
            // Tesla's distinctive full-width taillight bar
            let taillightScale = SIMD3<Float>(bodyScale.x * 0.92, 0.08, 0.1)
            let taillightLocalZ = -bodyScale.z * 0.48  // At rear
            let taillightLocalY = bodyY + bodyScale.y * 0.25  // Mid-height on trunk
            let taillightWorldX = taillightLocalZ * sinR
            let taillightWorldZ = taillightLocalZ * cosR
            pointer[baseIndex + 7] = VoxelInstance(
                position: SIMD3<Float>(position.x + taillightWorldX, taillightLocalY, position.z + taillightWorldZ),
                scale: taillightScale,
                rotationY: rotationY,
                rotationX: 0,
                rotationZ: 0,
                materialID: 0,
                textureIndex: -1,
                shapeID: 18
            )
        }
    }

    private func updatePlaneInstances() {
        guard let planeInstanceBuffer, !planePaths.isEmpty else { return }
        let now = CACurrentMediaTime()
        let deltaTime = max(0, now - lastPlaneUpdateTime)
        lastPlaneUpdateTime = now
        let pointer = planeInstanceBuffer.contents().bindMemory(to: VoxelInstance.self, capacity: planeInstanceCount)
        for (index, path) in planePaths.enumerated() {
            let baseIndex = index * 16

            // Skip exploded planes - zero out their instances
            if explodedPlaneIndices.contains(index) {
                for i in 0..<16 {
                    pointer[baseIndex + i] = VoxelInstance(position: .zero, scale: .zero, rotationY: 0, rotationX: 0, rotationZ: 0, materialID: 0, textureIndex: -1, shapeID: 0)
                }
                continue
            }

            // Check if this plane is being piloted
            let isPiloted = index == pilotedPlaneIndex
            let flightState = isPiloted ? pilotedPlaneFlightState : nil

            let position: SIMD3<Float>
            let rotationY: Float
            let rotationX: Float  // pitch
            let rotationZ: Float  // roll
            let direction: SIMD3<Float>
            let right: SIMD3<Float>
            let up: SIMD3<Float>  // Local up vector for part positioning
            let glow: Float
            let showFlames: Bool

            if let state = flightState {
                // Use piloted flight state
                position = state.position

                // Compute full 3D orientation matching physics convention
                let yaw = state.yaw
                let pitch = state.pitch
                let roll = state.roll

                let cosY = cos(yaw)
                let sinY = sin(yaw)
                let cosP = cos(pitch)
                let sinP = sin(pitch)
                let cosR = cos(roll)
                let sinR = sin(roll)

                // Forward vector (matches physics forwardVector)
                let forward = SIMD3<Float>(
                    cosP * sinY,
                    sinP,
                    cosP * cosY
                )

                // Right vector (horizontal, yaw only)
                let flatRight = SIMD3<Float>(cosY, 0, -sinY)

                // Up vector before roll (perpendicular to forward and right)
                let pitchedUp = SIMD3<Float>(
                    -sinP * sinY,
                    cosP,
                    -sinP * cosY
                )

                // Apply roll around forward axis
                let rightVec = flatRight * cosR + pitchedUp * sinR
                let upVec = -flatRight * sinR + pitchedUp * cosR

                // Use transformed vectors for part positioning
                direction = forward
                right = rightVec
                up = upVec

                // Derive rotationY to match rendering convention (use flat yaw direction)
                let flatDir = SIMD3<Float>(sin(yaw), 0, cos(yaw))
                rotationY = atan2(flatDir.z, flatDir.x)
                rotationX = roll     // Visual roll - bank left/right
                rotationZ = pitch    // Visual pitch - nose up/down
                let isDoingManeuver = state.activeManeuver != .none
                glow = (state.isBoosting || isDoingManeuver) ? (0.8 + 0.2 * sin(Float(now) * 25.0)) : 0.0
                showFlames = state.isBoosting || isDoingManeuver
            } else {
                // Normal path-following plane
                let isHovered = hoveredPlaneIndex == index
                let speedBoost: Float = isHovered ? 1.6 : 1.0
                if index < planeOffsets.count, speedBoost > 1.0 {
                    planeOffsets[index] = fmod(planeOffsets[index] + Float(deltaTime) * path.speed * (speedBoost - 1.0), path.totalLength)
                }
                let baseDistance = fmod(Float(now) * path.speed + path.phase, path.totalLength)
                let offset = index < planeOffsets.count ? planeOffsets[index] : 0
                let distance = fmod(baseDistance + offset, path.totalLength)
                position = positionAlongPath(path: path, distance: distance)
                let nextDistance = fmod(distance + 1.0, path.totalLength)
                let nextPosition = positionAlongPath(path: path, distance: nextDistance)
                direction = simd_normalize(nextPosition - position)
                right = simd_normalize(SIMD3<Float>(-direction.z, 0, direction.x))
                up = SIMD3<Float>(0, 1, 0)  // World up for non-piloted planes
                rotationY = atan2(direction.z, direction.x)
                rotationX = 0
                rotationZ = 0
                glow = isHovered ? (0.6 + 0.4 * sin(Float(now) * 18.0)) : 0.0
                showFlames = isHovered
            }
            let bodyOffset = direction * (path.scale.x * 0.1)  // Shift body back so longer tail extends rearward
            pointer[baseIndex] = VoxelInstance(
                position: position - bodyOffset,
                _pad0: 0,
                scale: path.scale,
                _pad1: 0,
                rotationY: rotationY,
                rotationX: rotationX,
                rotationZ: rotationZ,
                _pad2: 0,
                materialID: 0,
                highlight: 0,
                hover: glow,
                textureIndex: planeTextureIndex,
                shapeID: 6
            )
            pointer[baseIndex + 1] = VoxelInstance(
                position: position + up * 0.1,
                _pad0: 0,
                scale: SIMD3<Float>(1.4, 0.08, 6.3),
                _pad1: 0,
                rotationY: rotationY,
                rotationX: rotationX,
                rotationZ: rotationZ,
                _pad2: 0,
                materialID: 0,
                highlight: 0,
                hover: glow * 0.6,
                textureIndex: planeTextureIndex,
                shapeID: 0
            )
            let thrusterOffset = path.scale.z * 0.35
            let thrusterBack = path.scale.x * 0.05
            pointer[baseIndex + 2] = VoxelInstance(
                position: position - direction * thrusterBack + right * thrusterOffset - up * 0.12,
                _pad0: 0,
                scale: SIMD3<Float>(0.55, 0.25, 0.55),
                _pad1: 0,
                rotationY: rotationY,
                rotationX: rotationX,
                rotationZ: rotationZ,
                _pad2: 0,
                materialID: 0,
                highlight: 0,
                hover: glow,
                textureIndex: planeTextureIndex,
                shapeID: 0
            )
            pointer[baseIndex + 3] = VoxelInstance(
                position: position - direction * thrusterBack - right * thrusterOffset - up * 0.12,
                _pad0: 0,
                scale: SIMD3<Float>(0.55, 0.25, 0.55),
                _pad1: 0,
                rotationY: rotationY,
                rotationX: rotationX,
                rotationZ: rotationZ,
                _pad2: 0,
                materialID: 0,
                highlight: 0,
                hover: glow,
                textureIndex: planeTextureIndex,
                shapeID: 0
            )
            let flameScale = showFlames ? SIMD3<Float>(0.9, 0.25, 0.25) : SIMD3<Float>(0, 0, 0)
            let flameBack = thrusterBack + path.scale.x * 0.18
            pointer[baseIndex + 4] = VoxelInstance(
                position: position - direction * flameBack + right * thrusterOffset - up * 0.1,
                _pad0: 0,
                scale: flameScale,
                _pad1: 0,
                rotationY: rotationY,
                rotationX: rotationX,
                rotationZ: rotationZ,
                _pad2: 0,
                materialID: 0,
                highlight: 0,
                hover: glow,
                textureIndex: -1,
                shapeID: 7
            )
            pointer[baseIndex + 5] = VoxelInstance(
                position: position - direction * flameBack - right * thrusterOffset - up * 0.1,
                _pad0: 0,
                scale: flameScale,
                _pad1: 0,
                rotationY: rotationY,
                rotationX: rotationX,
                rotationZ: rotationZ,
                _pad2: 0,
                materialID: 0,
                highlight: 0,
                hover: glow,
                textureIndex: -1,
                shapeID: 7
            )
            // Horizontal stabilizer (small tail wing)
            let tailBack = path.scale.x * 0.42
            pointer[baseIndex + 6] = VoxelInstance(
                position: position - bodyOffset - direction * tailBack + up * 0.15,
                _pad0: 0,
                scale: SIMD3<Float>(1.0, 0.06, 2.8),
                _pad1: 0,
                rotationY: rotationY,
                rotationX: rotationX,
                rotationZ: rotationZ,
                _pad2: 0,
                materialID: 0,
                highlight: 0,
                hover: glow * 0.5,
                textureIndex: planeTextureIndex,
                shapeID: 0
            )
            // Vertical fin (tail)
            pointer[baseIndex + 7] = VoxelInstance(
                position: position - bodyOffset - direction * tailBack + up * 0.55,
                _pad0: 0,
                scale: SIMD3<Float>(1.2, 0.9, 0.08),
                _pad1: 0,
                rotationY: rotationY,
                rotationX: rotationX,
                rotationZ: rotationZ,
                _pad2: 0,
                materialID: 0,
                highlight: 0,
                hover: glow * 0.5,
                textureIndex: planeTextureIndex,
                shapeID: 0
            )
            
            // Banner (Attach to all path-following planes if texture exists, skip for piloted plane)
            if bannerTextureIndex >= 0 && !isPiloted {
                // Get path distance for banner calculation (only for path-following planes)
                let baseDistance = fmod(Float(now) * path.speed + path.phase, path.totalLength)
                let offset = index < planeOffsets.count ? planeOffsets[index] : 0
                let pathDistance = fmod(baseDistance + offset, path.totalLength)

                let ropeLen: Float = 2.5
                let segmentCount = 8
                let segmentLen: Float = 1.5
                let uWidth = 1.0 / Float(segmentCount)

                // Trail start position (behind tail)
                let tailDist = pathDistance - tailBack - ropeLen

                for i in 0..<segmentCount {
                    let segDist = tailDist - Float(i) * segmentLen - segmentLen * 0.5

                    // Wrap distance for closed loop path
                    var d = segDist
                    if d < 0 { d += path.totalLength }

                    let pos = positionAlongPath(path: path, distance: d)
                    let nextPos = positionAlongPath(path: path, distance: d + 0.1) // Look ahead slightly

                    let dir = simd_normalize(nextPos - pos)
                    let rotY = atan2(dir.z, dir.x)

                    // uOffset calculation:
                    // Segments are 0..7. 0 is trailing the plane (Right side in World Space for L->R flight).
                    // 7 is the tail end (Left side).
                    // Text "Directory" reads L->R (0->1).
                    // So Seg 7 should correspond to U=0. Seg 0 should correspond to U=1.
                    // uOffset = (7 - i) * uWidth.
                    // i=0 -> 7 * 0.125 = 0.875.
                    // i=7 -> 0 * 0.125 = 0.0.
                    let uOffset = Float(segmentCount - 1 - i) * uWidth

                    pointer[baseIndex + 8 + i] = VoxelInstance(
                        position: pos,
                        _pad0: 0,
                        scale: SIMD3<Float>(segmentLen, 3.0, 0.1),
                        _pad1: 0,
                        rotationY: rotY,
                        rotationX: 0,
                        rotationZ: 0,
                        _pad2: 0,
                        materialID: 0,
                        highlight: uOffset, // Passed as U Offset
                        hover: 0,
                        activity: uWidth,   // Passed as U Width
                        activityKind: 0,
                        textureIndex: Int32(bannerTextureIndex),
                        shapeID: 13
                    )
                }
            } else {
                // Zero out unused slots (8..16) - piloted planes or no banner texture
                for i in 0..<8 {
                     pointer[baseIndex + 8 + i] = VoxelInstance(position: .zero, scale: .zero, rotationY: 0, rotationX: 0, rotationZ: 0, materialID: 0, textureIndex: -1, shapeID: 0)
                }
            }
        }
    }

    private func positionAlongPath(path: PlanePath, distance: Float) -> SIMD3<Float> {
        var remaining = distance
        for (index, segment) in path.segmentLengths.enumerated() {
            if remaining <= segment || index == path.segmentLengths.count - 1 {
                let a = path.waypoints[index]
                let b = path.waypoints[index + 1]
                let t = segment == 0 ? 0 : remaining / segment
                return a + (b - a) * t
            }
            remaining -= segment
        }
        return path.waypoints.last ?? SIMD3<Float>(0, 0, 0)
    }

    private func computeSegmentLengths(waypoints: [SIMD3<Float>]) -> [Float] {
        guard waypoints.count > 1 else { return [] }
        var lengths: [Float] = []
        lengths.reserveCapacity(waypoints.count - 1)
        for index in 0..<(waypoints.count - 1) {
            lengths.append(simd_length(waypoints[index + 1] - waypoints[index]))
        }
        return lengths
    }

    private func smoothPath(waypoints: [SIMD3<Float>], iterations: Int) -> [SIMD3<Float>] {
        guard waypoints.count > 2 else { return waypoints }
        var points = waypoints
        for _ in 0..<iterations {
            var smoothed: [SIMD3<Float>] = []
            smoothed.reserveCapacity(points.count * 2)
            smoothed.append(points[0])
            for index in 0..<(points.count - 1) {
                let p0 = points[index]
                let p1 = points[index + 1]
                let q = p0 * 0.75 + p1 * 0.25
                let r = p0 * 0.25 + p1 * 0.75
                smoothed.append(q)
                smoothed.append(r)
            }
            smoothed.append(points[points.count - 1])
            points = smoothed
        }
        return points
    }

    private func randomPerimeterPoint(width: Int, height: Int, seed: UInt64, edge: Int) -> (x: Int, y: Int) {
        let pick = Int((seed >> 8) % UInt64(max(1, max(width, height))))
        switch edge {
        case 0:
            return (x: min(pick, width - 1), y: 0)
        case 1:
            return (x: min(pick, width - 1), y: height - 1)
        case 2:
            return (x: 0, y: min(pick, height - 1))
        default:
            return (x: width - 1, y: min(pick, height - 1))
        }
    }

    private func randomInteriorPoint(width: Int, height: Int, seed: UInt64) -> (x: Int, y: Int) {
        let ix = max(0, min(width - 1, Int(seed % UInt64(width))))
        let iy = max(0, min(height - 1, Int((seed >> 8) % UInt64(height))))
        return (x: ix, y: iy)
    }

    private func findPath(start: (x: Int, y: Int), goal: (x: Int, y: Int), width: Int, height: Int) -> [(x: Int, y: Int)] {
        guard width > 0, height > 0 else { return [start, goal] }
        guard start.x >= 0, start.x < width, start.y >= 0, start.y < height,
              goal.x >= 0, goal.x < width, goal.y >= 0, goal.y < height else {
            return [start, goal]
        }
        let total = width * height
        var gScore = [Float](repeating: .greatestFiniteMagnitude, count: total)
        var fScore = [Float](repeating: .greatestFiniteMagnitude, count: total)
        var cameFrom = [Int](repeating: -1, count: total)
        var openSet: [Int] = []

        func indexFor(x: Int, y: Int) -> Int { y * width + x }
        func heuristic(x: Int, y: Int) -> Float {
            let dx = abs(goal.x - x)
            let dy = abs(goal.y - y)
            let diag = min(dx, dy)
            let straight = max(dx, dy) - diag
            return Float(diag) * 1.414 + Float(straight)
        }

        let startIndex = indexFor(x: start.x, y: start.y)
        gScore[startIndex] = 0
        fScore[startIndex] = heuristic(x: start.x, y: start.y)
        openSet.append(startIndex)

        let neighbors = [
            (-1, 0), (1, 0), (0, -1), (0, 1),
            (-1, -1), (1, -1), (-1, 1), (1, 1)
        ]

        while !openSet.isEmpty {
            let currentIndex = openSet.min(by: { fScore[$0] < fScore[$1] }) ?? openSet[0]
            if currentIndex == indexFor(x: goal.x, y: goal.y) {
                break
            }
            openSet.removeAll { $0 == currentIndex }

            let currentX = currentIndex % width
            let currentY = currentIndex / width
            for (dx, dy) in neighbors {
                let nx = currentX + dx
                let ny = currentY + dy
                if nx < 0 || ny < 0 || nx >= width || ny >= height { continue }
                let neighborIndex = indexFor(x: nx, y: ny)
                let cost: Float = (dx != 0 && dy != 0) ? 1.414 : 1.0
                let tentative = gScore[currentIndex] + cost
                if tentative < gScore[neighborIndex] {
                    cameFrom[neighborIndex] = currentIndex
                    gScore[neighborIndex] = tentative
                    fScore[neighborIndex] = tentative + heuristic(x: nx, y: ny)
                    if !openSet.contains(neighborIndex) {
                        openSet.append(neighborIndex)
                    }
                }
            }
        }

        var path: [(x: Int, y: Int)] = []
        let goalIndex = indexFor(x: goal.x, y: goal.y)
        if goalIndex < 0 || goalIndex >= total || cameFrom[goalIndex] == -1 {
            return [start, goal]
        }
        var current = goalIndex
        while current != -1 {
            let x = current % width
            let y = current / width
            path.append((x: x, y: y))
            current = cameFrom[current]
        }
        return path.reversed()
    }

    private func sortedUnique(values: [Float]) -> [Float] {
        let rounded = values.map { round($0 * 100.0) / 100.0 }
        return Array(Set(rounded)).sorted()
    }

    private func minSpacing(values: [Float]) -> Float {
        guard values.count > 1 else { return 0 }
        var minDiff: Float = .greatestFiniteMagnitude
        for index in 1..<values.count {
            let diff = values[index] - values[index - 1]
            if diff > 0 && diff < minDiff {
                minDiff = diff
            }
        }
        return minDiff == .greatestFiniteMagnitude ? 0 : minDiff
    }

    private func randomUnit(seed: UInt64) -> Float {
        let v = (seed &* 1103515245 &+ 12345) & 0x7fffffff
        return Float(v) / Float(0x7fffffff)
    }

    private func rayFrom(point: CGPoint, in size: CGSize) -> RayTracer.Ray {
        let viewMatrix = camera.viewMatrix()
        let projectionMatrix = camera.projectionMatrix()
        let viewProjection = projectionMatrix * viewMatrix
        let inverseViewProjection = simd_inverse(viewProjection)
        let ndcX = (2.0 * Float(point.x) / Float(size.width)) - 1.0
        let ndcY = (2.0 * Float(point.y) / Float(size.height)) - 1.0
        let nearPoint = SIMD4<Float>(ndcX, ndcY, -1.0, 1.0)
        let farPoint = SIMD4<Float>(ndcX, ndcY, 1.0, 1.0)
        let worldNear = inverseViewProjection * nearPoint
        let worldFar = inverseViewProjection * farPoint
        let nearPosition = SIMD3<Float>(
            worldNear.x / worldNear.w,
            worldNear.y / worldNear.w,
            worldNear.z / worldNear.w
        )
        let farPosition = SIMD3<Float>(
            worldFar.x / worldFar.w,
            worldFar.y / worldFar.w,
            worldFar.z / worldFar.w
        )
        let rayOrigin = nearPosition
        let rayDirection = simd_normalize(farPosition - nearPosition)
        return RayTracer.Ray(origin: rayOrigin, direction: rayDirection)
    }

    private func intersectSphere(ray: RayTracer.Ray, center: SIMD3<Float>, radius: Float) -> Float? {
        let oc = ray.origin - center
        let a = simd_dot(ray.direction, ray.direction)
        let b = 2.0 * simd_dot(oc, ray.direction)
        let c = simd_dot(oc, oc) - radius * radius
        let discriminant = b * b - 4.0 * a * c
        if discriminant < 0 { return nil }
        let sqrtD = sqrt(discriminant)
        let t1 = (-b - sqrtD) / (2.0 * a)
        let t2 = (-b + sqrtD) / (2.0 * a)
        if t1 >= 0 { return t1 }
        if t2 >= 0 { return t2 }
        return nil
    }

    func pickBlock(at point: CGPoint, in size: CGSize) -> CityBlock? {
        return pickBlockHit(at: point, in: size)?.block
    }

    func pickBlockHit(at point: CGPoint, in size: CGSize) -> (block: CityBlock, distance: Float)? {
        guard size.width > 1, size.height > 1, !blocks.isEmpty else { return nil }
        let viewMatrix = camera.viewMatrix()
        let projectionMatrix = camera.projectionMatrix()
        let viewProjection = projectionMatrix * viewMatrix
        let inverseViewProjection = simd_inverse(viewProjection)
        let ndcX = (2.0 * Float(point.x) / Float(size.width)) - 1.0
        let ndcY = (2.0 * Float(point.y) / Float(size.height)) - 1.0
        let nearPoint = SIMD4<Float>(ndcX, ndcY, -1.0, 1.0)
        let farPoint = SIMD4<Float>(ndcX, ndcY, 1.0, 1.0)
        let worldNear = inverseViewProjection * nearPoint
        let worldFar = inverseViewProjection * farPoint
        let nearPosition = SIMD3<Float>(
            worldNear.x / worldNear.w,
            worldNear.y / worldNear.w,
            worldNear.z / worldNear.w
        )
        let farPosition = SIMD3<Float>(
            worldFar.x / worldFar.w,
            worldFar.y / worldFar.w,
            worldFar.z / worldFar.w
        )
        let rayOrigin = nearPosition
        let rayDirection = simd_normalize(farPosition - nearPosition)

        let ray = RayTracer.Ray(origin: rayOrigin, direction: rayDirection)
        let tracer = RayTracer()
        // Use wedgeYaw (fixed isometric angle) for wedge rotation - wedges are always rendered at this angle
        if let hit = tracer.intersect(ray: ray, blocks: blocks, cameraYaw: camera.wedgeYaw),
           let block = blocks.first(where: { $0.nodeID == hit.blockID }) {
            return (block, hit.distance)
        }

        return nil
    }

    /// Pick a grapple target - returns position and attachment type for holding onto moving objects
    func pickGrappleTarget(at point: CGPoint, in size: CGSize) -> (position: SIMD3<Float>, attachment: Camera.GrappleAttachment)? {
        guard size.width > 1, size.height > 1 else { return nil }
        let ray = rayFrom(point: point, in: size)

        var closestHit: (position: SIMD3<Float>, distance: Float, attachment: Camera.GrappleAttachment)?

        // Check blocks
        if !blocks.isEmpty {
            let tracer = RayTracer()
            if let hit = tracer.intersect(ray: RayTracer.Ray(origin: ray.origin, direction: ray.direction), blocks: blocks, cameraYaw: camera.wedgeYaw) {
                let hitPoint = ray.origin + ray.direction * hit.distance
                if closestHit == nil || hit.distance < closestHit!.distance {
                    closestHit = (hitPoint, hit.distance, .block(position: hitPoint))
                }
            }
        }

        // Check planes (includes banners attached to them)
        let now = CACurrentMediaTime()
        for (index, path) in planePaths.enumerated() {
            guard !explodedPlaneIndices.contains(index) else { continue }

            let baseDistance = fmod(Float(now) * path.speed + path.phase, path.totalLength)
            let offset = index < planeOffsets.count ? planeOffsets[index] : 0
            let distance = fmod(baseDistance + offset, path.totalLength)
            let position = positionAlongPath(path: path, distance: distance)
            let radius = max(path.scale.x, path.scale.z) * 0.75

            if let hitDist = intersectSphere(ray: ray, center: position, radius: radius) {
                if closestHit == nil || hitDist < closestHit!.distance {
                    closestHit = (position, hitDist, .plane(index: index))
                }
            }

            // Also check banner area (below the plane)
            if bannerTextureIndex >= 0 {
                let bannerCenter = position - SIMD3<Float>(0, 5.0, 0)  // Banner hangs below
                let bannerRadius: Float = 8.0  // Generous radius for banner
                if let hitDist = intersectSphere(ray: ray, center: bannerCenter, radius: bannerRadius) {
                    if closestHit == nil || hitDist < closestHit!.distance {
                        closestHit = (bannerCenter, hitDist, .plane(index: index))
                    }
                }
            }
        }

        // Check helicopters
        let heliTargets = helicopterManager.getHelicopterHitTargets()
        for (index, target) in heliTargets.enumerated() {
            if let hitDist = intersectSphere(ray: ray, center: target.position, radius: target.radius) {
                if closestHit == nil || hitDist < closestHit!.distance {
                    closestHit = (target.position, hitDist, .helicopter(index: index))
                }
            }
        }

        // Check beacons (git repo towers)
        for box in gitBeaconBoxes {
            if let hitDist = rayIntersectAABB(origin: ray.origin, direction: ray.direction, minBounds: box.min, maxBounds: box.max) {
                let beaconCenter = (box.min + box.max) * 0.5
                if closestHit == nil || hitDist < closestHit!.distance {
                    closestHit = (beaconCenter, hitDist, .beacon(nodeID: box.nodeID))
                }
            }
        }

        // Check cars
        for (index, path) in carPaths.enumerated() {
            let t = fmod(Float(now) * path.speed + path.phase, 1.0)
            let position = path.start + (path.end - path.start) * t
            // Car radius based on scale - use max of X/Z for width, with some extra for the body
            let radius = max(path.scale.x, path.scale.z) * 0.6
            let carCenter = position + SIMD3<Float>(0, 0.5, 0)  // Cars are slightly above ground

            if let hitDist = intersectSphere(ray: ray, center: carCenter, radius: radius) {
                if closestHit == nil || hitDist < closestHit!.distance {
                    closestHit = (carCenter, hitDist, .car(index: index))
                }
            }
        }

        // Check satellites
        let satelliteHitBoxes = satelliteManager.getSatelliteHitBoxes()
        for box in satelliteHitBoxes {
            // Use a sphere around the satellite center for grappling (simpler than OBB)
            let radius = max(box.halfExtents.x, max(box.halfExtents.y, box.halfExtents.z)) * 2.0
            if let hitDist = intersectSphere(ray: ray, center: box.center, radius: radius) {
                if closestHit == nil || hitDist < closestHit!.distance {
                    closestHit = (box.center, hitDist, .satellite(sessionID: box.sessionID))
                }
            }
        }

        if let hit = closestHit {
            return (hit.position, hit.attachment)
        }
        return nil
    }

    /// Get current position of a plane by index (for grapple attachment following)
    func planePosition(index: Int) -> SIMD3<Float>? {
        // If this plane is being piloted, return the piloted position
        if index == pilotedPlaneIndex, let state = pilotedPlaneFlightState {
            return state.position
        }

        guard index >= 0, index < planePaths.count, !explodedPlaneIndices.contains(index) else { return nil }
        let path = planePaths[index]
        let now = CACurrentMediaTime()
        let baseDistance = fmod(Float(now) * path.speed + path.phase, path.totalLength)
        let offset = index < planeOffsets.count ? planeOffsets[index] : 0
        let distance = fmod(baseDistance + offset, path.totalLength)
        return positionAlongPath(path: path, distance: distance)
    }

    /// Get current yaw (heading) of a plane by index
    /// Returns yaw in Camera's convention where forward = (sin(yaw), 0, cos(yaw))
    func planeYaw(index: Int) -> Float? {
        // If this plane is being piloted, return the piloted yaw
        if index == pilotedPlaneIndex, let state = pilotedPlaneFlightState {
            return state.yaw
        }

        guard index >= 0, index < planePaths.count, !explodedPlaneIndices.contains(index) else { return nil }
        let path = planePaths[index]
        let now = CACurrentMediaTime()
        let baseDistance = fmod(Float(now) * path.speed + path.phase, path.totalLength)
        let offset = index < planeOffsets.count ? planeOffsets[index] : 0
        let distance = fmod(baseDistance + offset, path.totalLength)
        let position = positionAlongPath(path: path, distance: distance)
        let nextPosition = positionAlongPath(path: path, distance: fmod(distance + 1.0, path.totalLength))
        let direction = simd_normalize(nextPosition - position)
        // Camera convention: forward = (sin(yaw), 0, cos(yaw))
        // So yaw = atan2(direction.x, direction.z)
        return atan2(direction.x, direction.z)
    }

    /// Start piloting a plane
    func startPilotingPlane(index: Int) {
        guard index >= 0, index < planePaths.count, !explodedPlaneIndices.contains(index) else { return }
        pilotedPlaneIndex = index
    }

    /// Stop piloting - creates a crashing plane that falls and explodes
    func stopPilotingPlane() {
        // Create a crashing plane from the current flight state
        if let index = pilotedPlaneIndex,
           let state = pilotedPlaneFlightState,
           index < planePaths.count {
            let path = planePaths[index]
            let crashingPlane = CrashingPlane(
                position: state.position,
                velocity: state.velocity,
                pitch: state.pitch,
                roll: state.roll,
                yaw: state.yaw,
                scale: path.scale,
                planeIndex: index
            )
            crashingPlanes.append(crashingPlane)
            // Mark this plane index as exploded so it doesn't render on its path
            explodedPlaneIndices.insert(index)
        }

        pilotedPlaneIndex = nil
        pilotedPlaneFlightState = nil
    }

    /// Get current position of a helicopter by index (for grapple attachment following)
    func helicopterPosition(index: Int) -> SIMD3<Float>? {
        let targets = helicopterManager.getHelicopterHitTargets()
        guard index >= 0, index < targets.count else { return nil }
        return targets[index].position
    }

    func satellitePosition(sessionID: UUID) -> SIMD3<Float>? {
        satelliteManager.getSatelliteTarget(sessionID: sessionID)?.position
    }

    /// Get satellite target (position and radius) for a specific sessionID
    func getSatelliteTarget(sessionID: UUID) -> (position: SIMD3<Float>, radius: Float)? {
        return satelliteManager.getSatelliteTarget(sessionID: sessionID)
    }

    /// Get all active satellites with their positions and radii (for collision detection)
    func getSatellitePositions() -> [(position: SIMD3<Float>, radius: Float, sessionID: UUID)] {
        var positions: [(SIMD3<Float>, Float, UUID)] = []

        // Query all active satellites
        let hitBoxes = satelliteManager.getSatelliteHitBoxes()

        // Group by sessionID to avoid duplicates (each satellite has 5 hitboxes)
        var seenSessions = Set<UUID>()

        for box in hitBoxes {
            if !seenSessions.contains(box.sessionID) {
                seenSessions.insert(box.sessionID)

                if let (pos, radius) = satelliteManager.getSatelliteTarget(sessionID: box.sessionID) {
                    positions.append((pos, radius, box.sessionID))
                }
            }
        }

        return positions
    }

    /// Get current position of a car by index (for grapple attachment following)
    func carPosition(index: Int) -> SIMD3<Float>? {
        guard index >= 0, index < carPaths.count else { return nil }
        let path = carPaths[index]
        let now = CACurrentMediaTime()
        let t = fmod(Float(now) * path.speed + path.phase, 1.0)
        let position = path.start + (path.end - path.start) * t
        return position + SIMD3<Float>(0, 0.5, 0)  // Car center is slightly above ground
    }

    func pickBeacon(at point: CGPoint, in size: CGSize) -> UUID? {
        guard size.width > 1, size.height > 1, !gitBeaconBoxes.isEmpty else { return nil }
        let ray = rayFrom(point: point, in: size)
        return BeaconPicker.pick(ray: ray, boxes: gitBeaconBoxes)
    }

    func pickBeaconHit(at point: CGPoint, in size: CGSize) -> (nodeID: UUID, distance: Float)? {
        guard size.width > 1, size.height > 1, !gitBeaconBoxes.isEmpty else { return nil }
        let ray = rayFrom(point: point, in: size)
        return BeaconPicker.pickWithDistance(ray: ray, boxes: gitBeaconBoxes)
    }

    private func rayIntersectAABB(origin: SIMD3<Float>, direction: SIMD3<Float>, minBounds: SIMD3<Float>, maxBounds: SIMD3<Float>) -> Float? {
        let invDirection = SIMD3<Float>(
            direction.x == 0 ? .greatestFiniteMagnitude : 1.0 / direction.x,
            direction.y == 0 ? .greatestFiniteMagnitude : 1.0 / direction.y,
            direction.z == 0 ? .greatestFiniteMagnitude : 1.0 / direction.z
        )
        let t1 = (minBounds - origin) * invDirection
        let t2 = (maxBounds - origin) * invDirection
        let tMin = max(max(min(t1.x, t2.x), min(t1.y, t2.y)), min(t1.z, t2.z))
        let tMax = min(min(max(t1.x, t2.x), max(t1.y, t2.y)), max(t1.z, t2.z))
        if tMax < 0 || tMin > tMax { return nil }
        return tMin >= 0 ? tMin : tMax
    }
    
    private func rayIntersectTriangle(origin: SIMD3<Float>, direction: SIMD3<Float>, v0: SIMD3<Float>, v1: SIMD3<Float>, v2: SIMD3<Float>) -> Float? {
        let epsilon: Float = 0.0000001
        let edge1 = v1 - v0
        let edge2 = v2 - v0
        let h = simd_cross(direction, edge2)
        let a = simd_dot(edge1, h)
        
        if a > -epsilon && a < epsilon { return nil }
        
        let f = 1.0 / a
        let s = origin - v0
        let u = f * simd_dot(s, h)
        
        if u < 0.0 || u > 1.0 { return nil }
        
        let q = simd_cross(s, edge1)
        let v = f * simd_dot(direction, q)
        
        if v < 0.0 || u + v > 1.0 { return nil }
        
        let t = f * simd_dot(edge2, q)
        
        if t > epsilon {
            return t
        }
        return nil
    }

    private static func vertexDescriptor() -> MTLVertexDescriptor {
        let descriptor = MTLVertexDescriptor()
        descriptor.attributes[0].format = .float3
        descriptor.attributes[0].offset = 0
        descriptor.attributes[0].bufferIndex = 0
        descriptor.attributes[1].format = .float3
        descriptor.attributes[1].offset = MemoryLayout<SIMD3<Float>>.stride
        descriptor.attributes[1].bufferIndex = 0
        descriptor.attributes[2].format = .float2
        descriptor.attributes[2].offset = MemoryLayout<SIMD3<Float>>.stride * 2
        descriptor.attributes[2].bufferIndex = 0
        descriptor.layouts[0].stride = MemoryLayout<Vertex>.stride
        return descriptor
    }

    private static func buildCubeVertices() -> [Vertex] {
        let p: Float = 0.5
        let nX = SIMD3<Float>(-1, 0, 0)
        let pX = SIMD3<Float>(1, 0, 0)
        let nY = SIMD3<Float>(0, -1, 0)
        let pY = SIMD3<Float>(0, 1, 0)
        let nZ = SIMD3<Float>(0, 0, -1)
        let pZ = SIMD3<Float>(0, 0, 1)

        func quad(_ a: SIMD3<Float>, _ b: SIMD3<Float>, _ c: SIMD3<Float>, _ d: SIMD3<Float>, _ n: SIMD3<Float>) -> [Vertex] {
            [
                Vertex(position: a, normal: n, uv: SIMD2<Float>(0, 1)),
                Vertex(position: b, normal: n, uv: SIMD2<Float>(1, 1)),
                Vertex(position: c, normal: n, uv: SIMD2<Float>(1, 0)),
                Vertex(position: a, normal: n, uv: SIMD2<Float>(0, 1)),
                Vertex(position: c, normal: n, uv: SIMD2<Float>(1, 0)),
                Vertex(position: d, normal: n, uv: SIMD2<Float>(0, 0)),
            ]
        }

        let v0 = SIMD3<Float>(-p, -p, -p)
        let v1 = SIMD3<Float>(p, -p, -p)
        let v2 = SIMD3<Float>(p, p, -p)
        let v3 = SIMD3<Float>(-p, p, -p)
        let v4 = SIMD3<Float>(-p, -p, p)
        let v5 = SIMD3<Float>(p, -p, p)
        let v6 = SIMD3<Float>(p, p, p)
        let v7 = SIMD3<Float>(-p, p, p)

        return quad(v0, v1, v2, v3, nZ)
            + quad(v5, v4, v7, v6, pZ)
            + quad(v4, v0, v3, v7, nX)
            + quad(v1, v5, v6, v2, pX)
            + quad(v4, v5, v1, v0, nY)
            + quad(v3, v2, v6, v7, pY)
    }

    private func centerOf(blocks: [CityBlock]) -> SIMD3<Float> {
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

        return SIMD3<Float>((minX + maxX) * 0.5, 0, (minZ + maxZ) * 0.5)
    }

    func autoFitCamera(blocks: [CityBlock]) {
        guard let bounds = boundsOf(blocks: blocks) else { return }
        let center = (bounds.min + bounds.max) * 0.5
        let radius = maxDistance(from: center, minBounds: bounds.min, maxBounds: bounds.max)
        let fovY: Float = 0.75
        let fovX = 2 * atan(tan(fovY * 0.5) * max(camera.aspect, 0.01))
        let halfAngle = min(fovY * 0.5, fovX * 0.5)
        let paddedRadius = radius * 1.1
        let distance = paddedRadius / max(tan(halfAngle), 0.001)
        camera.target = center
        camera.distance = max(10, min(1000, distance))
    }

    private func boundsOf(blocks: [CityBlock]) -> (min: SIMD3<Float>, max: SIMD3<Float>)? {
        guard !blocks.isEmpty else { return nil }
        var minX: Float = .greatestFiniteMagnitude
        var maxX: Float = -.greatestFiniteMagnitude
        var minY: Float = .greatestFiniteMagnitude
        var maxY: Float = -.greatestFiniteMagnitude
        var minZ: Float = .greatestFiniteMagnitude
        var maxZ: Float = -.greatestFiniteMagnitude

        for block in blocks {
            let halfX = Float(block.footprint.x) * 0.5
            let halfZ = Float(block.footprint.y) * 0.5
            minX = min(minX, block.position.x - halfX)
            maxX = max(maxX, block.position.x + halfX)
            minZ = min(minZ, block.position.z - halfZ)
            maxZ = max(maxZ, block.position.z + halfZ)
            minY = min(minY, block.position.y)
            maxY = max(maxY, block.visualTopY)
        }

        return (SIMD3<Float>(minX, minY, minZ), SIMD3<Float>(maxX, maxY, maxZ))
    }

    private func maxDistance(from center: SIMD3<Float>, minBounds: SIMD3<Float>, maxBounds: SIMD3<Float>) -> Float {
        let corners = [
            SIMD3<Float>(minBounds.x, minBounds.y, minBounds.z),
            SIMD3<Float>(minBounds.x, minBounds.y, maxBounds.z),
            SIMD3<Float>(minBounds.x, maxBounds.y, minBounds.z),
            SIMD3<Float>(minBounds.x, maxBounds.y, maxBounds.z),
            SIMD3<Float>(maxBounds.x, minBounds.y, minBounds.z),
            SIMD3<Float>(maxBounds.x, minBounds.y, maxBounds.z),
            SIMD3<Float>(maxBounds.x, maxBounds.y, minBounds.z),
            SIMD3<Float>(maxBounds.x, maxBounds.y, maxBounds.z)
        ]
        var maxDistance: Float = 0
        for corner in corners {
            maxDistance = max(maxDistance, simd_distance(center, corner))
        }
        return maxDistance
    }
}
