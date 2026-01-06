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
        let textureCount = 32
        
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
        encoder?.setVertexBuffer(instanceBuffer, offset: 0, index: 1)

        var uniforms = Uniforms(viewProjection: camera.projectionMatrix() * camera.viewMatrix())
        encoder?.setVertexBytes(&uniforms, length: MemoryLayout<Uniforms>.stride, index: 2)
        
        if let textureArray = textureArray {
            encoder?.setFragmentTexture(textureArray, index: 0)
        }
        encoder?.setFragmentSamplerState(samplerState, index: 0)

        if instanceCount > 0 {
            encoder?.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 36, instanceCount: instanceCount)
        }
        encoder?.endEncoding()
        commandBuffer.present(drawable)
        commandBuffer.commit()
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
