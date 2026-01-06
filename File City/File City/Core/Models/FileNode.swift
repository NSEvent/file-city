import Foundation

struct FileNode: Identifiable, Hashable {
    enum NodeType {
        case file
        case folder
        case symlink
    }

    let id: UUID
    let url: URL
    let name: String
    let type: NodeType
    let sizeBytes: Int64
    let modifiedAt: Date
    var children: [FileNode]
    var isHidden: Bool
    var isGitRepo: Bool
    var isGitClean: Bool
}
