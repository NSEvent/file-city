import Metal
import MetalKit

final class MetalRenderer: NSObject, MTKViewDelegate {
    private let device: MTLDevice
    private let commandQueue: MTLCommandQueue

    init?(view: MTKView) {
        guard let device = MTLCreateSystemDefaultDevice(),
              let commandQueue = device.makeCommandQueue() else {
            return nil
        }
        self.device = device
        self.commandQueue = commandQueue
        super.init()
        view.device = device
        view.delegate = self
    }

    func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize) {
    }

    func draw(in view: MTKView) {
        guard let drawable = view.currentDrawable,
              let renderPassDescriptor = view.currentRenderPassDescriptor,
              let commandBuffer = commandQueue.makeCommandBuffer() else {
            return
        }
        let encoder = commandBuffer.makeRenderCommandEncoder(descriptor: renderPassDescriptor)
        encoder?.endEncoding()
        commandBuffer.present(drawable)
        commandBuffer.commit()
    }
}
