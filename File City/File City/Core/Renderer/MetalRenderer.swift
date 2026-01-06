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
    private var roadInstanceBuffer: MTLBuffer?
    private var roadInstanceCount: Int = 0
    private var carInstanceBuffer: MTLBuffer?
    private var carInstanceCount: Int = 0
    private var carPaths: [CarPath] = []
    private var blocks: [CityBlock] = []
    let camera = Camera()

    struct Vertex {
        let position: SIMD3<Float>
        let normal: SIMD3<Float>
        let uv: SIMD2<Float>
    }

    struct Uniforms {
        var viewProjection: simd_float4x4
    }

    private struct CarPath {
        let start: SIMD3<Float>
        let end: SIMD3<Float>
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
        descriptor.fragmentFunction = library.makeFunction(name: "fragment_main")
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
        let textureCount = 34
        
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

    func updateInstances(blocks: [CityBlock], selectedNodeID: UUID?, hoveredNodeID: UUID?) {
        let blocksChanged = blocks != self.blocks
        self.blocks = blocks
        let instances = blocks.map { block in
            VoxelInstance(
                position: SIMD3<Float>(block.position.x, block.position.y + Float(block.height) * 0.5, block.position.z),
                scale: SIMD3<Float>(Float(block.footprint.x), Float(block.height), Float(block.footprint.y)),
                materialID: UInt32(block.materialID),
                highlight: block.nodeID == selectedNodeID ? 1.0 : 0.0,
                hover: block.nodeID == hoveredNodeID ? 1.0 : 0.0,
                textureIndex: block.textureIndex,
                shapeID: block.shapeID
            )
        }
        instanceCount = instances.count
        if instances.isEmpty {
            instanceBuffer = nil
            return
        }
        if blocksChanged {
            camera.target = centerOf(blocks: blocks)
            rebuildRoadsAndCars(blocks: blocks)
        }
        instanceBuffer = device.makeBuffer(bytes: instances, length: MemoryLayout<VoxelInstance>.stride * instances.count, options: [])
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

        var uniforms = Uniforms(viewProjection: camera.projectionMatrix() * camera.viewMatrix())
        encoder?.setVertexBytes(&uniforms, length: MemoryLayout<Uniforms>.stride, index: 2)
        
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
                position: SIMD3<Float>(centerX, 0.5, roadZ),
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
                position: SIMD3<Float>(roadX, 0.5, centerZ),
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
                let start = SIMD3<Float>(forward ? minX - 2.0 : maxX + 2.0, 0.6, roadZ + laneOffset)
                let end = SIMD3<Float>(forward ? maxX + 2.0 : minX - 2.0, 0.6, roadZ + laneOffset)
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
                let start = SIMD3<Float>(roadX - laneOffset, 0.6, forward ? minZ - 2.0 : maxZ + 2.0)
                let end = SIMD3<Float>(roadX - laneOffset, 0.6, forward ? maxZ + 2.0 : minZ - 2.0)
                let scale = SIMD3<Float>(1.6, 1.2, 3.2)
                carPaths.append(CarPath(start: start, end: end, speed: speed, phase: phase, scale: scale))
            }
        }

        carInstanceCount = carPaths.count
        if carInstanceCount > 0 {
            carInstanceBuffer = device.makeBuffer(length: MemoryLayout<VoxelInstance>.stride * carInstanceCount, options: [])
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

    func pickBlock(at point: CGPoint, in size: CGSize) -> CityBlock? {
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
        
        // Delegate to RayTracer
        let ray = RayTracer.Ray(origin: rayOrigin, direction: rayDirection)
        let tracer = RayTracer()
        if let hit = tracer.intersect(ray: ray, blocks: blocks) {
            // Find block by ID (this could be optimized if hit returned the block directly, 
            // but we need to match the signature or keep RayTracer generic)
            return blocks.first { $0.nodeID == hit.blockID }
        }
        
        return nil
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
}
