import AppKit
import Combine
import Foundation

@MainActor
final class AppState: ObservableObject {
    @Published var rootURL: URL?
    @Published var nodeCount: Int = 0
    @Published var blocks: [CityBlock] = []
    @Published var searchQuery: String = ""
    @Published var searchResults: [URL] = []
    @Published var selectedURL: URL?
    @Published var selectedFocusNodeID: UUID?
    @Published var hoveredURL: URL?
    @Published var hoveredNodeID: UUID?
    @Published var hoveredGitStatus: [String]?

    private let scanner = DirectoryScanner()
    private let mapper = CityMapper()
    private let searchIndex = SearchIndex()
    private let pinStore = PinStore()
    private let rescanSubject = PassthroughSubject<Void, Never>()
    private var focusNodeIDByURL: [URL: UUID] = [:]
    private var nodeByID: [UUID: FileNode] = [:]
    private var nodeByURL: [URL: FileNode] = [:]
    private var watcher: FSEventsWatcher?
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

        // Skip automatic setup if running tests to prevent hangs
        if ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] == nil {
            if let defaultRoot = defaultRootURL() {
                rootURL = defaultRoot
                scanRoot()
                startWatchingRoot()
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
            scanRoot()
            startWatchingRoot()
        }
    }

    func scanRoot() {
        guard let rootURL else { return }
        Task {
            do {
                let result = try await scanner.scan(url: rootURL, maxDepth: 2, maxNodes: LayoutRules.default.maxNodes)
                nodeCount = result.nodeCount
                searchIndex.reset()
                searchIndex.indexNode(result.root)
                blocks = mapper.map(root: result.root, rules: .default, pinStore: pinStore)
                focusNodeIDByURL = buildFocusMap(root: result.root)
                nodeByID = buildNodeIDMap(root: result.root)
                nodeByURL = buildNodeURLMap(root: result.root)
                selectedFocusNodeID = selectedURL.flatMap { focusNodeIDByURL[$0] }
            } catch {
                nodeCount = 0
                blocks = []
                searchResults = []
                focusNodeIDByURL = [:]
                nodeByID = [:]
                nodeByURL = [:]
                selectedFocusNodeID = nil
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
            }
        }
    }

    func focus(_ url: URL) {
        selectedURL = url
        selectedFocusNodeID = focusNodeIDByURL[url]
    }

    func enter(_ url: URL) {
        focus(url)
        guard isDirectory(url) else { return }
        rootURL = url
        hoveredURL = nil
        hoveredNodeID = nil
        hoveredGitStatus = nil
        selectedURL = nil
        selectedFocusNodeID = nil
        scanRoot()
        startWatchingRoot()
    }

    func goToParent() {
        guard let parent = parentURL() else { return }
        rootURL = parent
        hoveredURL = nil
        hoveredNodeID = nil
        hoveredGitStatus = nil
        selectedURL = nil
        selectedFocusNodeID = nil
        scanRoot()
        startWatchingRoot()
    }

    func canGoToParent() -> Bool {
        parentURL() != nil
    }

    func url(for nodeID: UUID) -> URL? {
        nodeByID[nodeID]?.url
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
        let output = runGitStatus(at: url)
        guard !output.isEmpty else {
            return [title, "Git status unavailable"]
        }
        let lines = output
            .split(separator: "\n")
            .map { String($0) }
        guard let first = lines.first else {
            return [title, "Git status unavailable"]
        }
        var result: [String] = [title]
        let branchLine = first.hasPrefix("## ") ? String(first.dropFirst(3)) : first
        result.append(branchLine.isEmpty ? "Unknown branch" : branchLine)
        let changes = lines.dropFirst()
        if changes.isEmpty {
            result.append("Clean")
        } else {
            result.append(contentsOf: changes.prefix(5))
        }
        return result
    }

    private func runGitStatus(at url: URL) -> String {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        process.arguments = ["git", "-C", url.path, "status", "--porcelain=1", "-b"]
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = Pipe()
        do {
            try process.run()
        } catch {
            return ""
        }
        process.waitUntilExit()
        guard process.terminationStatus == 0 else { return "" }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        return String(data: data, encoding: .utf8) ?? ""
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

    private func startWatchingRoot() {
        guard let rootURL else { return }
        watcher?.stop()
        let watcher = FSEventsWatcher(url: rootURL)
        watcher.onChange = { [weak self] in
            self?.rescanSubject.send(())
        }
        watcher.start()
        self.watcher = watcher
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
        // Point to the source directory to show AppShell and Core
        let home = FileManager.default.homeDirectoryForCurrentUser
        let url = home.appendingPathComponent("projects/file-city/File City/File City", isDirectory: true)
        var isDirectory: ObjCBool = false
        if FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory), isDirectory.boolValue {
            return url
        }
        return home.appendingPathComponent("projects", isDirectory: true)
    }

    private func isDirectory(_ url: URL) -> Bool {
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
