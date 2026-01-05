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

    private let scanner = DirectoryScanner()
    private let mapper = CityMapper()
    private let searchIndex = SearchIndex()
    private let pinStore = PinStore()
    private var cancellables: Set<AnyCancellable> = []

    init() {
        $searchQuery
            .debounce(for: .milliseconds(150), scheduler: DispatchQueue.main)
            .sink { [weak self] query in
                self?.searchResults = self?.searchIndex.search(query) ?? []
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
            } catch {
                nodeCount = 0
                blocks = []
                searchResults = []
            }
        }
    }

    func open(_ url: URL) {
        selectedURL = url
        FileActions().open(url)
    }

    func reveal(_ url: URL) {
        selectedURL = url
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
            }
        }
    }

    func pinnedURLs() -> [URL] {
        pinStore.allPinnedURLs()
    }
}
