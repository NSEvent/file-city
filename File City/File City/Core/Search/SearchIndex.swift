import Foundation

final class SearchIndex {
    private var index: [String: [URL]] = [:]

    func indexNode(_ node: FileNode) {
        let key = node.name.lowercased()
        index[key, default: []].append(node.url)
        for child in node.children {
            indexNode(child)
        }
    }

    func search(_ query: String) -> [URL] {
        let key = query.lowercased()
        return index[key] ?? []
    }
}
