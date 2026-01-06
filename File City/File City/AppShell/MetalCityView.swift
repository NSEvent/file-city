import MetalKit
import SwiftUI

struct MetalCityView: NSViewRepresentable {
    @EnvironmentObject var appState: AppState

    func makeCoordinator() -> Coordinator {
        Coordinator(appState: appState)
    }

    func makeNSView(context: Context) -> MTKView {
        let view = CityMTKView()
        view.preferredFramesPerSecond = 60
        view.clearColor = MTLClearColor(red: 0.68, green: 0.78, blue: 0.86, alpha: 1.0)
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
        view.onHover = { point in
            context.coordinator.handleHover(point, in: view)
        }
        view.onHoverEnd = {
            context.coordinator.clearHover()
        }
        view.onClick = { point in
            context.coordinator.handleClick(point, in: view)
        }
        view.onRightClick = { point in
            context.coordinator.handleRightClick(point, in: view)
        }
        return view
    }

    func updateNSView(_ nsView: MTKView, context: Context) {
        context.coordinator.appState = appState
        context.coordinator.renderer?.updateInstances(
            blocks: appState.blocks,
            selectedNodeID: appState.selectedFocusNodeID,
            hoveredNodeID: appState.hoveredNodeID
        )
    }

    final class Coordinator: NSObject {
        var renderer: MetalRenderer?
        weak var appState: AppState?
        private var hoveredNodeID: UUID?
        private var hoveredBeaconNodeID: UUID?

        init(appState: AppState) {
            self.appState = appState
        }

        func attachGestures(to view: MTKView) {
            let magnify = NSMagnificationGestureRecognizer(target: self, action: #selector(handleMagnify(_:)))
            view.addGestureRecognizer(magnify)
        }

        @objc private func handleMagnify(_ gesture: NSMagnificationGestureRecognizer) {
            renderer?.camera.zoom(delta: Float(gesture.magnification))
        }

        func handleHover(_ point: CGPoint, in view: MTKView) {
            guard let renderer else { return }
            let backingPoint = view.convertToBacking(point)
            if let beaconNodeID = renderer.pickBeacon(at: backingPoint, in: view.drawableSize) {
                if hoveredBeaconNodeID != beaconNodeID {
                    hoveredBeaconNodeID = beaconNodeID
                    hoveredNodeID = nil
                    appState?.hoveredURL = nil
                    appState?.hoveredNodeID = nil
                    if let url = appState?.url(for: beaconNodeID) {
                        appState?.hoveredGitStatus = appState?.gitStatusLines(for: url)
                    } else {
                        appState?.hoveredGitStatus = nil
                    }
                }
                renderer.setHoveredPlane(index: nil)
                return
            }
            if hoveredBeaconNodeID != nil {
                hoveredBeaconNodeID = nil
                appState?.hoveredGitStatus = nil
            }
            if let planeIndex = renderer.pickPlane(at: backingPoint, in: view.drawableSize) {
                renderer.setHoveredPlane(index: planeIndex)
                if hoveredNodeID != nil {
                    hoveredNodeID = nil
                    appState?.hoveredURL = nil
                    appState?.hoveredNodeID = nil
                }
                return
            }
            guard let block = renderer.pickBlock(at: backingPoint, in: view.drawableSize) else {
                renderer.setHoveredPlane(index: nil)
                if hoveredNodeID != nil {
                    hoveredNodeID = nil
                    appState?.hoveredURL = nil
                    appState?.hoveredNodeID = nil
                }
                return
            }
            renderer.setHoveredPlane(index: nil)
            guard hoveredNodeID != block.nodeID else { return }
            hoveredNodeID = block.nodeID
            hoveredBeaconNodeID = nil
            appState?.hoveredGitStatus = nil
            appState?.hoveredURL = appState?.url(for: block.nodeID)
            appState?.hoveredNodeID = block.nodeID
        }

        func clearHover() {
            renderer?.setHoveredPlane(index: nil)
            hoveredNodeID = nil
            hoveredBeaconNodeID = nil
            appState?.hoveredURL = nil
            appState?.hoveredNodeID = nil
            appState?.hoveredGitStatus = nil
        }

        func handleClick(_ point: CGPoint, in view: MTKView) {
            guard let renderer else { return }
            let backingPoint = view.convertToBacking(point)
            guard let block = renderer.pickBlock(at: backingPoint, in: view.drawableSize) else { return }
            guard let url = appState?.url(for: block.nodeID) else { return }
            appState?.enter(url)
        }
        
        func handleRightClick(_ point: CGPoint, in view: MTKView) {
            guard let renderer else { return }
            let backingPoint = view.convertToBacking(point)
            guard let block = renderer.pickBlock(at: backingPoint, in: view.drawableSize) else { return }
            guard let url = appState?.url(for: block.nodeID) else { return }
            appState?.reveal(url)
        }
    }
}

final class CityMTKView: MTKView {
    var onScroll: ((CGFloat, CGFloat) -> Void)?
    var onHover: ((CGPoint) -> Void)?
    var onHoverEnd: (() -> Void)?
    var onClick: ((CGPoint) -> Void)?
    var onRightClick: ((CGPoint) -> Void)?
    private var trackingArea: NSTrackingArea?

    override func scrollWheel(with event: NSEvent) {
        onScroll?(event.scrollingDeltaX, event.scrollingDeltaY)
    }

    override func updateTrackingAreas() {
        if let trackingArea {
            removeTrackingArea(trackingArea)
        }
        let options: NSTrackingArea.Options = [.activeInKeyWindow, .inVisibleRect, .mouseMoved, .mouseEnteredAndExited]
        let trackingArea = NSTrackingArea(rect: bounds, options: options, owner: self, userInfo: nil)
        addTrackingArea(trackingArea)
        self.trackingArea = trackingArea
        super.updateTrackingAreas()
    }

    override func mouseMoved(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        onHover?(point)
    }

    override func mouseExited(with event: NSEvent) {
        onHoverEnd?()
    }

    override func mouseDown(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        onClick?(point)
    }
    
    override func rightMouseDown(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        onRightClick?(point)
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        window?.acceptsMouseMovedEvents = true
    }
}
