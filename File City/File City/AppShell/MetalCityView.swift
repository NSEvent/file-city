import MetalKit
import SwiftUI

struct MetalCityView: NSViewRepresentable {
    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    func makeNSView(context: Context) -> MTKView {
        let view = MTKView()
        view.preferredFramesPerSecond = 60
        view.clearColor = MTLClearColor(red: 0.08, green: 0.1, blue: 0.12, alpha: 1.0)
        view.colorPixelFormat = .bgra8Unorm
        context.coordinator.renderer = MetalRenderer(view: view)
        return view
    }

    func updateNSView(_ nsView: MTKView, context: Context) {
    }

    final class Coordinator {
        var renderer: MetalRenderer?
    }
}
