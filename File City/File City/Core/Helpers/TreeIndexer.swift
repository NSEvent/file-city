import Foundation

/// Generic tree indexing utilities for FileNode trees
/// Eliminates duplicate recursive traversal patterns
enum TreeIndexer {

    // MARK: - Generic Tree Indexing

    /// Build a map from a FileNode tree using custom key and value extractors
    /// - Parameters:
    ///   - root: The root node to traverse
    ///   - keyExtractor: Function to extract the key from a node
    ///   - valueExtractor: Function to extract the value from a node
    /// - Returns: Dictionary mapping keys to values for all nodes
    static func buildMap<K: Hashable, V>(
        root: FileNode,
        keyExtractor: (FileNode) -> K,
        valueExtractor: (FileNode) -> V
    ) -> [K: V] {
        var map: [K: V] = [:]
        traverse(node: root, map: &map, keyExtractor: keyExtractor, valueExtractor: valueExtractor)
        return map
    }

    private static func traverse<K: Hashable, V>(
        node: FileNode,
        map: inout [K: V],
        keyExtractor: (FileNode) -> K,
        valueExtractor: (FileNode) -> V
    ) {
        map[keyExtractor(node)] = valueExtractor(node)
        for child in node.children {
            traverse(node: child, map: &map, keyExtractor: keyExtractor, valueExtractor: valueExtractor)
        }
    }

    // MARK: - Specialized Builders (Common Patterns)

    /// Build a map from URL to node ID
    static func buildNodeIDByURL(root: FileNode) -> [URL: UUID] {
        buildMap(root: root, keyExtractor: \.url, valueExtractor: \.id)
    }

    /// Build a map from node ID to FileNode
    static func buildNodeByID(root: FileNode) -> [UUID: FileNode] {
        buildMap(root: root, keyExtractor: \.id, valueExtractor: { $0 })
    }

    /// Build a map from URL to FileNode
    static func buildNodeByURL(root: FileNode) -> [URL: FileNode] {
        buildMap(root: root, keyExtractor: \.url, valueExtractor: { $0 })
    }

    /// Build a focus map where all descendants map to their first-level ancestor's ID
    /// This is used for selection highlighting - selecting a deep file highlights its top-level building
    static func buildFocusMap(root: FileNode) -> [URL: UUID] {
        var map: [URL: UUID] = [:]
        for child in root.children {
            indexFocusURLs(node: child, focusID: child.id, map: &map)
        }
        return map
    }

    private static func indexFocusURLs(node: FileNode, focusID: UUID, map: inout [URL: UUID]) {
        map[node.url] = focusID
        for child in node.children {
            indexFocusURLs(node: child, focusID: focusID, map: &map)
        }
    }

    // MARK: - Tree Statistics

    /// Count all nodes in a tree
    static func countNodes(_ node: FileNode) -> Int {
        1 + node.children.reduce(0) { $0 + countNodes($1) }
    }

    /// Find a node by URL in a tree
    static func findNode(url: URL, in root: FileNode) -> FileNode? {
        if root.url == url { return root }
        for child in root.children {
            if let found = findNode(url: url, in: child) {
                return found
            }
        }
        return nil
    }

    /// Get all URLs in a tree
    static func allURLs(root: FileNode) -> Set<URL> {
        var urls = Set<URL>()
        collectURLs(node: root, urls: &urls)
        return urls
    }

    private static func collectURLs(node: FileNode, urls: inout Set<URL>) {
        urls.insert(node.url)
        for child in node.children {
            collectURLs(node: child, urls: &urls)
        }
    }
}
