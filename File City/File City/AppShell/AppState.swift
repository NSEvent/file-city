import AppKit
import Combine
import Foundation

@MainActor
final class AppState: ObservableObject {
    @Published var rootURL: URL?
    @Published var nodeCount: Int = 0
    @Published var blocks: [CityBlock] = []
    @Published private(set) var pendingAutoFit = false
    @Published var searchQuery: String = ""
    @Published var searchResults: [URL] = []
    @Published var selectedURLs: Set<URL> = []
    @Published var selectedFocusNodeIDs: Set<UUID> = []

    /// Convenience accessor for single selection (first selected URL)
    var selectedURL: URL? { selectedURLs.first }

    @Published var hoveredURL: URL?
    @Published var hoveredNodeID: UUID?
    @Published var hoveredGitStatus: [String]?
    @Published var hoveredBeaconNodeID: UUID?
    @Published var hoveredBeaconURL: URL?
    @Published var hoveredClaudeSession: ClaudeSession?
    @Published var hoveredClaudeOutputLines: [String]?
    private var hoveredClaudeSessionID: UUID?
    @Published var activityInfoLines: [String]?
    @Published private(set) var activityVersion: UInt = 0
    @Published var isFirstPerson: Bool = false
    @Published var canBoardPlane: Bool = false
    @Published var isPilotingPlane: Bool = false

    // MARK: - Time Machine State
    @Published var timeTravelMode: TimeTravelMode = .live
    @Published var commitHistory: [GitCommit] = []
    @Published var sliderPosition: Double = 1.0  // 0=oldest, 1=newest/live
    @Published var isRootGitRepo: Bool = false

    private let scanner = DirectoryScanner()
    private let gitTreeScanner = GitTreeScanner()
    private let mapper = CityMapper()
    private let searchIndex = SearchIndex()
    private let pinStore = PinStore()
    private let rescanSubject = PassthroughSubject<Void, Never>()
    let fileWriteSubject = PassthroughSubject<UUID, Never>()
    let fileReadSubject = PassthroughSubject<UUID, Never>()
    private var gitStatusTask: Task<Void, Never>?
    private var gitLOCTask: Task<Void, Never>?
    private var gitCleanByPath: [String: Bool] = [:]
    /// LOC data keyed by path (not UUID) to survive rescans that regenerate node IDs
    @Published var locByPath: [String: Int] = [:]

    /// Computed property to convert path-based LOC to nodeID-based for rendering
    /// This allows LOC data to persist across FSEvents rescans that regenerate UUIDs
    var locByNodeID: [UUID: Int] {
        var result: [UUID: Int] = [:]
        for (path, loc) in locByPath {
            let url = URL(fileURLWithPath: path)
            if let node = nodeByURL[url] {
                result[node.id] = loc
            }
        }
        return result
    }
    private var historicalTreeCache: [String: FileNode] = [:]
    private var lastLoadedCommitID: String?
    private var timeTravelLoadTask: Task<Void, Never>?
    private var focusNodeIDByURL: [URL: UUID] = [:]
    private var nodeByID: [UUID: FileNode] = [:]
    private var nodeByURL: [URL: FileNode] = [:]
    private var watcher: FSEventsWatcher?
    private var activityWatcher: FileActivityWatcher?
    private var socketWatcher: SocketActivityWatcher?
    private var activityByURL: [URL: NodeActivityPulse] = [:]
    private var activityInfoExpiresAt: CFTimeInterval?
    private var ignoreActivityUntil: CFTimeInterval = 0
    let activityDuration: CFTimeInterval = 1.4
    private var cancellables: Set<AnyCancellable> = []

