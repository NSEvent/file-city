import MetalKit
import SwiftUI

struct MetalCityView: NSViewRepresentable {
    @EnvironmentObject var appState: AppState

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    func makeNSView(context: Context) -> MTKView {
        let view = MTKView()
        view.preferredFramesPerSecond = 60
        view.clearColor = MTLClearColor(red: 0.08, green: 0.1, blue: 0.12, alpha: 1.0)
        view.colorPixelFormat = .bgra8Unorm
        view.depthStencilPixelFormat = .depth32Float
        view.isPaused = false
        view.enableSetNeedsDisplay = false
        context.coordinator.renderer = MetalRenderer(view: view)
        view.delegate = context.coordinator.renderer
        context.coordinator.attachGestures(to: view)
        return view
    }

    func updateNSView(_ nsView: MTKView, context: Context) {
        context.coordinator.renderer?.updateInstances(blocks: appState.blocks)
    }

    final class Coordinator: NSObject {
        var renderer: MetalRenderer?
        private var lastPanPoint: CGPoint = .zero

        func attachGestures(to view: MTKView) {
            let pan = NSPanGestureRecognizer(target: self, action: #selector(handlePan(_:)))
            let magnify = NSMagnificationGestureRecognizer(target: self, action: #selector(handleMagnify(_:)))
            view.addGestureRecognizer(pan)
            view.addGestureRecognizer(magnify)
        }

        @objc private func handlePan(_ gesture: NSPanGestureRecognizer) {
            guard let view = gesture.view else { return }
            let point = gesture.translation(in: view)
            if gesture.state == .began {
                lastPanPoint = point
                return
            }
            let delta = CGPoint(x: point.x - lastPanPoint.x, y: point.y - lastPanPoint.y)
            renderer?.camera.pan(deltaX: Float(delta.x), deltaY: Float(-delta.y))
            lastPanPoint = point
        }

        @objc private func handleMagnify(_ gesture: NSMagnificationGestureRecognizer) {
            renderer?.camera.zoom(delta: Float(gesture.magnification))
        }
    }
}
