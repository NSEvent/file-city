import Foundation
import Combine

/// Manages Git time travel functionality
/// Handles loading historical trees and caching
@MainActor
final class TimeTravelManager: ObservableObject {

    // MARK: - Published State

    @Published private(set) var mode: TimeTravelMode = .live
    @Published private(set) var commitHistory: [GitCommit] = []
    @Published var sliderPosition: Double = 1.0  // 0=oldest, 1=newest/live
    @Published private(set) var isRootGitRepo: Bool = false

    // MARK: - Dependencies

    private let gitTreeScanner = GitTreeScanner()

    // MARK: - Internal State

    private var historicalTreeCache: [String: FileNode] = [:]
    private var lastLoadedCommitID: String?
    private var loadTask: Task<Void, Never>?
    private var rootURL: URL?

    // MARK: - Callbacks

    /// Called when a historical tree is loaded and should be applied
    var onTreeLoaded: ((FileNode) -> Void)?

    /// Called when returning to live mode
    var onReturnToLive: (() -> Void)?

    // MARK: - Public Methods

    /// Set the root URL and load Git history if available
    func setRoot(_ url: URL?) {
        rootURL = url
        historicalTreeCache.removeAll()
        lastLoadedCommitID = nil
        mode = .live
        sliderPosition = 1.0

        guard let url else {
            isRootGitRepo = false
            commitHistory = []
            return
        }

        isRootGitRepo = GitService.isGitRepository(at: url)

        guard isRootGitRepo else {
            commitHistory = []
            return
        }

        Task {
            let history = await GitService.fetchCommitHistory(at: url, limit: Constants.Git.maxCommitHistory)
            commitHistory = history
        }
    }

    /// Clear all cached state
    func clearCache() {
        historicalTreeCache.removeAll()
        lastLoadedCommitID = nil
    }

    /// Update slider position during drag
    /// - Parameters:
    ///   - position: New slider position (0=oldest, 1=newest)
    ///   - live: If true, immediately load the historical tree
    func updatePosition(_ position: Double, live: Bool = false) {
        guard !commitHistory.isEmpty else { return }

        sliderPosition = position
        let previousMode = mode

        if position >= 0.99 {
            // Live mode
            mode = .live

            if live && !previousMode.isLive {
                lastLoadedCommitID = nil
                onReturnToLive?()
            }
        } else {
            // Historical mode - map position to commit index
            let invertedPosition = 1.0 - position
            let index = Int(invertedPosition * Double(commitHistory.count - 1))
            let clampedIndex = max(0, min(commitHistory.count - 1, index))
            let commit = commitHistory[clampedIndex]

            mode = .historical(commit)

            // Load tree if live scrubbing and commit changed
            if live && commit.id != lastLoadedCommitID {
                lastLoadedCommitID = commit.id
                loadHistoricalTree(commit: commit)
            }
        }
    }

    /// Commit to current time travel position
    func commitToPosition() {
        switch mode {
        case .live:
            onReturnToLive?()

        case .historical(let commit):
            if let cachedTree = historicalTreeCache[commit.id] {
                onTreeLoaded?(cachedTree)
            } else {
                loadHistoricalTree(commit: commit)
            }
        }
    }

    /// Return to live mode
    func returnToLive() {
        sliderPosition = 1.0
        mode = .live
        lastLoadedCommitID = nil
        onReturnToLive?()
    }

    /// Get the current historical commit (if any)
    var currentCommit: GitCommit? {
        mode.commit
    }

    /// Check if currently in live mode
    var isLive: Bool {
        mode.isLive
    }

    // MARK: - Private Methods

    private func loadHistoricalTree(commit: GitCommit) {
        // Cancel any pending load
        loadTask?.cancel()

        // Check cache first
        if let cachedTree = historicalTreeCache[commit.id] {
            onTreeLoaded?(cachedTree)
            return
        }

        // Fetch in background
        loadTask = Task {
            guard let rootURL else { return }

            let tree = await fetchAndBuildTree(commit: commit, rootURL: rootURL)

            // Verify we're still on this commit
            guard !Task.isCancelled,
                  case .historical(let currentCommit) = mode,
                  currentCommit.id == commit.id,
                  let tree else { return }

            historicalTreeCache[commit.id] = tree
            onTreeLoaded?(tree)
        }
    }

    private func fetchAndBuildTree(commit: GitCommit, rootURL: URL) async -> FileNode? {
        guard let output = await GitService.fetchTreeAtCommit(commit.id, at: rootURL) else {
            return nil
        }

        let result = gitTreeScanner.buildTree(
            from: output,
            rootURL: rootURL,
            maxDepth: Constants.Scanning.maxDepth
        )

        return result.root
    }
}

// MARK: - Convenience Extensions

extension TimeTravelManager {
    /// Get formatted commit info for display
    func commitInfo(for position: Double) -> String? {
        guard !commitHistory.isEmpty, position < 0.99 else { return nil }

        let invertedPosition = 1.0 - position
        let index = Int(invertedPosition * Double(commitHistory.count - 1))
        let clampedIndex = max(0, min(commitHistory.count - 1, index))
        let commit = commitHistory[clampedIndex]

        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
        let relativeDate = formatter.localizedString(for: commit.timestamp, relativeTo: Date())

        return "\(commit.shortHash) - \(relativeDate)"
    }
}
