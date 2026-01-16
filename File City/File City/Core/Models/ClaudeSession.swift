import Foundation

/// Represents a running Claude Code CLI session
struct ClaudeSession: Identifiable, Equatable {
    let id: UUID
    let workingDirectory: URL
    let spawnTime: Date
    var state: SessionState
    var ptyPath: String?
    var isSelected: Bool = false
    var outputHistory: [String] = []
    var lastKnownSnapshot: String = ""

    enum SessionState: Int32, Equatable {
        case launching = 0   // Just spawned, waiting for first output
        case idle = 1        // Waiting for user input
        case generating = 2  // Actively producing output
        case exiting = 3     // Process terminating
    }

    init(id: UUID = UUID(), workingDirectory: URL, spawnTime: Date = Date(), state: SessionState = .launching, ptyPath: String? = nil) {
        self.id = id
        self.workingDirectory = workingDirectory
        self.spawnTime = spawnTime
        self.state = state
        self.ptyPath = ptyPath
        self.isSelected = false
        self.outputHistory = []
        self.lastKnownSnapshot = ""
    }
}
