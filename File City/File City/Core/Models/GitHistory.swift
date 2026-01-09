import Foundation

/// Represents a single commit in the git history
struct GitCommit: Identifiable, Hashable {
    let id: String          // Full SHA hash
    let shortHash: String   // First 7 chars
    let timestamp: Date
    let subject: String     // Commit message first line

    var displayDate: String {
        let formatter = DateFormatter()
        formatter.dateStyle = .short
        formatter.timeStyle = .short
        return formatter.string(from: timestamp)
    }
}

/// Represents the time travel state
enum TimeTravelMode: Equatable {
    case live                      // Current filesystem (rightmost position)
    case historical(GitCommit)     // Viewing a specific commit

    var isLive: Bool {
        if case .live = self { return true }
        return false
    }

    var commit: GitCommit? {
        if case .historical(let commit) = self { return commit }
        return nil
    }
}
