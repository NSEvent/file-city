import Metal
import MetalKit
import simd

final class MetalRenderer: NSObject, MTKViewDelegate {
    private let device: MTLDevice
    private let commandQueue: MTLCommandQueue
    private let pipelineState: MTLRenderPipelineState
    private let depthState: MTLDepthStencilState
    private let cubeVertexBuffer: MTLBuffer
    private var instanceBuffer: MTLBuffer?
    private var instanceCount: Int = 0
    private var blocks: [CityBlock] = []
    let camera = Camera()

    struct Vertex {
        let position: SIMD3<Float>
        let normal: SIMD3<Float>
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

        let cubeVertices = MetalRenderer.buildCubeVertices()
        guard let cubeVertexBuffer = device.makeBuffer(bytes: cubeVertices, length: MemoryLayout<Vertex>.stride * cubeVertices.count, options: []) else {
            return nil
        }
        self.cubeVertexBuffer = cubeVertexBuffer

        super.init()
        view.device = device
        view.delegate = self
    }

    func updateInstances(blocks: [CityBlock], selectedNodeID: UUID?, hoveredNodeID: UUID?) {
        self.blocks = blocks
        let instances = blocks.map { block in
            VoxelInstance(
                position: SIMD3<Float>(block.position.x, block.position.y, block.position.z),
                scale: SIMD3<Float>(Float(block.footprint.x), Float(block.height), Float(block.footprint.y)),
                materialID: UInt32(block.materialID),
                highlight: block.nodeID == selectedNodeID ? 1.0 : 0.0,
                hover: block.nodeID == hoveredNodeID ? 1.0 : 0.0,
                _pad2: 0
            )
        }
        instanceCount = instances.count
        if instances.isEmpty {
            instanceBuffer = nil
            return
        }
        camera.target = centerOf(blocks: blocks)
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
        let threshold: Float = 30
        var bestBlock: CityBlock?
        var bestDistance = threshold * threshold
        var bestDepth: Float = .greatestFiniteMagnitude

        for block in blocks {
            let center = SIMD3<Float>(
                block.position.x + Float(block.footprint.x) * 0.5,
                Float(block.height) * 0.5,
                block.position.z + Float(block.footprint.y) * 0.5
            )
            let worldPosition = SIMD4<Float>(center.x, center.y, center.z, 1)
            let clip = projectionMatrix * viewMatrix * worldPosition
            if clip.w <= 0 { continue }
            let ndc = SIMD3<Float>(clip.x / clip.w, clip.y / clip.w, clip.z / clip.w)
            if ndc.x < -1 || ndc.x > 1 || ndc.y < -1 || ndc.y > 1 { continue }
            let screenX = (ndc.x * 0.5 + 0.5) * Float(size.width)
            let screenY = (1 - (ndc.y * 0.5 + 0.5)) * Float(size.height)
            let dx = Float(point.x) - screenX
            let dy = Float(point.y) - screenY
            let distance = dx * dx + dy * dy
            if distance < bestDistance || (distance == bestDistance && ndc.z < bestDepth) {
                bestDistance = distance
                bestDepth = ndc.z
                bestBlock = block
            }
        }

        return bestBlock
    }

    private static func vertexDescriptor() -> MTLVertexDescriptor {
        let descriptor = MTLVertexDescriptor()
        descriptor.attributes[0].format = .float3
        descriptor.attributes[0].offset = 0
        descriptor.attributes[0].bufferIndex = 0
        descriptor.attributes[1].format = .float3
        descriptor.attributes[1].offset = MemoryLayout<SIMD3<Float>>.stride
        descriptor.attributes[1].bufferIndex = 0
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
                Vertex(position: a, normal: n),
                Vertex(position: b, normal: n),
                Vertex(position: c, normal: n),
                Vertex(position: a, normal: n),
                Vertex(position: c, normal: n),
                Vertex(position: d, normal: n),
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
