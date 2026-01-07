import Metal
import MetalKit
import simd
import CryptoKit

final class MetalRenderer: NSObject, MTKViewDelegate {
    private let device: MTLDevice
    private let commandQueue: MTLCommandQueue
    private let pipelineState: MTLRenderPipelineState
    private let depthState: MTLDepthStencilState
    private let samplerState: MTLSamplerState
    private let cubeVertexBuffer: MTLBuffer
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
    private var gitBeaconBoxes: [BeaconPicker.Box] = []
    private let beaconHitInflation: Float = 1.0
    private var blocks: [CityBlock] = []
    let camera = Camera()

    struct Vertex {
        let position: SIMD3<Float>
        let normal: SIMD3<Float>
        let uv: SIMD2<Float>
    }

    struct Uniforms {
        var viewProjection: simd_float4x4
        var time: Float
        var _pad: SIMD3<Float> = .zero
    }

    private struct CarPath {
        let start: SIMD3<Float>
        let end: SIMD3<Float>
        let speed: Float
        let phase: Float
        let scale: SIMD3<Float>
    }

    private struct PlanePath {
        let waypoints: [SIMD3<Float>]
        let segmentLengths: [Float]
        let totalLength: Float
        let speed: Float
        let phase: Float
        let scale: SIMD3<Float>
    }

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
        
        let descriptor = MTLTextureDescriptor()
        descriptor.textureType = .type2DArray
        descriptor.pixelFormat = first.pixelFormat
        descriptor.width = first.width
        descriptor.height = first.height
        descriptor.arrayLength = sourceTextures.count
        descriptor.usage = .shaderRead
        
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
        
        blitEncoder.endEncoding()
        commandBuffer.commit()
        
