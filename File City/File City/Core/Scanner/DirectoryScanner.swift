import Foundation

final class DirectoryScanner {
    struct ScanResult {
        let root: FileNode
        let nodeCount: Int
    }

    func scan(url: URL) async throws -> ScanResult {
        let root = FileNode(
            id: UUID(),
            url: url,
            name: url.lastPathComponent,
            type: .folder,
            sizeBytes: 0,
            modifiedAt: Date(),
            children: [],
            isHidden: false
        )
        return ScanResult(root: root, nodeCount: 1)
    }
}
