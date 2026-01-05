import MetalKit
import SwiftUI

struct MetalCityView: NSViewRepresentable {
    @EnvironmentObject var appState: AppState

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    func makeNSView(context: Context) -> MTKView {
        let view = CityMTKView()
        view.preferredFramesPerSecond = 60
        view.clearColor = MTLClearColor(red: 0.08, green: 0.1, blue: 0.12, alpha: 1.0)
        view.colorPixelFormat = .bgra8Unorm
        view.depthStencilPixelFormat = .depth32Float
        view.isPaused = false
        view.enableSetNeedsDisplay = false
        context.coordinator.renderer = MetalRenderer(view: view)
        view.delegate = context.coordinator.renderer
        context.coordinator.attachGestures(to: view)
        view.onScroll = { deltaX, deltaY in
            context.coordinator.renderer?.camera.pan(deltaX: Float(-deltaX), deltaY: Float(-deltaY))
        }
        return view
    }

    func updateNSView(_ nsView: MTKView, context: Context) {
        context.coordinator.renderer?.updateInstances(blocks: appState.blocks, selectedNodeID: appState.selectedFocusNodeID)
    }

    final class Coordinator: NSObject {
        var renderer: MetalRenderer?

        func attachGestures(to view: MTKView) {
            let magnify = NSMagnificationGestureRecognizer(target: self, action: #selector(handleMagnify(_:)))
            view.addGestureRecognizer(magnify)
        }

        @objc private func handleMagnify(_ gesture: NSMagnificationGestureRecognizer) {
            renderer?.camera.zoom(delta: Float(gesture.magnification))
        }
    }
}

final class CityMTKView: MTKView {
    var onScroll: ((CGFloat, CGFloat) -> Void)?

    override func scrollWheel(with event: NSEvent) {
        onScroll?(event.scrollingDeltaX, event.scrollingDeltaY)
    }
}
