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

    private let scanner = DirectoryScanner()
    private let mapper = CityMapper()
    private let searchIndex = SearchIndex()
    private let pinStore = PinStore()
    private let rescanSubject = PassthroughSubject<Void, Never>()
    private var focusNodeIDByURL: [URL: UUID] = [:]
    private var watcher: FSEventsWatcher?
    private var cancellables: Set<AnyCancellable> = []

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
                selectedFocusNodeID = selectedURL.flatMap { focusNodeIDByURL[$0] }
            } catch {
                nodeCount = 0
                blocks = []
                searchResults = []
                focusNodeIDByURL = [:]
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
                selectedFocusNodeID = selectedURL.flatMap { focusNodeIDByURL[$0] }
            }
        }
    }

    func focus(_ url: URL) {
        selectedURL = url
        selectedFocusNodeID = focusNodeIDByURL[url]
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
