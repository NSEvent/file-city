import Combine
import MetalKit
import SwiftUI

struct MetalCityView: NSViewRepresentable {
    @EnvironmentObject var appState: AppState

    func makeCoordinator() -> Coordinator {
        Coordinator(appState: appState)
    }

    func makeNSView(context: Context) -> MTKView {
        let view = CityMTKView()
        // Subscribe to appState changes via Coordinator
        context.coordinator.startObserving(appState: appState)
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
        view.onKey = { key in
            context.coordinator.handleKey(key)
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
        // Apply auto-fit BEFORE updating instances so first render has correct camera
        context.coordinator.applyPendingAutoFit(blocks: appState.blocks)
        let activityNow = appState.activityNow()
        context.coordinator.renderer?.updateInstances(
            blocks: appState.blocks,
            selectedNodeID: appState.selectedFocusNodeID,
            hoveredNodeID: appState.hoveredNodeID,
            hoveredBeaconNodeID: appState.hoveredBeaconNodeID,
            activityByNodeID: appState.activitySnapshot(now: activityNow),
            activityNow: activityNow,
            activityDuration: appState.activityDuration
        )
    }

    final class Coordinator: NSObject {
        var renderer: MetalRenderer?
        weak var appState: AppState?
        private var hoveredNodeID: UUID?
        private(set) var hoveredBeaconNodeID: UUID?
        private var cancellables = Set<AnyCancellable>()

        init(appState: AppState) {
            self.appState = appState
        }

        func startObserving(appState: AppState) {
            self.appState = appState
            // Subscribe to blocks changes and trigger updates
            appState.$blocks
                .receive(on: DispatchQueue.main)
                .sink { [weak self] blocks in
                    self?.updateFromAppState()
                }
                .store(in: &cancellables)

            // Also observe other relevant properties
            appState.$pendingAutoFit
                .receive(on: DispatchQueue.main)
                .sink { [weak self] _ in
                    self?.updateFromAppState()
                }
                .store(in: &cancellables)
        }

        private func updateFromAppState() {
            guard let appState, let renderer else { return }

            // Apply auto-fit first
            if appState.pendingAutoFit && !appState.blocks.isEmpty {
                renderer.autoFitCamera(blocks: appState.blocks)
                appState.clearPendingAutoFit()
            }

            // Update instances
            let activityNow = appState.activityNow()
            renderer.updateInstances(
                blocks: appState.blocks,
                selectedNodeID: appState.selectedFocusNodeID,
                hoveredNodeID: appState.hoveredNodeID,
                hoveredBeaconNodeID: appState.hoveredBeaconNodeID,
                activityByNodeID: appState.activitySnapshot(now: activityNow),
                activityNow: activityNow,
                activityDuration: appState.activityDuration
            )
        }

        func applyPendingAutoFit(blocks: [CityBlock]) {
            guard let appState, appState.pendingAutoFit, !blocks.isEmpty else { return }
            renderer?.autoFitCamera(blocks: blocks)
            appState.clearPendingAutoFit()
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
            if let planeIndex = renderer.pickPlane(at: backingPoint, in: view.drawableSize) {
                renderer.setHoveredPlane(index: planeIndex)
                if hoveredNodeID != nil {
                    hoveredNodeID = nil
                    appState?.hoveredURL = nil
                    appState?.hoveredNodeID = nil
                }
                if hoveredBeaconNodeID != nil {
                    hoveredBeaconNodeID = nil
                    appState?.hoveredGitStatus = nil
                    appState?.hoveredBeaconNodeID = nil
                    appState?.hoveredBeaconURL = nil
                }
                return
            }
            let beaconHit = renderer.pickBeaconHit(at: backingPoint, in: view.drawableSize)
            let blockHit = renderer.pickBlockHit(at: backingPoint, in: view.drawableSize)
            if let beaconHit, let blockHit, blockHit.distance <= beaconHit.distance {
                if hoveredBeaconNodeID != nil {
                    hoveredBeaconNodeID = nil
                    appState?.hoveredGitStatus = nil
                    appState?.hoveredBeaconNodeID = nil
                }
            } else if let beaconHit {
                if hoveredBeaconNodeID != beaconHit.nodeID {
                    hoveredBeaconNodeID = beaconHit.nodeID
                    hoveredNodeID = nil
                    appState?.hoveredURL = nil
                    appState?.hoveredNodeID = nil
                    appState?.hoveredBeaconNodeID = beaconHit.nodeID
                    if let url = appState?.url(for: beaconHit.nodeID) {
                        appState?.hoveredBeaconURL = url
                        appState?.hoveredGitStatus = appState?.gitStatusLines(for: url)
                    } else {
                        appState?.hoveredGitStatus = nil
                        appState?.hoveredBeaconURL = nil
                    }
                }
                renderer.setHoveredPlane(index: nil)
                return
            }
            if hoveredBeaconNodeID != nil {
                hoveredBeaconNodeID = nil
                appState?.hoveredGitStatus = nil
                appState?.hoveredBeaconNodeID = nil
                appState?.hoveredBeaconURL = nil
            }
            guard let block = blockHit?.block else {
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
            appState?.hoveredBeaconNodeID = nil
            appState?.hoveredBeaconURL = nil
        }

        func clearHover() {
            renderer?.setHoveredPlane(index: nil)
            hoveredNodeID = nil
            hoveredBeaconNodeID = nil
            appState?.hoveredURL = nil
            appState?.hoveredNodeID = nil
            appState?.hoveredGitStatus = nil
            appState?.hoveredBeaconNodeID = nil
            appState?.hoveredBeaconURL = nil
        }

        func handleKey(_ key: String) {
            switch key {
            case "1":
                appState?.triggerTestActivity(kind: .read)
            case "2":
                appState?.triggerTestActivity(kind: .write)
            default:
                break
            }
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
    var onKey: ((String) -> Void)?
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
        window?.makeFirstResponder(self)
    }

    override var acceptsFirstResponder: Bool {
        true
    }

    override func keyDown(with event: NSEvent) {
        if let key = event.charactersIgnoringModifiers, !key.isEmpty {
            onKey?(key)
        } else {
            super.keyDown(with: event)
        }
    }
}