    // MARK: - Claude Session Management
    @Published var claudeSessions: [ClaudeSession] = []
    let claudeSessionStateChanged = PassthroughSubject<UUID, Never>()
    let claudeSessionExited = PassthroughSubject<UUID, Never>()
    private let ptyManager = PTYManager()
    private let sizeFormatter = ByteCountFormatter()
    private let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter
    }()

    init() {
        $searchQuery
            .debounce(for: .milliseconds(150), scheduler: DispatchQueue.main)
            .sink { [weak self] query in
                self?.searchResults = self?.searchIndex.search(query) ?? []
            }
            .store(in: &cancellables)

        rescanSubject
            .debounce(for: .milliseconds(250), scheduler: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.scanRoot()
            }
            .store(in: &cancellables)

        // Subscribe to PTY manager events
        ptyManager.sessionStateChanged
            .receive(on: DispatchQueue.main)
            .sink { [weak self] sessionID in
                self?.handlePTYSessionStateChanged(sessionID)
            }
            .store(in: &cancellables)

        ptyManager.sessionExited
            .receive(on: DispatchQueue.main)
            .sink { [weak self] sessionID in
                self?.handlePTYSessionExited(sessionID)
            }
            .store(in: &cancellables)

        NotificationCenter.default.addObserver(
            forName: .fileCityOpenURL,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            guard let url = notification.object as? URL else { return }
            Task { @MainActor [weak self] in
                self?.openRoot(url)
            }
        }

        // Skip automatic setup if running tests to prevent hangs
        if ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] == nil {
            let root = AppDelegate.takePendingOpenURL()
                ?? LaunchRootResolver.resolve()
                ?? defaultRootURL()
            if let root {
                rootURL = root
                // Delay scan slightly to let SwiftUI set up the view hierarchy first
                DispatchQueue.main.async { [weak self] in
                    self?.scanRoot(autoFit: true)
                    self?.startWatchingRoot()
                    self?.loadGitHistory()
                }
            }
        }
    }

    func chooseRoot() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.prompt = "Choose"
        if panel.runModal() == .OK {
            rootURL = panel.url
            scanRoot(autoFit: true)
            startWatchingRoot()
        }
    }

    func scanRoot(autoFit: Bool = false) {
        guard let rootURL else { return }
        Task {
            do {
                let result = try await scanner.scan(url: rootURL, maxDepth: 2, maxNodes: LayoutRules.default.maxNodes)
                nodeCount = result.nodeCount
                searchIndex.reset()
                searchIndex.indexNode(result.root)
                // Update node maps BEFORE blocks to ensure locByNodeID computed property
                // has current data when $blocks subscription triggers updateFromAppState()
                focusNodeIDByURL = buildFocusMap(root: result.root)
                nodeByID = buildNodeIDMap(root: result.root)
                nodeByURL = buildNodeURLMap(root: result.root)
                blocks = mapper.map(root: result.root, rules: .default, pinStore: pinStore)
                if autoFit {
                    pendingAutoFit = true
                }
                selectedFocusNodeIDs = Set(selectedURLs.compactMap { focusNodeIDByURL[$0] })
                hoveredURL = hoveredURL.flatMap { nodeByURL[$0] != nil ? $0 : nil }
                hoveredNodeID = hoveredURL.flatMap { nodeByURL[$0]?.id }
                hoveredBeaconURL = hoveredBeaconURL.flatMap { nodeByURL[$0] != nil ? $0 : nil }
                hoveredBeaconNodeID = hoveredBeaconURL.flatMap { nodeByURL[$0]?.id }
                applyCachedGitStatuses()
                refreshGitStatuses()
            } catch {
                nodeCount = 0
                blocks = []
                searchResults = []
                focusNodeIDByURL = [:]
                nodeByID = [:]
                nodeByURL = [:]
                selectedFocusNodeIDs = []
                hoveredNodeID = nil
                hoveredBeaconNodeID = nil
                hoveredBeaconURL = nil
                locByPath = [:]
            }
        }
    }

    func open(_ url: URL) {
        focus(url)
        FileActions().open(url)
    }

    func reveal(_ url: URL) {
        focus(url)
        FileActions().revealInFinder(url)
    }

    // MARK: - Claude Session Management

    func launchClaude(at directory: URL) {
        let sessionID = ptyManager.spawnClaude(at: directory)
        let session = ClaudeSession(
            id: sessionID,
            workingDirectory: directory,
            spawnTime: Date(),
            state: .launching
        )
        claudeSessions.append(session)
    }

    func focusClaudeSession(_ sessionID: UUID) {
        ptyManager.focusTerminal(sessionID: sessionID)
    }

    func terminateClaudeSession(_ sessionID: UUID) {
        ptyManager.terminateSession(id: sessionID)
    }

    func setHoveredClaudeSession(_ sessionID: UUID?) {
        hoveredClaudeSessionID = sessionID
        if let sessionID {
            hoveredClaudeSession = claudeSessions.first { $0.id == sessionID }
            hoveredClaudeOutputLines = ptyManager.sessions[sessionID]?.lastOutputLines
        } else {
            hoveredClaudeSession = nil
            hoveredClaudeOutputLines = nil
        }
    }

    /// Refresh hovered session output (called periodically when hovering)
    private func refreshHoveredClaudeOutput() {
        guard let sessionID = hoveredClaudeSessionID else { return }
        hoveredClaudeSession = claudeSessions.first { $0.id == sessionID }
        hoveredClaudeOutputLines = ptyManager.sessions[sessionID]?.lastOutputLines
    }

    func claudeSessionOutputLines(for sessionID: UUID) -> [String]? {
        ptyManager.sessions[sessionID]?.lastOutputLines
    }

    private func handlePTYSessionStateChanged(_ sessionID: UUID) {
        NSLog("[AppState] handlePTYSessionStateChanged: %@", sessionID.uuidString)
        guard let ptySession = ptyManager.sessions[sessionID] else {
            NSLog("[AppState] No PTY session found")
            return
        }

        // Update our local session state
        if let index = claudeSessions.firstIndex(where: { $0.id == sessionID }) {
            NSLog("[AppState] Updating claudeSession %d to state %d", index, ptySession.state.rawValue)
            claudeSessions[index].state = ptySession.state
            claudeSessions[index].ptyPath = ptySession.ptyPath
        }

        // Refresh hover output if we're hovering over this or any session
        // (PTY manager polls all sessions, so refresh on any update)
        refreshHoveredClaudeOutput()

        // Notify observers
        NSLog("[AppState] Sending claudeSessionStateChanged")
        claudeSessionStateChanged.send(sessionID)
    }

    private func handlePTYSessionExited(_ sessionID: UUID) {
        // Update state to exiting
        if let index = claudeSessions.firstIndex(where: { $0.id == sessionID }) {
            claudeSessions[index].state = .exiting
        }

        // Notify observers
        claudeSessionExited.send(sessionID)

        // Remove session after delay
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 1_500_000_000) // 1.5s
            claudeSessions.removeAll { $0.id == sessionID }
        }
    }

    func togglePin(_ url: URL) {
        let hash = PinStore.pathHash(url)
        let pinned = !pinStore.isPinned(pathHash: hash)
        pinStore.setPinned(pinned, pathHash: hash, url: url)
        if let rootURL {
            Task {
                let result = try await scanner.scan(url: rootURL, maxDepth: 2, maxNodes: LayoutRules.default.maxNodes)
                nodeCount = result.nodeCount
                searchIndex.reset()
                searchIndex.indexNode(result.root)
                // Update node maps BEFORE blocks (same fix as scanRoot)
                focusNodeIDByURL = buildFocusMap(root: result.root)
                nodeByID = buildNodeIDMap(root: result.root)
                nodeByURL = buildNodeURLMap(root: result.root)
                blocks = mapper.map(root: result.root, rules: .default, pinStore: pinStore)
                selectedFocusNodeIDs = Set(selectedURLs.compactMap { focusNodeIDByURL[$0] })
                hoveredURL = hoveredURL.flatMap { nodeByURL[$0] != nil ? $0 : nil }
                hoveredNodeID = hoveredURL.flatMap { nodeByURL[$0]?.id }
                hoveredBeaconURL = hoveredBeaconURL.flatMap { nodeByURL[$0] != nil ? $0 : nil }
                hoveredBeaconNodeID = hoveredBeaconURL.flatMap { nodeByURL[$0]?.id }
                applyCachedGitStatuses()
                refreshGitStatuses()
            }
        }
    }

    func focus(_ url: URL) {
        selectedURLs = [url]
        selectedFocusNodeIDs = focusNodeIDByURL[url].map { [$0] } ?? []
    }

    /// Select a file/directory without navigating (for single-click)
    func select(_ url: URL) {
        selectedURLs = [url]
        selectedFocusNodeIDs = focusNodeIDByURL[url].map { [$0] } ?? []
    }

    /// Select multiple URLs (for list view multi-selection)
    func selectURLs(_ urls: Set<URL>) {
        selectedURLs = urls
        selectedFocusNodeIDs = Set(urls.compactMap { focusNodeIDByURL[$0] })
    }

    /// Add URL to current selection (for Cmd+click)
    func addToSelection(_ url: URL) {
        selectedURLs.insert(url)
        if let nodeID = focusNodeIDByURL[url] {
            selectedFocusNodeIDs.insert(nodeID)
        }
    }

    /// Remove URL from selection (for Cmd+click toggle)
    func removeFromSelection(_ url: URL) {
        selectedURLs.remove(url)
        if let nodeID = focusNodeIDByURL[url] {
            selectedFocusNodeIDs.remove(nodeID)
        }
    }

    /// Clear all selection
    func clearSelection() {
        selectedURLs = []
        selectedFocusNodeIDs = []
    }

    /// Activate item: navigate into directories, open files with default app (for double-click)
    func activateItem(_ url: URL) {
        if isDirectory(url) {
            enter(url)
        } else {
            open(url)
        }
    }

    func enter(_ url: URL) {
        focus(url)
        openRoot(url)
    }

    func openRoot(_ url: URL) {
        let target = isDirectory(url) ? url : url.deletingLastPathComponent()
        guard isDirectory(target) else { return }
        rootURL = target
        hoveredURL = nil
        hoveredNodeID = nil
        hoveredGitStatus = nil
        hoveredBeaconNodeID = nil
        hoveredBeaconURL = nil
        activityInfoLines = nil
        selectedURLs = []
        selectedFocusNodeIDs = []
        // Clear time travel state when changing roots
        historicalTreeCache = [:]
        timeTravelMode = .live
        sliderPosition = 1.0
        scanRoot(autoFit: true)
        startWatchingRoot()
        loadGitHistory()
    }

    func goToParent() {
        guard let parent = parentURL() else { return }
        rootURL = parent
        hoveredURL = nil
        hoveredNodeID = nil
        hoveredGitStatus = nil
        hoveredBeaconNodeID = nil
        hoveredBeaconURL = nil
        activityInfoLines = nil
        selectedURLs = []
        selectedFocusNodeIDs = []
        // Clear time travel state when changing roots
        historicalTreeCache = [:]
        timeTravelMode = .live
        sliderPosition = 1.0
        scanRoot(autoFit: true)
        startWatchingRoot()
        loadGitHistory()
    }

    func canGoToParent() -> Bool {
        parentURL() != nil
    }

    func url(for nodeID: UUID) -> URL? {
        nodeByID[nodeID]?.url
    }

    func clearPendingAutoFit() {
        pendingAutoFit = false
    }

    func infoLines(for url: URL) -> [String] {
        guard let node = nodeByURL[url] else {
            return [url.lastPathComponent, url.path]
        }
        let kind = displayType(node.type)
        let sizeText = sizeFormatter.string(fromByteCount: node.sizeBytes)
        let modifiedText = dateFormatter.string(from: node.modifiedAt)
        return [
            node.name,
            "\(kind) • \(sizeText)",
            "Modified \(modifiedText)",
            node.url.path
        ]
    }

    func gitStatusLines(for url: URL) -> [String] {
        // Delegate to GitService for consistent formatting
        GitService.formatStatusLines(for: url)
    }

    private func refreshGitStatuses() {
        gitStatusTask?.cancel()
        let nodes = nodeByID
        let rootPath = rootURL?.path
        gitStatusTask = Task.detached(priority: .utility) {
            var results: [UUID: Bool] = [:]
            results.reserveCapacity(nodes.count)
            for node in nodes.values where node.isGitRepo {
                if Task.isCancelled { return }
                results[node.id] = GitService.isRepositoryClean(at: node.url)
            }
            await MainActor.run {
                guard rootPath == self.rootURL?.path else { return }
                for (nodeID, isClean) in results {
                    if let url = self.nodeByID[nodeID]?.url {
                        self.gitCleanByPath[url.path] = isClean
                    }
                }
                self.blocks = self.blocks.map { block in
                    guard let clean = results[block.nodeID] else { return block }
                    return block.withGitClean(clean)
                }
            }
        }
    }

    private func applyCachedGitStatuses() {
        guard !gitCleanByPath.isEmpty else { return }
        blocks = blocks.map { block in
            guard let url = nodeByID[block.nodeID]?.url,
                  let clean = gitCleanByPath[url.path] else {
                return block
            }
            return block.withGitClean(clean)
        }
    }

    /// Count LOC for a specific node's containing git repo (triggered by write events)
    func countLOCForNode(_ nodeID: UUID) {
        guard let node = nodeByID[nodeID] else { return }

        // Find the git repo containing this node
        let gitRepoNode = findContainingGitRepo(for: node)
        guard let repoNode = gitRepoNode else { return }

        // Count LOC in background - store by path to survive rescans
        let repoPath = repoNode.url.path
        Task.detached(priority: .utility) {
            let loc = GitService.countLinesOfCode(at: repoNode.url)
            await MainActor.run {
                self.locByPath[repoPath] = loc
            }
        }
    }

    /// Find the git repo that contains this node (could be the node itself or an ancestor)
    private func findContainingGitRepo(for node: FileNode) -> FileNode? {
        // Check if this node is a git repo
        if node.isGitRepo {
            return node
        }

        // Walk up the path to find parent git repo
        var url = node.url.deletingLastPathComponent()
        while url.path != "/" {
            if let parentNode = nodeByURL[url], parentNode.isGitRepo {
                return parentNode
            }
            url = url.deletingLastPathComponent()
        }

        return nil
    }

    // MARK: - Time Machine Methods

    /// Fetch git commit history for the current root
    func loadGitHistory() {
        guard let rootURL else {
            isRootGitRepo = false
            commitHistory = []
            return
        }

        // Check if this is a git repo using GitService
        isRootGitRepo = GitService.isGitRepository(at: rootURL)

        guard isRootGitRepo else {
            commitHistory = []
            timeTravelMode = .live
            sliderPosition = 1.0
            return
        }

        Task {
            let history = await GitService.fetchCommitHistory(at: rootURL, limit: Constants.Git.maxCommitHistory)
            commitHistory = history
            timeTravelMode = .live
            sliderPosition = 1.0
        }
    }

    /// Update time travel position during slider drag
    /// - Parameters:
    ///   - position: Slider position (0 = oldest, 1 = newest/live)
    ///   - live: If true, immediately load and display the historical tree
    func updateTimeTravelPosition(_ position: Double, live: Bool = false) {
        guard !commitHistory.isEmpty else { return }
        sliderPosition = position

        let previousMode = timeTravelMode

        if position >= 0.99 {
            timeTravelMode = .live
            // Return to live if we were in historical mode
            if live && !previousMode.isLive {
                lastLoadedCommitID = nil
                scanRoot()
                startWatchingRoot()
            }
        } else {
            // Map position to commit index (1.0 = newest = index 0)
            let invertedPosition = 1.0 - position
            let index = Int(invertedPosition * Double(commitHistory.count - 1))
            let clampedIndex = max(0, min(commitHistory.count - 1, index))
            let commit = commitHistory[clampedIndex]
            timeTravelMode = .historical(commit)

            // Load tree immediately if live mode and commit changed
            if live && commit.id != lastLoadedCommitID {
                lastLoadedCommitID = commit.id
                loadHistoricalTreeLive(commit: commit)
            }
        }
    }

    /// Load historical tree during live scrubbing (optimized for responsiveness)
    private func loadHistoricalTreeLive(commit: GitCommit) {
        // Stop file watching
        watcher?.stop()
        activityWatcher?.stop()
        socketWatcher?.stop()

        // Cancel any pending load
        timeTravelLoadTask?.cancel()

        // Check cache first - if cached, apply immediately
        if let cachedTree = historicalTreeCache[commit.id] {
            applyHistoricalTree(cachedTree)
            return
        }

        // Fetch in background
        timeTravelLoadTask = Task {
            guard let rootURL else { return }
            let tree = await fetchAndBuildHistoricalTree(commit: commit, rootURL: rootURL)

            // Check if we're still on this commit (user may have moved slider)
            guard !Task.isCancelled,
                  case .historical(let currentCommit) = timeTravelMode,
                  currentCommit.id == commit.id,
                  let tree else { return }

            historicalTreeCache[commit.id] = tree
            applyHistoricalTree(tree)
        }
    }

    /// Commit to time travel position (load historical tree)
    func commitTimeTravel() {
        switch timeTravelMode {
        case .live:
            scanRoot()
            startWatchingRoot()

        case .historical(let commit):
            // Stop file watching in historical mode
            watcher?.stop()
            activityWatcher?.stop()
            socketWatcher?.stop()

            // Check cache first
            if let cachedTree = historicalTreeCache[commit.id] {
                applyHistoricalTree(cachedTree)
            } else {
                Task {
                    guard let rootURL else { return }
                    let tree = await fetchAndBuildHistoricalTree(commit: commit, rootURL: rootURL)
                    if let tree {
                        historicalTreeCache[commit.id] = tree
                        applyHistoricalTree(tree)
                    }
                }
            }
        }
    }

    /// Return to live mode
    func returnToLive() {
        sliderPosition = 1.0
        timeTravelMode = .live
        scanRoot()
        startWatchingRoot()
    }

    /// Fetch git tree at commit and build FileNode
    private func fetchAndBuildHistoricalTree(commit: GitCommit, rootURL: URL) async -> FileNode? {
        guard let output = await GitService.fetchTreeAtCommit(commit.id, at: rootURL) else {
            return nil
        }

        let result = gitTreeScanner.buildTree(from: output, rootURL: rootURL, maxDepth: Constants.Scanning.maxDepth)
        return result.root
    }

    /// Apply a historical FileNode tree to the city
    private func applyHistoricalTree(_ root: FileNode) {
        nodeCount = countNodes(root)
        searchIndex.reset()
        searchIndex.indexNode(root)
        // Update node maps BEFORE blocks (same fix as scanRoot)
        focusNodeIDByURL = buildFocusMap(root: root)
        nodeByID = buildNodeIDMap(root: root)
        nodeByURL = buildNodeURLMap(root: root)
        blocks = mapper.map(root: root, rules: .default, pinStore: pinStore)
        // Clear selection when changing history
        selectedURLs = []
        selectedFocusNodeIDs = []
        hoveredURL = nil
        hoveredNodeID = nil
    }

    private func countNodes(_ node: FileNode) -> Int {
        TreeIndexer.countNodes(node)
    }

    /// Get current commit for display (if in historical mode)
    func currentHistoricalCommit() -> GitCommit? {
        timeTravelMode.commit
    }

    func actionContainerURL() -> URL? {
        guard let rootURL else { return nil }
        guard let selectedURL = selectedURLs.first else { return rootURL }
        var isDirectory: ObjCBool = false
        if FileManager.default.fileExists(atPath: selectedURL.path, isDirectory: &isDirectory), isDirectory.boolValue {
            return selectedURL
        }
        return selectedURL.deletingLastPathComponent()
    }

    func createFolder() {
        guard timeTravelMode.isLive else { return }  // No file ops in historical mode
        guard let containerURL = actionContainerURL() else { return }
        guard let name = promptForName(title: "New Folder", message: "Enter a folder name.", placeholder: "New Folder") else { return }
        let newURL = containerURL.appendingPathComponent(name, isDirectory: true)
        do {
            try FileActions().createFolder(at: newURL)
            focus(newURL)
            rescanSubject.send(())
        } catch {
            presentError(error)
        }
    }

    func createFile() {
        guard timeTravelMode.isLive else { return }  // No file ops in historical mode
        guard let containerURL = actionContainerURL() else { return }
        guard let name = promptForName(title: "New File", message: "Enter a file name.", placeholder: "untitled.txt") else { return }
        let newURL = containerURL.appendingPathComponent(name, isDirectory: false)
        do {
            try FileActions().createEmptyFile(at: newURL)
            focus(newURL)
            rescanSubject.send(())
        } catch {
            presentError(error)
        }
    }

    func renameSelected() {
        guard timeTravelMode.isLive else { return }  // No file ops in historical mode
        guard let selectedURL = selectedURLs.first else { return }
        let currentName = selectedURL.lastPathComponent
        guard let name = promptForName(title: "Rename", message: "Enter a new name.", placeholder: currentName, defaultValue: currentName) else { return }
        let dstURL = selectedURL.deletingLastPathComponent().appendingPathComponent(name, isDirectory: isDirectory(selectedURL))
        do {
            try FileActions().renameItem(from: selectedURL, to: dstURL)
            focus(dstURL)
            rescanSubject.send(())
        } catch {
            presentError(error)
        }
    }

    func moveSelected() {
        guard timeTravelMode.isLive else { return }  // No file ops in historical mode
        guard !selectedURLs.isEmpty else { return }
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.prompt = "Move"
        if panel.runModal() == .OK, let destFolder = panel.url {
            do {
                for selectedURL in selectedURLs {
                    let destination = destFolder.appendingPathComponent(selectedURL.lastPathComponent, isDirectory: isDirectory(selectedURL))
                    try FileActions().moveItem(from: selectedURL, to: destination)
                }
                clearSelection()
                rescanSubject.send(())
            } catch {
                presentError(error)
            }
        }
    }

    func trashSelected() {
        guard timeTravelMode.isLive else { return }  // No file ops in historical mode
        guard !selectedURLs.isEmpty else { return }
        let count = selectedURLs.count
        let alert = NSAlert()
        alert.messageText = "Move to Trash?"
        alert.informativeText = count == 1 ? selectedURLs.first!.lastPathComponent : "\(count) items"
        alert.addButton(withTitle: "Trash")
        alert.addButton(withTitle: "Cancel")
        let response = alert.runModal()
        guard response == .alertFirstButtonReturn else { return }
        do {
            for url in selectedURLs {
                try FileActions().moveToTrash(url)
            }
            clearSelection()
            rescanSubject.send(())
        } catch {
            presentError(error)
        }
    }

    func pinnedURLs() -> [URL] {
        pinStore.allPinnedURLs()
    }

    func activityNow() -> CFTimeInterval {
        CFAbsoluteTimeGetCurrent()
    }

    func activitySnapshot(now: CFTimeInterval) -> [UUID: NodeActivityPulse] {
        activityByURL = activityByURL.filter { now - $0.value.startedAt <= activityDuration }
        if let expiresAt = activityInfoExpiresAt, now >= expiresAt {
            activityInfoLines = nil
            activityInfoExpiresAt = nil
        }
        var snapshot: [UUID: NodeActivityPulse] = [:]
        snapshot.reserveCapacity(activityByURL.count)
        for pulse in activityByURL.values {
            if let nodeID = resolveActivityNodeID(url: pulse.url) {
                // Prefer writes over reads, or more recent activity
                if let existing = snapshot[nodeID] {
                    if pulse.kind == .write && existing.kind == .read {
                        snapshot[nodeID] = pulse
                    } else if pulse.kind == existing.kind && pulse.startedAt > existing.startedAt {
                        snapshot[nodeID] = pulse
                    }
                } else {
                    snapshot[nodeID] = pulse
                }
            }
        }
        return snapshot
    }

    func triggerTestActivity(kind: ActivityKind) {
        let now = activityNow()
        let targetNodeID = hoveredNodeID ?? hoveredBeaconNodeID ?? selectedFocusNodeIDs.first
        guard let targetNodeID,
              let url = nodeByID[targetNodeID]?.url else { return }
        activityByURL[url] = NodeActivityPulse(
            kind: kind,
            startedAt: now,
            processName: "Test",
            url: url
        )
        if kind == .write {
            if let nodeID = resolveActivityNodeID(url: url) {
                fileWriteSubject.send(nodeID)
            }
        }
        let verb = kind == .write ? "Write" : "Read"
        let pathLine = relativePath(for: url) ?? url.lastPathComponent
        activityInfoLines = [
            "Test • \(verb)",
            pathLine
        ]
        activityInfoExpiresAt = now + 2.0
    }

    private func startWatchingRoot() {
        guard let rootURL else { return }
        // Suppress initial events (often stale or noise) for a short period after navigation
        ignoreActivityUntil = activityNow() + 1.0
        
        watcher?.stop()
        let watcher = FSEventsWatcher(url: rootURL)
        watcher.onChange = { [weak self] in
            self?.rescanSubject.send(())
        }
        // FSEvents can detect file writes without sudo
        watcher.onFileActivity = { [weak self] url, kind in
            self?.handleFSEventsActivity(url: url, kind: kind)
        }
        watcher.start()
        self.watcher = watcher

        // Connect to privileged helper for full read/write monitoring
        activityWatcher?.stop()
        socketWatcher?.stop()

        // Ensure helper is installed (prompts for password on first run)
        if HelperManager.ensureHelperReady() {
            let socketWatcher = SocketActivityWatcher(rootURL: rootURL) { [weak self] event in
                self?.handleActivityEvent(event)
            }
            socketWatcher.start()
            self.socketWatcher = socketWatcher
        } else if getuid() == 0 {
            // Fallback: if running as root, use direct fs_usage
            let activityWatcher = FileActivityWatcher(rootURL: rootURL) { [weak self] event in
                self?.handleActivityEvent(event)
            }
            activityWatcher.start()
            self.activityWatcher = activityWatcher
        }
        // If helper not available and not root, activity monitoring is disabled
    }

    private func handleFSEventsActivity(url: URL, kind: ActivityKind) {
        // Don't overwrite fs_usage events which have more detail
        let now = activityNow()
        if let existing = activityByURL[url], now - existing.startedAt < 0.3 {
            return
        }
        handleActivity(url: url, kind: kind, processName: "FSEvents", showInfo: false)
    }

    private func handleActivityEvent(_ event: FileActivityEvent) {
        handleActivity(url: event.url, kind: event.kind, processName: event.processName, showInfo: true)
    }

    /// Unified activity handler for both FSEvents and privileged helper events
    private func handleActivity(url: URL, kind: ActivityKind, processName: String, showInfo: Bool) {
        let now = activityNow()
        if now < ignoreActivityUntil { return }

        // Ignore internal git operations
        if isGitInternalPath(url) { return }

        activityByURL[url] = NodeActivityPulse(
            kind: kind,
            startedAt: now,
            processName: processName,
            url: url
        )

        // Send activity notifications
        if let nodeID = resolveActivityNodeID(url: url) {
            if kind == .write {
                fileWriteSubject.send(nodeID)
            } else if kind == .read {
                fileReadSubject.send(nodeID)
            }
        }

        activityVersion &+= 1

        // Show info panel for privileged helper events (more reliable source)
        if showInfo {
            let verb = kind == .write ? "Write" : "Read"
            let pathLine = relativePath(for: url) ?? url.lastPathComponent
            activityInfoLines = [
                "\(processName) • \(verb)",
                pathLine
            ]
            activityInfoExpiresAt = now + 2.0
        }
    }

    /// Check if a URL is within a .git directory (internal git operations)
    private func isGitInternalPath(_ url: URL) -> Bool {
        let path = url.path
        return path.contains("/.git/") || path.hasSuffix("/.git")
    }

    private func resolveActivityNodeID(url: URL) -> UUID? {
        if let node = nodeByURL[url] {
            return node.id
        }
        guard let rootURL else { return nil }
        guard url.path.hasPrefix(rootURL.path) else { return nil }
        // Find the first-level child of rootURL that contains this URL
        // This ensures files deep in a subdirectory animate the top-level building
        let rootPath = rootURL.path
        let relativePath = String(url.path.dropFirst(rootPath.count))
        let components = relativePath.split(separator: "/", omittingEmptySubsequences: true)
        if components.isEmpty {
            return nodeByURL[rootURL]?.id
        }
        let firstLevelPath = rootPath + "/" + String(components[0])
        let firstLevelURL = URL(fileURLWithPath: firstLevelPath)
        if let node = nodeByURL[firstLevelURL] {
            return node.id
        }
        // Fallback: walk up to find any match
        var currentURL = url.deletingLastPathComponent()
        while currentURL.path != rootURL.path {
            if let node = nodeByURL[currentURL] {
                return node.id
            }
            currentURL = currentURL.deletingLastPathComponent()
        }
        return nodeByURL[rootURL]?.id
    }

    private func relativePath(for url: URL) -> String? {
        guard let rootURL else { return nil }
        let rootPath = rootURL.path
        let path = url.path
        guard path.hasPrefix(rootPath) else { return nil }
        let relative = path.dropFirst(rootPath.count)
        if relative.isEmpty { return "." }
        if relative.hasPrefix("/") {
            return String(relative.dropFirst())
        }
        return String(relative)
    }

    // MARK: - Tree Indexing (delegated to TreeIndexer)

    private func buildFocusMap(root: FileNode) -> [URL: UUID] {
        TreeIndexer.buildFocusMap(root: root)
    }

    private func buildNodeIDMap(root: FileNode) -> [UUID: FileNode] {
        TreeIndexer.buildNodeByID(root: root)
    }

    private func buildNodeURLMap(root: FileNode) -> [URL: FileNode] {
        TreeIndexer.buildNodeByURL(root: root)
    }

    private func displayType(_ type: FileNode.NodeType) -> String {
        switch type {
        case .file:
            return "File"
        case .folder:
            return "Folder"
        case .symlink:
            return "Symlink"
        }
    }

    private func parentURL() -> URL? {
        guard let rootURL else { return nil }
        let parent = rootURL.deletingLastPathComponent()
        return parent.path == rootURL.path ? nil : parent
    }

    private func defaultRootURL() -> URL? {
        let home = FileManager.default.homeDirectoryForCurrentUser
        return home.appendingPathComponent("projects", isDirectory: true)
    }

    func isDirectory(_ url: URL) -> Bool {
        var isDirectory: ObjCBool = false
        FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory)
        return isDirectory.boolValue
    }

    private func promptForName(title: String, message: String, placeholder: String, defaultValue: String? = nil) -> String? {
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = message
        let textField = NSTextField(frame: NSRect(x: 0, y: 0, width: 320, height: 24))
        textField.placeholderString = placeholder
        if let defaultValue {
            textField.stringValue = defaultValue
        }
        alert.accessoryView = textField
        alert.addButton(withTitle: "OK")
        alert.addButton(withTitle: "Cancel")
        let response = alert.runModal()
        guard response == .alertFirstButtonReturn else { return nil }
        let name = textField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        return name.isEmpty ? nil : name
    }

    private func presentError(_ error: Error) {
        let alert = NSAlert(error: error)
        alert.runModal()
    }
}