        self.textureArray = arrayTex
    }

    func updateInstances(blocks: [CityBlock],
                         selectedNodeID: UUID?,
                         hoveredNodeID: UUID?,
                         hoveredBeaconNodeID: UUID?,
                         activityByNodeID: [UUID: NodeActivityPulse],
                         activityNow: CFTimeInterval,
                         activityDuration: CFTimeInterval) {
        let blocksChanged = blocks != self.blocks
        self.blocks = blocks
        let cameraYaw = camera.yaw
        var instances: [VoxelInstance] = blocks.map { block in
            let rotationY = rotationYForWedge(block: block, cameraYaw: cameraYaw)
            let isHovering = block.nodeID == hoveredNodeID || block.nodeID == hoveredBeaconNodeID
            let activity = activityByNodeID[block.nodeID]
            let activityStrength: Float
            let activityKind: Int32
            if let activity {
                let elapsed = max(0, activityNow - activity.startedAt)
                let normalized = max(0, 1.0 - (elapsed / max(0.001, activityDuration)))
                activityStrength = Float(normalized)
                activityKind = activity.kind.rawValue
            } else {
                activityStrength = 0
                activityKind = 0
            }
            return VoxelInstance(
                position: SIMD3<Float>(block.position.x, block.position.y + Float(block.height) * 0.5, block.position.z),
                scale: SIMD3<Float>(Float(block.footprint.x), Float(block.height), Float(block.footprint.y)),
                rotationY: rotationY,
                materialID: UInt32(block.materialID),
                highlight: block.nodeID == selectedNodeID ? 1.0 : 0.0,
                hover: isHovering ? 1.0 : 0.0,
                activity: activityStrength,
                activityKind: activityKind,
                textureIndex: block.textureIndex,
                shapeID: block.shapeID
            )
        }
        let gitTowerInstances = buildGitTowerInstances(blocks: blocks, hoveredBeaconNodeID: hoveredBeaconNodeID)
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

    private func rotationYForWedge(block: CityBlock, cameraYaw: Float) -> Float {
        guard block.shapeID == 3 || block.shapeID == 4 else { return 0 }
        return cameraYaw + (.pi / 4)
    }

    private func buildGitTowerInstances(blocks: [CityBlock], hoveredBeaconNodeID: UUID?) -> [VoxelInstance] {
        var topBlocks: [UUID: CityBlock] = [:]
        var topHeights: [UUID: Float] = [:]
        gitBeaconBoxes.removeAll()
        for block in blocks where block.isGitRepo {
            let topY = visualTopY(for: block)
            if let existing = topHeights[block.nodeID], existing >= topY {
                continue
            }
            topHeights[block.nodeID] = topY
            topBlocks[block.nodeID] = block
        }
        guard !topBlocks.isEmpty else { return [] }

        var instances: [VoxelInstance] = []
        instances.reserveCapacity(topBlocks.count * 4)
        for block in topBlocks.values {
            let beaconHighlight: Float = block.nodeID == hoveredBeaconNodeID ? 1.0 : 0.0
            let towerMaterialID = block.isGitClean ? gitCleanMaterialID : gitTowerMaterialID
            let footprintX = Float(block.footprint.x)
            let footprintZ = Float(block.footprint.y)
            let baseTopY = block.position.y + Float(block.height)
            let visualTopY = visualTopY(for: block)
            var roofY = visualTopY
            if block.shapeID == 2 {
                roofY = baseTopY + (visualTopY - baseTopY) * 0.42
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
            let rotationY = rotationYForWedge(block: block, cameraYaw: camera.yaw)
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
                baseY += towerSize * 0.25
            }
            if block.shapeID == 2 {
                let tipY = visualTopY
                towerHeight = max(0.8, tipY - baseY)
            }
            let mastY = baseY + towerHeight * 0.5
            let crossbarY = baseY + towerHeight * 0.8
            var beaconY = baseY + towerHeight + beaconSize * 0.5
            if block.shapeID == 2 {
                beaconY = visualTopY + beaconSize * 0.5
            }
            let towerBaseX = baseX + beaconOffsetX
            let towerBaseZ = baseZ + beaconOffsetZ

            instances.append(VoxelInstance(
                position: SIMD3<Float>(towerBaseX, baseY, towerBaseZ),
                scale: SIMD3<Float>(towerSize * 0.55, towerSize * 0.2, towerSize * 0.55),
                materialID: towerMaterialID,
                highlight: beaconHighlight,
                textureIndex: -1,
                shapeID: 5
            ))

            instances.append(VoxelInstance(
                position: SIMD3<Float>(towerBaseX, mastY, towerBaseZ),
                scale: SIMD3<Float>(towerSize * 0.18, towerHeight, towerSize * 0.18),
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
                materialID: towerMaterialID,
                highlight: beaconHighlight,
                textureIndex: -1,
                shapeID: 0
            ))

            instances.append(VoxelInstance(
                position: SIMD3<Float>(crossbarX, beaconY, crossbarZ),
                scale: SIMD3<Float>(beaconSize, beaconSize, beaconSize),
                materialID: towerMaterialID,
                highlight: beaconHighlight,
                textureIndex: -1,
                shapeID: block.isGitClean ? 9 : 8
            ))

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

    private func visualTopY(for block: CityBlock) -> Float {
        let baseTop = block.position.y + Float(block.height)
        let spireBoost: Float
        switch block.shapeID {
        case 1, 2, 3, 4:
            spireBoost = Float(block.height) * 0.5
        default:
            spireBoost = 0
        }
        return baseTop + spireBoost
    }

    func setHoveredPlane(index: Int?) {
        hoveredPlaneIndex = index
    }

    func pickPlane(at point: CGPoint, in size: CGSize) -> Int? {
        guard size.width > 1, size.height > 1, !planePaths.isEmpty else { return nil }
        let ray = rayFrom(point: point, in: size)
        let now = CACurrentMediaTime()
        var closest: (index: Int, distance: Float)?

        for (index, path) in planePaths.enumerated() {
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
        encoder?.setRenderPipelineState(pipelineState)
        encoder?.setDepthStencilState(depthState)
        encoder?.setVertexBuffer(cubeVertexBuffer, offset: 0, index: 0)

        var uniforms = Uniforms(viewProjection: camera.projectionMatrix() * camera.viewMatrix(),
                                time: Float(CACurrentMediaTime()))
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
            encoder?.setVertexBuffer(planeInstanceBuffer, offset: 0, index: 1)
            encoder?.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 36, instanceCount: planeInstanceCount)
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

        for zIndex in 0..<(zs.count - 1) {
            let roadZ = zs[zIndex] + stepZ * 0.5
            let instance = VoxelInstance(
                position: SIMD3<Float>(centerX, -0.6, roadZ),
                scale: SIMD3<Float>(spanX, 1.0, Float(roadWidth)),
                materialID: 0,
                textureIndex: roadTextureIndex,
                shapeID: 0
            )
            roadInstances.append(instance)
        }

        for xIndex in 0..<(xs.count - 1) {
            let roadX = xs[xIndex] + stepX * 0.5
            let instance = VoxelInstance(
                position: SIMD3<Float>(roadX, -0.6, centerZ),
                scale: SIMD3<Float>(Float(roadWidth), 1.0, spanZ),
                materialID: 0,
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

        for (index, z) in zs.dropLast().enumerated() {
            let roadZ = z + stepZ * 0.5
            let distance = max(1.0, spanX)
            let carCount = max(1, Int(distance / 40.0))
            for carIndex in 0..<carCount {
                let seed = UInt64(index * 73 + carIndex * 17)
                let speed = (2.0 + randomUnit(seed: seed) * 3.0) / distance
                let phase = randomUnit(seed: seed ^ 0xCAFE)
                let forward = (index % 2 == 0)
                let start = SIMD3<Float>(forward ? minX - 2.0 : maxX + 2.0, 0.5, roadZ + laneOffset)
                let end = SIMD3<Float>(forward ? maxX + 2.0 : minX - 2.0, 0.5, roadZ + laneOffset)
                let scale = SIMD3<Float>(3.2, 1.2, 1.6)
                carPaths.append(CarPath(start: start, end: end, speed: speed, phase: phase, scale: scale))
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
                let start = SIMD3<Float>(roadX - laneOffset, 0.5, forward ? minZ - 2.0 : maxZ + 2.0)
                let end = SIMD3<Float>(roadX - laneOffset, 0.5, forward ? maxZ + 2.0 : minZ - 2.0)
                let scale = SIMD3<Float>(1.6, 1.2, 3.2)
                carPaths.append(CarPath(start: start, end: end, speed: speed, phase: phase, scale: scale))
            }
        }

        carInstanceCount = carPaths.count
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

        let xRoads = (0..<(xs.count - 1)).map { xs[$0] + stepX * 0.5 }
        let zRoads = (0..<(zs.count - 1)).map { zs[$0] + stepZ * 0.5 }
        guard !xRoads.isEmpty, !zRoads.isEmpty else { return }

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
            let smoothed = smoothPath(waypoints: waypoints, iterations: 2)
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

        planeInstanceCount = planePaths.count * 8
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

        guard !labelTextures.isEmpty, let first = labelTextures.first else { return }

        // Create texture array for sign labels
        let descriptor = MTLTextureDescriptor()
        descriptor.textureType = .type2DArray
        descriptor.pixelFormat = first.pixelFormat
        descriptor.width = first.width
        descriptor.height = first.height
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

        let postHeight: Float = 2.0
        let postWidth: Float = 0.3
        let signboardHeight: Float = 0.8
        let signboardWidth: Float = 3.2

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
                materialID: 10,
                textureIndex: -1,
                shapeID: 0
            ))

            // Signboard with pre-baked texture (shapeID 11 for sign label)
            let boardY = baseY + postHeight + signboardHeight * 0.5
            instances.append(VoxelInstance(
                position: SIMD3<Float>(signX + 0.1, boardY, signZ),
                scale: SIMD3<Float>(0.1, signboardHeight, signboardWidth),
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
        let pointer = carInstanceBuffer.contents().bindMemory(to: VoxelInstance.self, capacity: carPaths.count)
        for (index, path) in carPaths.enumerated() {
            let t = fmod(Float(now) * path.speed + path.phase, 1.0)
            let position = path.start + (path.end - path.start) * t
            pointer[index] = VoxelInstance(
                position: position,
                scale: path.scale,
                materialID: 0,
                textureIndex: carTextureIndex,
                shapeID: 0
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
            let isHovered = hoveredPlaneIndex == index
            let speedBoost: Float = isHovered ? 1.6 : 1.0
            if index < planeOffsets.count, speedBoost > 1.0 {
                planeOffsets[index] = fmod(planeOffsets[index] + Float(deltaTime) * path.speed * (speedBoost - 1.0), path.totalLength)
            }
            let baseDistance = fmod(Float(now) * path.speed + path.phase, path.totalLength)
            let offset = index < planeOffsets.count ? planeOffsets[index] : 0
            let distance = fmod(baseDistance + offset, path.totalLength)
            let position = positionAlongPath(path: path, distance: distance)
            let nextDistance = fmod(distance + 1.0, path.totalLength)
            let nextPosition = positionAlongPath(path: path, distance: nextDistance)
            let direction = simd_normalize(nextPosition - position)
            let right = simd_normalize(SIMD3<Float>(-direction.z, 0, direction.x))
            let rotationY = atan2(direction.z, direction.x)
            let glow = isHovered ? (0.6 + 0.4 * sin(Float(now) * 18.0)) : 0.0
            let baseIndex = index * 8
            let bodyOffset = direction * (path.scale.x * 0.1)  // Shift body back so longer tail extends rearward
            pointer[baseIndex] = VoxelInstance(
                position: position - bodyOffset,
                _pad0: 0,
                scale: path.scale,
                _pad1: 0,
                rotationY: rotationY,
                _pad2: 0,
                materialID: 0,
                highlight: 0,
                hover: glow,
                textureIndex: planeTextureIndex,
                shapeID: 6
            )
            pointer[baseIndex + 1] = VoxelInstance(
                position: SIMD3<Float>(position.x, position.y + 0.1, position.z),
                _pad0: 0,
                scale: SIMD3<Float>(1.4, 0.08, 6.3),
                _pad1: 0,
                rotationY: rotationY,
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
                position: position - direction * thrusterBack + right * thrusterOffset - SIMD3<Float>(0, 0.12, 0),
                _pad0: 0,
                scale: SIMD3<Float>(0.55, 0.25, 0.55),
                _pad1: 0,
                rotationY: rotationY,
                _pad2: 0,
                materialID: 0,
                highlight: 0,
                hover: glow,
                textureIndex: planeTextureIndex,
                shapeID: 0
            )
            pointer[baseIndex + 3] = VoxelInstance(
                position: position - direction * thrusterBack - right * thrusterOffset - SIMD3<Float>(0, 0.12, 0),
                _pad0: 0,
                scale: SIMD3<Float>(0.55, 0.25, 0.55),
                _pad1: 0,
                rotationY: rotationY,
                _pad2: 0,
                materialID: 0,
                highlight: 0,
                hover: glow,
                textureIndex: planeTextureIndex,
                shapeID: 0
            )
            let flameScale = isHovered ? SIMD3<Float>(0.9, 0.25, 0.25) : SIMD3<Float>(0, 0, 0)
            let flameBack = thrusterBack + path.scale.x * 0.18
            pointer[baseIndex + 4] = VoxelInstance(
                position: position - direction * flameBack + right * thrusterOffset - SIMD3<Float>(0, 0.1, 0),
                _pad0: 0,
                scale: flameScale,
                _pad1: 0,
                rotationY: rotationY,
                _pad2: 0,
                materialID: 0,
                highlight: 0,
                hover: glow,
                textureIndex: -1,
                shapeID: 7
            )
            pointer[baseIndex + 5] = VoxelInstance(
                position: position - direction * flameBack - right * thrusterOffset - SIMD3<Float>(0, 0.1, 0),
                _pad0: 0,
                scale: flameScale,
                _pad1: 0,
                rotationY: rotationY,
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
                position: position - bodyOffset - direction * tailBack + SIMD3<Float>(0, 0.15, 0),
                _pad0: 0,
                scale: SIMD3<Float>(1.0, 0.06, 2.8),
                _pad1: 0,
                rotationY: rotationY,
                _pad2: 0,
                materialID: 0,
                highlight: 0,
                hover: glow * 0.5,
                textureIndex: planeTextureIndex,
                shapeID: 0
            )
            // Vertical fin (tail)
            pointer[baseIndex + 7] = VoxelInstance(
                position: position - bodyOffset - direction * tailBack + SIMD3<Float>(0, 0.55, 0),
                _pad0: 0,
                scale: SIMD3<Float>(1.2, 0.9, 0.08),
                _pad1: 0,
                rotationY: rotationY,
                _pad2: 0,
                materialID: 0,
                highlight: 0,
                hover: glow * 0.5,
                textureIndex: planeTextureIndex,
                shapeID: 0
            )
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
        if let hit = tracer.intersect(ray: ray, blocks: blocks, cameraYaw: camera.yaw),
           let block = blocks.first(where: { $0.nodeID == hit.blockID }) {
            return (block, hit.distance)
        }
        
        return nil
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
            maxY = max(maxY, visualTopY(for: block))
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
