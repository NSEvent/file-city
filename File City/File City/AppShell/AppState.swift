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
    @Published var selectedURL: URL?
    @Published var selectedFocusNodeID: UUID?
    @Published var hoveredURL: URL?
    @Published var hoveredNodeID: UUID?
    @Published var hoveredGitStatus: [String]?
    @Published var hoveredBeaconNodeID: UUID?
    @Published var hoveredBeaconURL: URL?
    @Published var activityInfoLines: [String]?
    @Published private(set) var activityVersion: UInt = 0

    private let scanner = DirectoryScanner()
    private let mapper = CityMapper()
    private let searchIndex = SearchIndex()
    private let pinStore = PinStore()
    private let rescanSubject = PassthroughSubject<Void, Never>()
    let fileWriteSubject = PassthroughSubject<UUID, Never>()
    let fileReadSubject = PassthroughSubject<UUID, Never>()
    private var gitStatusTask: Task<Void, Never>?
    private var gitCleanByPath: [String: Bool] = [:]
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
                blocks = mapper.map(root: result.root, rules: .default, pinStore: pinStore)
                if autoFit {
                    pendingAutoFit = true
                }
                focusNodeIDByURL = buildFocusMap(root: result.root)
                nodeByID = buildNodeIDMap(root: result.root)
                nodeByURL = buildNodeURLMap(root: result.root)
                selectedFocusNodeID = selectedURL.flatMap { focusNodeIDByURL[$0] }
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
                selectedFocusNodeID = nil
                hoveredNodeID = nil
                hoveredBeaconNodeID = nil
                hoveredBeaconURL = nil
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
                blocks = mapper.map(root: result.root, rules: .default, pinStore: pinStore)
                focusNodeIDByURL = buildFocusMap(root: result.root)
                nodeByID = buildNodeIDMap(root: result.root)
                nodeByURL = buildNodeURLMap(root: result.root)
                selectedFocusNodeID = selectedURL.flatMap { focusNodeIDByURL[$0] }
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
        selectedURL = url
        selectedFocusNodeID = focusNodeIDByURL[url]
    }

    /// Select a file/directory without navigating (for single-click)
    func select(_ url: URL) {
        selectedURL = url
        selectedFocusNodeID = focusNodeIDByURL[url]
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
        selectedURL = nil
        selectedFocusNodeID = nil
        scanRoot(autoFit: true)
        startWatchingRoot()
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
        selectedURL = nil
        selectedFocusNodeID = nil
        scanRoot(autoFit: true)
        startWatchingRoot()
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
        let title = "\(url.lastPathComponent) (git)"
        guard isDirectory(url) else {
            return [title, "Not a folder"]
        }
        let result = runGitStatus(at: url)
        guard !result.output.isEmpty else {
            if result.error.isEmpty {
                return [title, "Git status unavailable"]
            }
            return [title, "Git status error", result.error]
        }
        let lines = result.output
            .split(separator: "\n")
            .map { String($0) }
        guard let first = lines.first else {
            return [title, "Git status unavailable"]
        }
        var linesResult: [String] = [title]
        let branchLine = first.hasPrefix("## ") ? String(first.dropFirst(3)) : first
        linesResult.append(branchLine.isEmpty ? "Unknown branch" : branchLine)
        let changes = lines.dropFirst()
        if changes.isEmpty {
            linesResult.append("Clean")
        } else {
            let formatted = changes.prefix(5).map { formatGitStatusLine($0) }
            linesResult.append(contentsOf: formatted)
        }
        return linesResult
    }

    private func formatGitStatusLine(_ line: String) -> String {
        guard line.count >= 3 else { return line }
        let status = String(line.prefix(2))
        let path = line.dropFirst(3)
        if status == "??" {
            return "Untracked:\t\(path)"
        }
        if status == " M" {
            return "Modified:\t\(path)"
        }
        if status == "M " {
            return "Staged:\t\(path)"
        }
        if status == "A " {
            return "Added:\t\(path)"
        }
        if status == " D" {
            return "Deleted:\t\(path)"
        }
        if status == "R " || status == "R?" {
            return "Renamed:\t\(path)"
        }
        return line
    }

    private func runGitStatus(at url: URL) -> (output: String, error: String) {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/git")
        process.arguments = ["-C", url.path, "status", "--porcelain=1", "-b"]
        let outputPipe = Pipe()
        let errorPipe = Pipe()
        process.standardOutput = outputPipe
        process.standardError = errorPipe
        do {
            try process.run()
        } catch {
            return ("", error.localizedDescription)
        }
        process.waitUntilExit()
        let outputData = outputPipe.fileHandleForReading.readDataToEndOfFile()
        let errorData = errorPipe.fileHandleForReading.readDataToEndOfFile()
        let output = String(data: outputData, encoding: .utf8) ?? ""
        let error = String(data: errorData, encoding: .utf8) ?? ""
        guard process.terminationStatus == 0 else { return ("", error) }
        return (output, error)
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
                results[node.id] = AppState.isGitRepoClean(url: node.url)
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

    nonisolated private static func isGitRepoClean(url: URL) -> Bool {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/git")
        process.arguments = ["-C", url.path, "status", "--porcelain=1", "-b"]
        let outputPipe = Pipe()
        process.standardOutput = outputPipe
        process.standardError = Pipe()
        do {
            try process.run()
        } catch {
            return false
        }
        process.waitUntilExit()
        guard process.terminationStatus == 0 else { return false }
        let data = outputPipe.fileHandleForReading.readDataToEndOfFile()
        let output = String(data: data, encoding: .utf8) ?? ""
        let lines = output.split(separator: "\n")
        return lines.count <= 1
    }


    func actionContainerURL() -> URL? {
        guard let rootURL else { return nil }
        guard let selectedURL else { return rootURL }
        var isDirectory: ObjCBool = false
        if FileManager.default.fileExists(atPath: selectedURL.path, isDirectory: &isDirectory), isDirectory.boolValue {
            return selectedURL
        }
        return selectedURL.deletingLastPathComponent()
    }

    func createFolder() {
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
        guard let selectedURL else { return }
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
        guard let selectedURL else { return }
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.prompt = "Move"
        if panel.runModal() == .OK, let destFolder = panel.url {
            let destination = destFolder.appendingPathComponent(selectedURL.lastPathComponent, isDirectory: isDirectory(selectedURL))
            do {
                try FileActions().moveItem(from: selectedURL, to: destination)
                focus(destination)
                rescanSubject.send(())
            } catch {
                presentError(error)
            }
        }
    }

    func trashSelected() {
        guard let selected = selectedURL else { return }
        let alert = NSAlert()
        alert.messageText = "Move to Trash?"
        alert.informativeText = selected.lastPathComponent
        alert.addButton(withTitle: "Trash")
        alert.addButton(withTitle: "Cancel")
        let response = alert.runModal()
        guard response == .alertFirstButtonReturn else { return }
        do {
            try FileActions().moveToTrash(selected)
            selectedURL = nil
            selectedFocusNodeID = nil
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
        let targetNodeID = hoveredNodeID ?? hoveredBeaconNodeID ?? selectedFocusNodeID
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
        let now = activityNow()
        if now < ignoreActivityUntil { return }
        // Ignore internal git operations
        if url.path.contains("/.git/") || url.path.hasSuffix("/.git") { return }
        
        // Don't overwrite fs_usage events which have more detail
        if let existing = activityByURL[url], now - existing.startedAt < 0.3 {
            return
        }
        activityByURL[url] = NodeActivityPulse(
            kind: kind,
            startedAt: now,
            processName: "FSEvents",
            url: url
        )
        if kind == .write {
            if let nodeID = resolveActivityNodeID(url: url) {
                fileWriteSubject.send(nodeID)
            }
        } else if kind == .read {
            if let nodeID = resolveActivityNodeID(url: url) {
                fileReadSubject.send(nodeID)
            }
        }
        activityVersion &+= 1
    }

    private func handleActivityEvent(_ event: FileActivityEvent) {
        let now = activityNow()
        if now < ignoreActivityUntil { return }
        // Ignore internal git operations
        if event.url.path.contains("/.git/") || event.url.path.hasSuffix("/.git") { return }
        
        activityByURL[event.url] = NodeActivityPulse(
            kind: event.kind,
            startedAt: now,
            processName: event.processName,
            url: event.url
        )
        if event.kind == .write {
            if let nodeID = resolveActivityNodeID(url: event.url) {
                fileWriteSubject.send(nodeID)
            }
        } else if event.kind == .read {
            if let nodeID = resolveActivityNodeID(url: event.url) {
                fileReadSubject.send(nodeID)
            }
        }
        activityVersion &+= 1
        let verb = event.kind == .write ? "Write" : "Read"
        let pathLine = relativePath(for: event.url) ?? event.url.lastPathComponent
        activityInfoLines = [
            "\(event.processName) • \(verb)",
            pathLine
        ]
        activityInfoExpiresAt = now + 2.0
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

    private func buildFocusMap(root: FileNode) -> [URL: UUID] {
        var map: [URL: UUID] = [:]
        for child in root.children {
            indexFocusURLs(node: child, focusID: child.id, map: &map)
        }
        return map
    }

    private func indexFocusURLs(node: FileNode, focusID: UUID, map: inout [URL: UUID]) {
        map[node.url] = focusID
        for child in node.children {
            indexFocusURLs(node: child, focusID: focusID, map: &map)
        }
    }

    private func buildNodeIDMap(root: FileNode) -> [UUID: FileNode] {
        var map: [UUID: FileNode] = [:]
        indexNodeIDMap(node: root, map: &map)
        return map
    }

    private func buildNodeURLMap(root: FileNode) -> [URL: FileNode] {
        var map: [URL: FileNode] = [:]
        indexNodeURLMap(node: root, map: &map)
        return map
    }

    private func indexNodeIDMap(node: FileNode, map: inout [UUID: FileNode]) {
        map[node.id] = node
        for child in node.children {
            indexNodeIDMap(node: child, map: &map)
        }
    }

    private func indexNodeURLMap(node: FileNode, map: inout [URL: FileNode]) {
        map[node.url] = node
        for child in node.children {
            indexNodeURLMap(node: child, map: &map)
        }
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
