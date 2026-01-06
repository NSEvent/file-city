import Foundation

final class DirectoryScanner {
    struct ScanResult {
        let root: FileNode
        let nodeCount: Int
    }

    func scan(url: URL, maxDepth: Int, maxNodes: Int) async throws -> ScanResult {
        var count = 0
        let root = try scanNode(url: url, depth: 0, maxDepth: maxDepth, maxNodes: maxNodes, count: &count)
        return ScanResult(root: root, nodeCount: count)
    }

    private func scanNode(url: URL, depth: Int, maxDepth: Int, maxNodes: Int, count: inout Int) throws -> FileNode {
        if count >= maxNodes {
            return FileNode(
                id: UUID(),
                url: url,
                name: url.lastPathComponent,
                type: .folder,
                sizeBytes: 0,
                modifiedAt: Date(),
                children: [],
                isHidden: false,
                isGitRepo: false
            )
        }

        let keys: Set<URLResourceKey> = [.isDirectoryKey, .isSymbolicLinkKey, .fileSizeKey, .contentModificationDateKey, .isHiddenKey]
        let values = try url.resourceValues(forKeys: keys)
        let isDirectory = values.isDirectory ?? false
        let isSymlink = values.isSymbolicLink ?? false
        let modifiedAt = values.contentModificationDate ?? Date()
        var sizeBytes = Int64(values.fileSize ?? 0)
        let isHidden = values.isHidden ?? false
        let isGitRepo = isDirectory && isGitRepoDirectory(url)
        let type: FileNode.NodeType = isSymlink ? .symlink : (isDirectory ? .folder : .file)

        var children: [FileNode] = []
        count += 1

        if isDirectory && depth < maxDepth {
            let contents = (try? FileManager.default.contentsOfDirectory(at: url, includingPropertiesForKeys: Array(keys), options: [.skipsPackageDescendants])) ?? []
            for childURL in contents {
                if count >= maxNodes { break }
                let child = try scanNode(url: childURL, depth: depth + 1, maxDepth: maxDepth, maxNodes: maxNodes, count: &count)
                children.append(child)
            }
            sizeBytes = children.reduce(0) { $0 + $1.sizeBytes }
        }

        return FileNode(
            id: UUID(),
            url: url,
            name: url.lastPathComponent,
            type: type,
            sizeBytes: sizeBytes,
            modifiedAt: modifiedAt,
            children: children,
            isHidden: isHidden,
            isGitRepo: isGitRepo
        )
    }

    private func isGitRepoDirectory(_ url: URL) -> Bool {
        let gitURL = url.appendingPathComponent(".git", isDirectory: false)
        return FileManager.default.fileExists(atPath: gitURL.path)
    }
}
