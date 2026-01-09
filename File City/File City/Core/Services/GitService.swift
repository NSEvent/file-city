import Foundation

/// Service for interacting with Git repositories
/// Provides status checking, commit history, and cleanliness detection
final class GitService {

    // MARK: - Types

    struct StatusResult {
        let output: String
        let error: String

        var isSuccess: Bool { error.isEmpty && !output.isEmpty }
    }

    // MARK: - Public Methods

    /// Check if a URL is inside a Git repository
    static func isGitRepository(at url: URL) -> Bool {
        let gitDir = url.appendingPathComponent(".git")
        return FileManager.default.fileExists(atPath: gitDir.path)
    }

    /// Check if a Git repository is clean (no uncommitted changes)
    /// This is a synchronous operation - call from background thread
    static func isRepositoryClean(at url: URL) -> Bool {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/git")
        process.arguments = ["-C", url.path, "status", "--porcelain=1", "-b"]

        let outputPipe = Pipe()
        process.standardOutput = outputPipe
        process.standardError = Pipe()

        do {
            try process.run()
        } catch {
            return false
        }

        process.waitUntilExit()
        guard process.terminationStatus == 0 else { return false }

        let data = outputPipe.fileHandleForReading.readDataToEndOfFile()
        let output = String(data: data, encoding: .utf8) ?? ""
        let lines = output.split(separator: "\n")

        // Clean repo has only the branch line (or nothing)
        return lines.count <= 1
    }

    /// Get Git status for a repository
    static func getStatus(at url: URL) -> StatusResult {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/git")
        process.arguments = ["-C", url.path, "status", "--porcelain=1", "-b"]

        let outputPipe = Pipe()
        let errorPipe = Pipe()
        process.standardOutput = outputPipe
        process.standardError = errorPipe

        do {
            try process.run()
        } catch {
            return StatusResult(output: "", error: error.localizedDescription)
        }

        process.waitUntilExit()
        let outputData = outputPipe.fileHandleForReading.readDataToEndOfFile()
        let errorData = errorPipe.fileHandleForReading.readDataToEndOfFile()
        let output = String(data: outputData, encoding: .utf8) ?? ""
        let error = String(data: errorData, encoding: .utf8) ?? ""

        guard process.terminationStatus == 0 else {
            return StatusResult(output: "", error: error)
        }

        return StatusResult(output: output, error: "")
    }

    /// Fetch commit history for a repository
    /// - Parameters:
    ///   - url: The repository URL
    ///   - limit: Maximum number of commits to fetch
    /// - Returns: Array of commits (newest first)
    static func fetchCommitHistory(at url: URL, limit: Int = Constants.Git.maxCommitHistory) async -> [GitCommit] {
        await withCheckedContinuation { continuation in
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/git")
            process.arguments = ["-C", url.path, "log", "--format=%H %ct %s", "-n", "\(limit)"]

            let outputPipe = Pipe()
            process.standardOutput = outputPipe
            process.standardError = Pipe()

            do {
                try process.run()
            } catch {
                continuation.resume(returning: [])
                return
            }

            process.waitUntilExit()
            guard process.terminationStatus == 0 else {
                continuation.resume(returning: [])
                return
            }

            let data = outputPipe.fileHandleForReading.readDataToEndOfFile()
            let output = String(data: data, encoding: .utf8) ?? ""

            let commits = parseCommitHistory(output)
            continuation.resume(returning: commits)
        }
    }

    /// Fetch the file tree at a specific commit
    /// - Parameters:
    ///   - commitHash: The commit hash
    ///   - url: The repository URL
    /// - Returns: Raw ls-tree output
    static func fetchTreeAtCommit(_ commitHash: String, at url: URL) async -> String? {
        await withCheckedContinuation { continuation in
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/git")
            process.arguments = ["-C", url.path, "ls-tree", "-r", "-l", commitHash]

            let outputPipe = Pipe()
            process.standardOutput = outputPipe
            process.standardError = Pipe()

            do {
                try process.run()
            } catch {
                continuation.resume(returning: nil)
                return
            }

            process.waitUntilExit()
            guard process.terminationStatus == 0 else {
                continuation.resume(returning: nil)
                return
            }

            let data = outputPipe.fileHandleForReading.readDataToEndOfFile()
            let output = String(data: data, encoding: .utf8)
            continuation.resume(returning: output)
        }
    }

    // MARK: - Status Formatting

    /// Format Git status lines for display
    static func formatStatusLines(for url: URL) -> [String] {
        let title = "\(url.lastPathComponent) (git)"

        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory),
              isDirectory.boolValue else {
            return [title, "Not a folder"]
        }

        let result = getStatus(at: url)

        guard result.isSuccess else {
            if result.error.isEmpty {
                return [title, "Git status unavailable"]
            }
            return [title, "Git status error", result.error]
        }

        let lines = result.output
            .split(separator: "\n")
            .map { String($0) }

        guard let first = lines.first else {
            return [title, "Git status unavailable"]
        }

        var statusLines: [String] = [title]

        // Parse branch line
        let branchLine = first.hasPrefix("## ") ? String(first.dropFirst(3)) : first
        statusLines.append(branchLine.isEmpty ? "Unknown branch" : branchLine)

        // Parse change lines
        let changes = lines.dropFirst()
        if changes.isEmpty {
            statusLines.append("Clean")
        } else {
            let formatted = changes.prefix(5).map { formatStatusLine($0) }
            statusLines.append(contentsOf: formatted)
        }

        return statusLines
    }

    /// Format a single status line for display
    static func formatStatusLine(_ line: String) -> String {
        guard line.count >= 3 else { return line }

        let status = String(line.prefix(2))
        let path = line.dropFirst(3)

        switch status {
        case "??":
            return "Untracked:\t\(path)"
        case " M":
            return "Modified:\t\(path)"
        case "M ":
            return "Staged:\t\(path)"
        case "A ":
            return "Added:\t\(path)"
        case " D":
            return "Deleted:\t\(path)"
        case "R ", "R?":
            return "Renamed:\t\(path)"
        default:
            return line
        }
    }

    // MARK: - Private Helpers

    private static func parseCommitHistory(_ output: String) -> [GitCommit] {
        var commits: [GitCommit] = []

        for line in output.split(separator: "\n") {
            let parts = line.split(separator: " ", maxSplits: 2)
            guard parts.count >= 2 else { continue }

            let hash = String(parts[0])
            let shortHash = String(hash.prefix(7))
            let timestamp = TimeInterval(parts[1]) ?? 0
            let subject = parts.count > 2 ? String(parts[2]) : ""

            let commit = GitCommit(
                id: hash,
                shortHash: shortHash,
                timestamp: Date(timeIntervalSince1970: timestamp),
                subject: subject
            )
            commits.append(commit)
        }

        return commits
    }
}

// MARK: - Batch Operations

extension GitService {

    /// Check cleanliness for multiple repositories in parallel
    /// Returns a dictionary mapping node IDs to cleanliness status
    static func checkCleanliness(for nodes: [UUID: FileNode]) async -> [UUID: Bool] {
        await withTaskGroup(of: (UUID, Bool).self) { group in
            var results: [UUID: Bool] = [:]
            results.reserveCapacity(nodes.count)

            for (id, node) in nodes where node.isGitRepo {
                group.addTask {
                    let isClean = GitService.isRepositoryClean(at: node.url)
                    return (id, isClean)
                }
            }

            for await (id, isClean) in group {
                results[id] = isClean
            }

            return results
        }
    }
}
