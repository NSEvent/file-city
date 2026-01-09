import Foundation

/// Builds a FileNode tree from git ls-tree output for historical commits
final class GitTreeScanner {

    struct ScanResult {
        let root: FileNode
        let nodeCount: Int
    }

    /// Parses git ls-tree -r -l output and builds a FileNode tree
    /// - Parameters:
    ///   - output: Raw output from `git ls-tree -r -l <commit>`
    ///   - rootURL: The root URL to use as base for virtual file URLs
    ///   - maxDepth: Maximum depth to build (default 2, matching DirectoryScanner)
    /// - Returns: ScanResult with root FileNode and node count
    func buildTree(from output: String, rootURL: URL, maxDepth: Int = 2) -> ScanResult {
        let entries = parseGitLsTree(output)
        let (root, count) = buildHierarchy(from: entries, rootURL: rootURL, maxDepth: maxDepth)
        return ScanResult(root: root, nodeCount: count)
    }

    // MARK: - Parsing

    private struct GitEntry {
        let mode: String      // e.g., "100644" (file), "040000" (tree), "160000" (submodule)
        let path: String      // Full path relative to root
        let sizeBytes: Int64  // File size in bytes
    }

    /// Parses git ls-tree -r -l output into GitEntry array
    /// Format: "<mode> <type> <hash> <size>\t<path>"
    /// Example: "100644 blob abc123def456 12345\tsrc/main.swift"
    private func parseGitLsTree(_ output: String) -> [GitEntry] {
        var entries: [GitEntry] = []

        for line in output.split(separator: "\n") {
            let lineStr = String(line)

            // Split by tab to separate metadata from path
            guard let tabIndex = lineStr.firstIndex(of: "\t") else { continue }
            let metadata = String(lineStr[..<tabIndex])
            let path = String(lineStr[lineStr.index(after: tabIndex)...])

            // Parse metadata: "mode type hash size"
            let parts = metadata.split(separator: " ", omittingEmptySubsequences: true)
            guard parts.count >= 4 else { continue }

            let mode = String(parts[0])
            // parts[1] is type (blob/tree/commit), parts[2] is hash
            let sizeStr = String(parts[3])
            let sizeBytes = Int64(sizeStr) ?? 0

            entries.append(GitEntry(mode: mode, path: path, sizeBytes: sizeBytes))
        }

        return entries
    }

    // MARK: - Hierarchy Building

    /// Builds hierarchical FileNode tree from flat git entries
    private func buildHierarchy(from entries: [GitEntry], rootURL: URL, maxDepth: Int) -> (FileNode, Int) {
        // Group entries by their first path component
        var topLevelGroups: [String: [GitEntry]] = [:]

        for entry in entries {
            let components = entry.path.split(separator: "/", maxSplits: 1)
            guard let first = components.first else { continue }
            let key = String(first)

            if topLevelGroups[key] == nil {
                topLevelGroups[key] = []
            }
            topLevelGroups[key]?.append(entry)
        }

        // Build children for depth 1
        var children: [FileNode] = []
        var nodeCount = 1  // Count root

        for (name, groupEntries) in topLevelGroups {
            let childURL = rootURL.appendingPathComponent(name)

            // Check if this is a directory (has nested paths) or a file
            let hasNestedPaths = groupEntries.contains { entry in
                entry.path.contains("/") && entry.path.hasPrefix("\(name)/")
            }

            if hasNestedPaths || groupEntries.count > 1 {
                // This is a directory - build its children if depth allows
                let (childNode, childCount) = buildDirectoryNode(
                    name: name,
                    url: childURL,
                    entries: groupEntries,
                    currentDepth: 1,
                    maxDepth: maxDepth
                )
                children.append(childNode)
                nodeCount += childCount
            } else if let entry = groupEntries.first, !entry.path.contains("/") {
                // This is a top-level file
                let fileNode = FileNode(
                    id: UUID(),
                    url: childURL,
                    name: name,
                    type: .file,
                    sizeBytes: entry.sizeBytes,
                    modifiedAt: Date(),
                    children: [],
                    isHidden: name.hasPrefix("."),
                    isGitRepo: false,
                    isGitClean: false
                )
                children.append(fileNode)
                nodeCount += 1
            }
        }

        // Calculate total size
        let totalSize = children.reduce(Int64(0)) { $0 + $1.sizeBytes }

        // Build root node
        let root = FileNode(
            id: UUID(),
            url: rootURL,
            name: rootURL.lastPathComponent,
            type: .folder,
            sizeBytes: totalSize,
            modifiedAt: Date(),
            children: children,
            isHidden: false,
            isGitRepo: true,
            isGitClean: false
        )

        return (root, nodeCount)
    }

    /// Builds a directory FileNode with its children
    private func buildDirectoryNode(
        name: String,
        url: URL,
        entries: [GitEntry],
        currentDepth: Int,
        maxDepth: Int
    ) -> (FileNode, Int) {
        var children: [FileNode] = []
        var nodeCount = 1  // Count this directory

        if currentDepth < maxDepth {
            // Group entries by next path component
            var subGroups: [String: [GitEntry]] = [:]

            for entry in entries {
                // Remove the current directory prefix from path
                let pathWithoutPrefix: String
                if entry.path.hasPrefix("\(name)/") {
                    pathWithoutPrefix = String(entry.path.dropFirst(name.count + 1))
                } else {
                    pathWithoutPrefix = entry.path
                }

                let components = pathWithoutPrefix.split(separator: "/", maxSplits: 1)
                guard let first = components.first else { continue }
                let key = String(first)

                if subGroups[key] == nil {
                    subGroups[key] = []
                }
                // Store with modified path
                subGroups[key]?.append(GitEntry(
                    mode: entry.mode,
                    path: pathWithoutPrefix,
                    sizeBytes: entry.sizeBytes
                ))
            }

            // Build children
            for (childName, childEntries) in subGroups {
                let childURL = url.appendingPathComponent(childName)

                let hasNestedPaths = childEntries.contains { $0.path.contains("/") }

                if hasNestedPaths || childEntries.count > 1 {
                    // Subdirectory
                    let (childNode, childCount) = buildDirectoryNode(
                        name: childName,
                        url: childURL,
                        entries: childEntries,
                        currentDepth: currentDepth + 1,
                        maxDepth: maxDepth
                    )
                    children.append(childNode)
                    nodeCount += childCount
                } else if let entry = childEntries.first, !entry.path.contains("/") {
                    // File
                    let fileNode = FileNode(
                        id: UUID(),
                        url: childURL,
                        name: childName,
                        type: .file,
                        sizeBytes: entry.sizeBytes,
                        modifiedAt: Date(),
                        children: [],
                        isHidden: childName.hasPrefix("."),
                        isGitRepo: false,
                        isGitClean: false
                    )
                    children.append(fileNode)
                    nodeCount += 1
                }
            }
        }

        // Calculate directory size from children
        let totalSize = children.reduce(Int64(0)) { $0 + $1.sizeBytes }

        let node = FileNode(
            id: UUID(),
            url: url,
            name: name,
            type: .folder,
            sizeBytes: totalSize,
            modifiedAt: Date(),
            children: children,
            isHidden: name.hasPrefix("."),
            isGitRepo: false,
            isGitClean: false
        )

        return (node, nodeCount)
    }
}
