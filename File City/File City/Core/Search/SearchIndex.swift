import Foundation

final class SearchIndex {
    private var index: [String: [URL]] = [:]

    func reset() {
        index.removeAll()
    }

    func indexNode(_ node: FileNode) {
        let key = node.name.lowercased()
        index[key, default: []].append(node.url)
        for child in node.children {
            indexNode(child)
        }
    }

    func search(_ query: String) -> [URL] {
        let key = query.lowercased()
        guard !key.isEmpty else { return [] }
        return index
            .filter { $0.key.contains(key) }
            .flatMap { $0.value }
            .sorted { $0.path < $1.path }
    }
}
