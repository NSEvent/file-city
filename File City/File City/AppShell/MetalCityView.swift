import Combine
import MetalKit
import SwiftUI
import CoreGraphics

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
        context.coordinator.subscribeToPackageLanding()
        context.coordinator.attachGestures(to: view)
        context.coordinator.cityView = view
        view.coordinator = context.coordinator
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
        view.onDoubleClick = { point in
            context.coordinator.handleDoubleClick(point, in: view)
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

        // Update Banner Text
        if let rootURL = appState.rootURL {
            context.coordinator.renderer?.setBannerText(rootURL.lastPathComponent)
        }

        let activityNow = appState.activityNow()
        context.coordinator.renderer?.updateInstances(
            blocks: appState.blocks,
            selectedNodeIDs: appState.selectedFocusNodeIDs,
            hoveredNodeID: appState.hoveredNodeID,
            hoveredBeaconNodeID: appState.hoveredBeaconNodeID,
            activityByNodeID: appState.activitySnapshot(now: activityNow),
            activityNow: activityNow,
            activityDuration: appState.activityDuration,
            locByNodeID: appState.locByNodeID
        )
    }

    final class Coordinator: NSObject {
        var renderer: MetalRenderer?
        weak var appState: AppState?
        weak var cityView: CityMTKView?
        private var hoveredNodeID: UUID?
        private(set) var hoveredBeaconNodeID: UUID?
        private var hoveredSatelliteSessionID: UUID?
        private var cancellables = Set<AnyCancellable>()
        private var activityTimer: Timer?
        private var activityEndTime: CFTimeInterval = 0

        // First-person mode state
        var pressedKeys: Set<UInt16> = []
        var isMouseCaptured: Bool = false
        private var movementTimer: Timer?
        private var lastMovementTime: CFTimeInterval = CACurrentMediaTime()
        private var lastSpacePressTime: CFTimeInterval = 0
        private var lastWPressTime: CFTimeInterval = 0
        private var lastSPressTime: CFTimeInterval = 0
        private var lastAPressTime: CFTimeInterval = 0
        private var lastDPressTime: CFTimeInterval = 0
        private let doubleTapInterval: CFTimeInterval = 0.3  // 300ms for double-tap
        private var hitTestFrameCounter: Int = 0
        private let hitTestInterval: Int = 4  // Run hit test every N frames

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

            // Observe activity changes to start animation timer
            appState.$activityVersion
                .receive(on: DispatchQueue.main)
                .sink { [weak self] _ in
                    self?.handleActivityChange()
                }
                .store(in: &cancellables)

            appState.fileWriteSubject
                .receive(on: DispatchQueue.main)
                .sink { [weak self] nodeID in
                    self?.handleFileWrite(nodeID: nodeID)
                }
                .store(in: &cancellables)

            appState.fileReadSubject
                .receive(on: DispatchQueue.main)
                .sink { [weak self] nodeID in
                    self?.handleFileRead(nodeID: nodeID)
                }
                .store(in: &cancellables)

            // Clear helicopters on directory switch
            appState.$rootURL
                .dropFirst()
                .receive(on: DispatchQueue.main)
                .sink { [weak self] _ in
                    self?.renderer?.clearHelicopters()
                }
                .store(in: &cancellables)

            // Observe LOC changes to update flags
            appState.$locByPath
                .receive(on: DispatchQueue.main)
                .sink { [weak self] _ in
                    self?.updateFromAppState()
                }
                .store(in: &cancellables)

            // Subscribe to Claude session changes
            appState.$claudeSessions
                .receive(on: DispatchQueue.main)
                .sink { [weak self] sessions in
                    self?.syncSatellites(with: sessions)
                }
                .store(in: &cancellables)

            appState.claudeSessionStateChanged
                .receive(on: DispatchQueue.main)
                .sink { [weak self] sessionID in
                    NSLog("[MetalCityView] Received claudeSessionStateChanged: %@", sessionID.uuidString)
                    guard let appState = self?.appState,
                          let session = appState.claudeSessions.first(where: { $0.id == sessionID }) else {
                        NSLog("[MetalCityView] Could not find session")
                        return
                    }
                    NSLog("[MetalCityView] Calling updateSatelliteState with state %d", session.state.rawValue)
                    self?.renderer?.updateSatelliteState(sessionID: sessionID, state: session.state)
                }
                .store(in: &cancellables)

            appState.claudeSessionExited
                .receive(on: DispatchQueue.main)
                .sink { [weak self] sessionID in
                    self?.renderer?.removeSatellite(sessionID: sessionID)
                }
                .store(in: &cancellables)

            // Subscribe to selected Claude session changes
            appState.$selectedClaudeSession
                .receive(on: DispatchQueue.main)
                .sink { [weak self] session in
                    // Clear all selections first
                    if let appState = self?.appState {
                        for claudeSession in appState.claudeSessions {
                            self?.renderer?.updateSatelliteSelection(sessionID: claudeSession.id, selected: false)
                        }
                    }
                    // Set new selection
                    if let session = session {
                        self?.renderer?.updateSatelliteSelection(sessionID: session.id, selected: true)
                    }
                }
                .store(in: &cancellables)
        }

        private var syncedSessionIDs: Set<UUID> = []

        private func syncSatellites(with sessions: [ClaudeSession]) {
            guard let renderer else { return }
            // Spawn satellites for new sessions
            for session in sessions {
                if !syncedSessionIDs.contains(session.id) {
                    renderer.spawnSatellite(sessionID: session.id)
                    syncedSessionIDs.insert(session.id)
                }
            }
            // Remove satellites for sessions that no longer exist
            let currentIDs = Set(sessions.map { $0.id })
            for sessionID in syncedSessionIDs {
                if !currentIDs.contains(sessionID) {
                    renderer.removeSatellite(sessionID: sessionID)
                }
            }
            syncedSessionIDs = currentIDs
        }

        private func handleFileWrite(nodeID: UUID) {
            guard let appState, let renderer else { return }
            if let block = appState.blocks.first(where: { $0.nodeID == nodeID }) {
                renderer.spawnHelicopter(at: block)

                // Check if this write was initiated by a Claude session
                if let activity = appState.activityForNodeID(nodeID), let sessionID = activity.initiatingSessionID {
                    renderer.spawnElectricityBeam(from: sessionID, to: block)
                }
            }
        }

        private func handleFileRead(nodeID: UUID) {
            guard let appState, let renderer else { return }
            if let block = appState.blocks.first(where: { $0.nodeID == nodeID }) {
                renderer.spawnBeam(at: block)

                // Check if this read was initiated by a Claude session
                if let activity = appState.activityForNodeID(nodeID), let sessionID = activity.initiatingSessionID {
                    renderer.spawnElectricityBeam(from: sessionID, to: block)
                }
            }
        }

        func subscribeToPackageLanding() {
            guard let renderer else { return }
            renderer.packageLandedPublisher
                .receive(on: DispatchQueue.main)
                .sink { [weak self] nodeID in
                    self?.appState?.countLOCForNode(nodeID)
                }
                .store(in: &cancellables)
        }

        private func handleActivityChange() {
            guard let appState else { return }
            // Extend the timer end time
            activityEndTime = appState.activityNow() + appState.activityDuration + 0.1
            // Start timer if not already running
            if activityTimer == nil {
                activityTimer = Timer.scheduledTimer(withTimeInterval: 1.0 / 30.0, repeats: true) { [weak self] _ in
                    self?.activityTimerFired()
                }
            }
            updateFromAppState()
        }

        private func activityTimerFired() {
            guard let appState else {
                stopActivityTimer()
                return
            }
            let now = appState.activityNow()
            if now >= activityEndTime {
                stopActivityTimer()
            }
            updateFromAppState()
        }

        private func stopActivityTimer() {
            activityTimer?.invalidate()
            activityTimer = nil
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
                selectedNodeIDs: appState.selectedFocusNodeIDs,
                hoveredNodeID: appState.hoveredNodeID,
                hoveredBeaconNodeID: appState.hoveredBeaconNodeID,
                activityByNodeID: appState.activitySnapshot(now: activityNow),
                activityNow: activityNow,
                activityDuration: appState.activityDuration,
                locByNodeID: appState.locByNodeID
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

            // Skip hover handling in first-person mode with mouse captured
            if renderer.camera.isFirstPerson && isMouseCaptured { return }

            let backingPoint = view.convertToBacking(point)

            // Check for satellite hover first
            if let sessionID = renderer.pickSatellite(at: backingPoint, in: view.drawableSize) {
                NSLog("[MetalCityView] Satellite hover detected: %@", sessionID.uuidString)
                if hoveredSatelliteSessionID != sessionID {
                    hoveredSatelliteSessionID = sessionID
                    appState?.setHoveredClaudeSession(sessionID)
                    // Clear other hover states
                    hoveredNodeID = nil
                    hoveredBeaconNodeID = nil
                    appState?.hoveredURL = nil
                    appState?.hoveredNodeID = nil
                    appState?.hoveredGitStatus = nil
                    appState?.hoveredBeaconNodeID = nil
                    appState?.hoveredBeaconURL = nil
                    renderer.setHoveredPlane(index: nil)
                }
                return
            } else if hoveredSatelliteSessionID != nil {
                hoveredSatelliteSessionID = nil
                appState?.setHoveredClaudeSession(nil)
            }

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
            hoveredSatelliteSessionID = nil
            appState?.hoveredURL = nil
            appState?.hoveredNodeID = nil
            appState?.hoveredGitStatus = nil
            appState?.hoveredBeaconNodeID = nil
            appState?.hoveredBeaconURL = nil
            appState?.setHoveredClaudeSession(nil)
        }

        func handleKey(_ key: String) {
            switch key {
            case "1":
                let targetID = hoveredNodeID ?? hoveredBeaconNodeID
                if let targetID,
                   let block = appState?.blocks.first(where: { $0.nodeID == targetID }) {
                    renderer?.spawnHelicopter(at: block)
                } else {
                    appState?.triggerTestActivity(kind: .read)
                }
            case "2":
                let targetID = hoveredNodeID ?? hoveredBeaconNodeID
                if let targetID,
                   let block = appState?.blocks.first(where: { $0.nodeID == targetID }) {
                    renderer?.spawnBeam(at: block)
                } else {
                    appState?.triggerTestActivity(kind: .write)
                }
            default:
                break
            }
        }

        func handleClick(_ point: CGPoint, in view: MTKView) {
            guard let renderer else { return }

            // In first-person mode, click captures mouse
            if renderer.camera.isFirstPerson && !isMouseCaptured {
                captureMouse()
                return
            }

            let backingPoint = view.convertToBacking(point)

            // Check for satellite click first
            if let sessionID = renderer.pickSatellite(at: backingPoint, in: view.drawableSize) {
                NSLog("[MetalCityView] Satellite click detected: %@", sessionID.uuidString)
                appState?.selectClaudeSession(sessionID)
                return
            }

            // Check for plane click
            if let planeIndex = renderer.pickPlane(at: backingPoint, in: view.drawableSize) {
                renderer.explodePlane(index: planeIndex)
                return
            }

            // If clicked on a building, select it; otherwise clear selection
            if let block = renderer.pickBlock(at: backingPoint, in: view.drawableSize),
               let url = appState?.url(for: block.nodeID) {
                appState?.select(url)
            } else {
                appState?.clearSelection()
            }
        }

        func handleDoubleClick(_ point: CGPoint, in view: MTKView) {
            guard let renderer else { return }
            let backingPoint = view.convertToBacking(point)
            guard let block = renderer.pickBlock(at: backingPoint, in: view.drawableSize) else { return }
            guard let url = appState?.url(for: block.nodeID) else { return }
            appState?.activateItem(url)
        }

        func handleRightClick(_ point: CGPoint, in view: MTKView) {
            guard let renderer else { return }
            let backingPoint = view.convertToBacking(point)

            // Check for satellite right-click
            if let sessionID = renderer.pickSatellite(at: backingPoint, in: view.drawableSize) {
                showSatelliteContextMenu(sessionID: sessionID, at: point, in: view)
                return
            }

            // Check for block right-click
            if let block = renderer.pickBlock(at: backingPoint, in: view.drawableSize),
               let url = appState?.url(for: block.nodeID) {
                var isDir: ObjCBool = false
                let exists = FileManager.default.fileExists(atPath: url.path, isDirectory: &isDir)

                if exists && isDir.boolValue {
                    showDirectoryContextMenu(url: url, at: point, in: view)
                } else {
                    appState?.reveal(url)
                }
                return
            }

            // Right-click on ground - show context menu for current root directory
            if let rootURL = appState?.rootURL {
                showDirectoryContextMenu(url: rootURL, at: point, in: view)
            }
        }

        private func showDirectoryContextMenu(url: URL, at point: CGPoint, in view: MTKView) {
            let menu = NSMenu()

            // Reveal in Finder
            let revealItem = NSMenuItem(title: "Reveal in Finder", action: #selector(revealInFinder(_:)), keyEquivalent: "")
            revealItem.representedObject = url
            revealItem.target = self
            menu.addItem(revealItem)

            menu.addItem(NSMenuItem.separator())

            // Launch Claude here
            let claudeItem = NSMenuItem(title: "Launch Claude here", action: #selector(launchClaudeHere(_:)), keyEquivalent: "")
            claudeItem.representedObject = url
            claudeItem.target = self
            menu.addItem(claudeItem)

            // Show the menu at click location (point is already in view coordinates)
            menu.popUp(positioning: nil, at: point, in: view)
        }

        private func showSatelliteContextMenu(sessionID: UUID, at point: CGPoint, in view: MTKView) {
            let menu = NSMenu()

            // Focus terminal
            let focusItem = NSMenuItem(title: "Focus Terminal", action: #selector(focusSatelliteTerminal(_:)), keyEquivalent: "")
            focusItem.representedObject = sessionID
            focusItem.target = self
            menu.addItem(focusItem)

            menu.addItem(NSMenuItem.separator())

            // Terminate session
            let terminateItem = NSMenuItem(title: "Terminate Session", action: #selector(terminateSatelliteSession(_:)), keyEquivalent: "")
            terminateItem.representedObject = sessionID
            terminateItem.target = self
            menu.addItem(terminateItem)

            // Show the menu at click location (point is already in view coordinates)
            menu.popUp(positioning: nil, at: point, in: view)
        }

        @objc private func revealInFinder(_ sender: NSMenuItem) {
            guard let url = sender.representedObject as? URL else { return }
            appState?.reveal(url)
        }

        @objc private func launchClaudeHere(_ sender: NSMenuItem) {
            guard let url = sender.representedObject as? URL else { return }
            appState?.launchClaude(at: url)
        }

        @objc private func focusSatelliteTerminal(_ sender: NSMenuItem) {
            guard let sessionID = sender.representedObject as? UUID else { return }
            appState?.focusClaudeSession(sessionID)
        }

        @objc private func terminateSatelliteSession(_ sender: NSMenuItem) {
            guard let sessionID = sender.representedObject as? UUID else { return }
            appState?.terminateClaudeSession(sessionID)
        }

        // MARK: - First-Person Mode Controls

        func toggleFirstPersonMode() {
            guard let renderer else { return }
            renderer.camera.toggleFirstPerson()

            if renderer.camera.isFirstPerson {
                // Enter first-person: position at edge of city
                if let blocks = appState?.blocks {
                    renderer.camera.enterCityCenter(blocks: blocks)
                }
                startMovementTimer()
                appState?.isFirstPerson = true
            } else {
                // Exit first-person: release mouse and stop timer
                releaseMouse()
                stopMovementTimer()
                appState?.isFirstPerson = false
            }
        }

        func captureMouse() {
            guard !isMouseCaptured else { return }
            isMouseCaptured = true
            CGDisplayHideCursor(CGMainDisplayID())
            CGAssociateMouseAndMouseCursorPosition(0)
        }

        func releaseMouse() {
            guard isMouseCaptured else { return }
            isMouseCaptured = false
            CGDisplayShowCursor(CGMainDisplayID())
            CGAssociateMouseAndMouseCursorPosition(1)
        }

        func handleMouseDelta(deltaX: CGFloat, deltaY: CGFloat) {
            guard let renderer, renderer.camera.isFirstPerson, isMouseCaptured else { return }
            if renderer.camera.isPilotingPlane {
                // Allow limited mouse look while piloting (flight sim style)
                renderer.camera.adjustPlaneCameraLook(deltaX: Float(deltaX), deltaY: Float(deltaY))
            } else {
                renderer.camera.rotate(deltaX: Float(deltaX), deltaY: Float(deltaY))
            }
        }

        func handleKeyDown(keyCode: UInt16) {
            // Ignore key repeats (key already held down)
            let isRepeat = pressedKeys.contains(keyCode)
            pressedKeys.insert(keyCode)

            // Skip double-tap detection for key repeats
            guard !isRepeat else { return }

            // ESC releases mouse in first-person mode
            if keyCode == 53 { // ESC
                if isMouseCaptured {
                    releaseMouse()
                } else if renderer?.camera.isFirstPerson == true {
                    // ESC while not captured exits first-person mode
                    toggleFirstPersonMode()
                }
            }

            // F toggles first-person mode
            if keyCode == 3 { // F
                toggleFirstPersonMode()
            }

            // Space: double-tap toggles flying, single tap jumps (in gravity mode)
            if keyCode == 49 { // Space
                let now = CACurrentMediaTime()
                if now - lastSpacePressTime < doubleTapInterval {
                    // Double-tap: toggle flying
                    renderer?.camera.toggleFlying()
                    lastSpacePressTime = 0  // Reset to prevent triple-tap
                } else {
                    // Single tap: jump if in gravity mode
                    if renderer?.camera.isFlying == false {
                        renderer?.camera.jump()
                    }
                    lastSpacePressTime = now
                }
            }

            // W: double-tap behavior depends on mode
            if keyCode == 13 { // W
                let now = CACurrentMediaTime()
                if now - lastWPressTime < doubleTapInterval {
                    if renderer?.camera.isPilotingPlane == true {
                        // Double-tap W while piloting: loop belly out
                        renderer?.camera.startAerobaticManeuver(.loopBellyOut)
                    } else {
                        // Double-tap W while walking: start sprinting
                        renderer?.camera.isSprinting = true
                    }
                    lastWPressTime = 0  // Reset to prevent triple-tap
                } else {
                    lastWPressTime = now
                }
            }

            // S: double-tap for loop belly in (only when piloting)
            if keyCode == 1 { // S
                let now = CACurrentMediaTime()
                if now - lastSPressTime < doubleTapInterval {
                    if renderer?.camera.isPilotingPlane == true {
                        renderer?.camera.startAerobaticManeuver(.loopBellyIn)
                    }
                    lastSPressTime = 0
                } else {
                    lastSPressTime = now
                }
            }

            // A: double-tap for left roll (only when piloting)
            if keyCode == 0 { // A
                let now = CACurrentMediaTime()
                if now - lastAPressTime < doubleTapInterval {
                    if renderer?.camera.isPilotingPlane == true {
                        renderer?.camera.startAerobaticManeuver(.rollLeft)
                    }
                    lastAPressTime = 0
                } else {
                    lastAPressTime = now
                }
            }

            // D: double-tap for right roll (only when piloting)
            if keyCode == 2 { // D
                let now = CACurrentMediaTime()
                if now - lastDPressTime < doubleTapInterval {
                    if renderer?.camera.isPilotingPlane == true {
                        renderer?.camera.startAerobaticManeuver(.rollRight)
                    }
                    lastDPressTime = 0
                } else {
                    lastDPressTime = now
                }
            }

            // E: board/exit plane
            if keyCode == 14 { // E
                guard let renderer else { return }

                // If already flying a plane, exit
                if renderer.camera.isPilotingPlane {
                    exitPlane()
                    return
                }

                // If attached to a plane, board it
                if case .plane(let index) = renderer.camera.grappleAttachment {
                    boardPlane(index: index)
                }
            }

        }

        func handleShiftPressed() {
            renderer?.camera.isShiftHeld = true
            tryGrapple()
        }

        func handleShiftReleased() {
            renderer?.camera.isShiftHeld = false
            // If attached, release
            if renderer?.camera.isAttached == true {
                renderer?.camera.stopGrapple()
            }
        }

        private func tryGrapple() {
            guard let renderer, let cityView,
                  renderer.camera.isFirstPerson,
                  !renderer.camera.isFlying,
                  !renderer.camera.isGrappling,
                  !renderer.camera.isAttached else { return }

            // Cast ray from center of screen
            let size = cityView.drawableSize
            let centerPoint = CGPoint(x: size.width / 2, y: size.height / 2)

            if let result = renderer.pickGrappleTarget(at: centerPoint, in: size) {
                renderer.camera.startGrapple(to: result.position, attachment: result.attachment)
            }
        }

        private func boardPlane(index: Int) {
            guard let renderer else { return }
            guard let planePos = renderer.planePosition(index: index),
                  let planeYaw = renderer.planeYaw(index: index) else { return }

            // Board the plane - transition camera to piloting mode
            renderer.camera.boardPlane(index: index, planePosition: planePos, planeYaw: planeYaw)
            renderer.startPilotingPlane(index: index)

            // Update AppState
            appState?.isPilotingPlane = true
            appState?.canBoardPlane = false
        }

        private func exitPlane() {
            guard let renderer else { return }

            // Exit the plane - returns to first-person at plane position
            _ = renderer.camera.exitPlane()
            renderer.stopPilotingPlane()

            // Update AppState
            appState?.isPilotingPlane = false
        }

        func handleKeyUp(keyCode: UInt16) {
            pressedKeys.remove(keyCode)

            // Stop sprinting when W is released
            if keyCode == 13 { // W
                renderer?.camera.isSprinting = false
            }
        }

        private func startMovementTimer() {
            stopMovementTimer()
            lastMovementTime = CACurrentMediaTime()
            movementTimer = Timer.scheduledTimer(withTimeInterval: 1.0 / 60.0, repeats: true) { [weak self] _ in
                self?.updateMovement()
            }
        }

        private func stopMovementTimer() {
            movementTimer?.invalidate()
            movementTimer = nil
        }

        private func updateMovement() {
            guard let renderer, renderer.camera.isFirstPerson else { return }

            let now = CACurrentMediaTime()
            let deltaTime = Float(now - lastMovementTime)
            lastMovementTime = now

            // Handle plane piloting (takes highest priority)
            if renderer.camera.isPilotingPlane {
                updatePlaneControls(deltaTime: deltaTime)
                return
            }

            // Handle grapple movement (takes priority over normal movement)
            if renderer.camera.isGrappling {
                _ = renderer.camera.updateGrapple(deltaTime: deltaTime)
                // Skip normal movement while grappling
                return
            }

            // Handle attachment to moving objects (hold shift)
            if renderer.camera.isAttached {
                switch renderer.camera.grappleAttachment {
                case .plane(let index):
                    if let pos = renderer.planePosition(index: index) {
                        renderer.camera.updateAttachment(targetPosition: pos)
                        // Can board this plane
                        if appState?.canBoardPlane != true {
                            appState?.canBoardPlane = true
                        }
                    } else {
                        // Plane gone (exploded?), detach
                        renderer.camera.stopGrapple()
                        appState?.canBoardPlane = false
                    }
                case .helicopter(let index):
                    if let pos = renderer.helicopterPosition(index: index) {
                        renderer.camera.updateAttachment(targetPosition: pos)
                    } else {
                        // Helicopter gone, detach
                        renderer.camera.stopGrapple()
                    }
                case .car(let index):
                    if let pos = renderer.carPosition(index: index) {
                        renderer.camera.updateAttachment(targetPosition: pos, rideOnTop: true)
                    } else {
                        // Car gone, detach
                        renderer.camera.stopGrapple()
                    }
                case .satellite(let sessionID):
                    if let pos = renderer.satellitePosition(sessionID: sessionID) {
                        renderer.camera.updateAttachment(targetPosition: pos)
                    } else {
                        // Satellite gone (session ended), detach
                        renderer.camera.stopGrapple()
                    }
                case .block, .beacon:
                    // Static attachment, nothing to update
                    break
                case .none:
                    break
                }
                // Skip normal movement while attached
                return
            } else {
                // Not attached, clear boarding prompt if showing
                if appState?.canBoardPlane == true {
                    appState?.canBoardPlane = false
                }
            }

            // Check if standing on satellite still exists (for cleanup)
            if renderer.camera.standingOnSatellite != nil {
                // Verify the satellite still exists
                if renderer.getSatelliteTarget(sessionID: renderer.camera.standingOnSatellite!) == nil {
                    // Satellite disappeared, stop standing
                    renderer.camera.standingOnSatellite = nil
                }
            }

            // Calculate movement direction from pressed keys
            var forwardAmount: Float = 0
            var rightAmount: Float = 0
            var upAmount: Float = 0

            // W/S for forward/back
            if pressedKeys.contains(13) { forwardAmount += 1 }  // W
            if pressedKeys.contains(1) { forwardAmount -= 1 }   // S

            // A/D for strafe
            if pressedKeys.contains(0) { rightAmount += 1 }     // A
            if pressedKeys.contains(2) { rightAmount -= 1 }     // D

            // Up/down only in flying mode (Space/Shift)
            if renderer.camera.isFlying {
                if pressedKeys.contains(49) { upAmount += 1 }       // Space
                if pressedKeys.contains(56) || pressedKeys.contains(60) { upAmount -= 1 } // Shift
            }

            // Always apply movement/physics (gravity needs to run even without input)
            let blocks = appState?.blocks
            let satellites = renderer.getSatellitePositions()
            renderer.camera.move(forward: forwardAmount, right: rightAmount, up: upAmount, deltaTime: deltaTime, blocks: blocks, satellites: satellites)

            // Center-screen hit testing for crosshair targeting (throttled to reduce lag)
            hitTestFrameCounter += 1
            if hitTestFrameCounter >= hitTestInterval {
                hitTestFrameCounter = 0
                updateCrosshairTarget()
            }
        }

        private func updatePlaneControls(deltaTime: Float) {
            guard let renderer else { return }

            // W = nose down, S = nose up
            var pitchInput: Float = 0
            if pressedKeys.contains(13) { pitchInput -= 1 }  // W - nose down
            if pressedKeys.contains(1) { pitchInput += 1 }   // S - nose up

            // A = bank left, D = bank right (standard flight sim)
            var rollInput: Float = 0
            if pressedKeys.contains(0) { rollInput -= 1 }    // A - roll left
            if pressedKeys.contains(2) { rollInput += 1 }    // D - roll right

            // Space = boost
            let isBoosting = pressedKeys.contains(49)        // Space

            // Update plane physics
            renderer.camera.updatePlanePhysics(
                deltaTime: deltaTime,
                pitchInput: pitchInput,
                rollInput: rollInput,
                isBoosting: isBoosting
            )

            // Sync flight state to renderer for rendering
            renderer.pilotedPlaneFlightState = renderer.camera.planeFlightState
        }

        private func updateCrosshairTarget() {
            guard let renderer, let cityView, renderer.camera.isFirstPerson else { return }

            // Use center of screen for hit testing
            let size = cityView.drawableSize
            let centerPoint = CGPoint(x: size.width / 2, y: size.height / 2)

            // Check for plane hit first (makes them speed up)
            if let planeIndex = renderer.pickPlane(at: centerPoint, in: size) {
                renderer.setHoveredPlane(index: planeIndex)
                // Clear block hover when looking at plane
                if hoveredNodeID != nil {
                    hoveredNodeID = nil
                    appState?.hoveredURL = nil
                    appState?.hoveredNodeID = nil
                }
                return
            } else {
                renderer.setHoveredPlane(index: nil)
            }

            // Check for block hit at center
            if let blockHit = renderer.pickBlockHit(at: centerPoint, in: size) {
                let block = blockHit.block
                if hoveredNodeID != block.nodeID {
                    hoveredNodeID = block.nodeID
                    appState?.hoveredURL = appState?.url(for: block.nodeID)
                    appState?.hoveredNodeID = block.nodeID
                }
            } else {
                if hoveredNodeID != nil {
                    hoveredNodeID = nil
                    appState?.hoveredURL = nil
                    appState?.hoveredNodeID = nil
                }
            }
        }
    }
}

final class CityMTKView: MTKView {
    var onScroll: ((CGFloat, CGFloat) -> Void)?
    var onHover: ((CGPoint) -> Void)?
    var onHoverEnd: (() -> Void)?
    var onKey: ((String) -> Void)?
    var onClick: ((CGPoint) -> Void)?
    var onDoubleClick: ((CGPoint) -> Void)?
    var onRightClick: ((CGPoint) -> Void)?
    weak var coordinator: MetalCityView.Coordinator?
    private var trackingArea: NSTrackingArea?
    private var pendingClickTimer: Timer?
    private var pendingClickPoint: CGPoint?

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
        // In first-person mode with captured mouse, use delta for look
        if let coordinator, coordinator.isMouseCaptured {
            coordinator.handleMouseDelta(deltaX: event.deltaX, deltaY: event.deltaY)
        } else {
            let point = convert(event.locationInWindow, from: nil)
            onHover?(point)
        }
    }

    override func mouseDragged(with event: NSEvent) {
        // Also handle mouse delta during drag for captured mode
        if let coordinator, coordinator.isMouseCaptured {
            coordinator.handleMouseDelta(deltaX: event.deltaX, deltaY: event.deltaY)
        }
    }

    override func mouseExited(with event: NSEvent) {
        onHoverEnd?()
    }

    override func mouseDown(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)

        if event.clickCount == 2 {
            // Double-click: cancel pending single-click and trigger double-click
            pendingClickTimer?.invalidate()
            pendingClickTimer = nil
            pendingClickPoint = nil
            onDoubleClick?(point)
        } else {
            // Single-click: delay to check for double-click
            pendingClickTimer?.invalidate()
            pendingClickPoint = point
            pendingClickTimer = Timer.scheduledTimer(withTimeInterval: NSEvent.doubleClickInterval, repeats: false) { [weak self] _ in
                guard let self, let clickPoint = self.pendingClickPoint else { return }
                self.pendingClickPoint = nil
                self.onClick?(clickPoint)
            }
        }
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
        // Handle first-person movement keys
        coordinator?.handleKeyDown(keyCode: event.keyCode)

        // Also pass to original handler for other keys
        if let key = event.charactersIgnoringModifiers, !key.isEmpty {
            onKey?(key)
        }
    }

    override func keyUp(with event: NSEvent) {
        coordinator?.handleKeyUp(keyCode: event.keyCode)
    }

    override func flagsChanged(with event: NSEvent) {
        // Track modifier key state changes (Shift)
        let shiftPressed = event.modifierFlags.contains(.shift)
        let wasShiftPressed = coordinator?.pressedKeys.contains(56) == true
        if shiftPressed {
            coordinator?.pressedKeys.insert(56)
            // Trigger grapple on Shift press (not release)
            if !wasShiftPressed {
                coordinator?.handleShiftPressed()
            }
        } else {
            coordinator?.pressedKeys.remove(56)
            coordinator?.pressedKeys.remove(60)
            // Handle shift release for grapple detachment
            if wasShiftPressed {
                coordinator?.handleShiftReleased()
            }
        }
    }
}
