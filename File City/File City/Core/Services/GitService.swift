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

    /// Maximum number of repos to count LOC for (for performance)
    private static let maxReposToCount = 20

    /// Count lines of code for multiple repositories (limited concurrency)
    /// Returns a dictionary mapping node IDs to LOC counts
    static func countLinesOfCode(for nodes: [UUID: FileNode]) async -> [UUID: Int] {
        let gitRepos = nodes.filter { $0.value.isGitRepo }.prefix(maxReposToCount)
        var results: [UUID: Int] = [:]
        results.reserveCapacity(gitRepos.count)

        // Process sequentially to avoid overwhelming the system
        for (id, node) in gitRepos {
            if Task.isCancelled { break }
            let loc = countLinesOfCode(at: node.url)
            results[id] = loc
        }

        return results
    }
}

// MARK: - Lines of Code

extension GitService {

    /// Common source code file extensions to count
    private static let sourceExtensions: Set<String> = [
        // Swift/Apple
        "swift", "m", "mm", "h",
        // Web
        "js", "jsx", "ts", "tsx", "vue", "svelte",
        "html", "css", "scss", "sass", "less",
        // Systems
        "c", "cpp", "cc", "cxx", "hpp", "rs", "go",
        // JVM
        "java", "kt", "kts", "scala", "groovy",
        // Scripting
        "py", "rb", "php", "pl", "sh", "bash", "zsh",
        // Data/Config (often contains logic)
        "json", "yaml", "yml", "toml",
        // Other
        "sql", "graphql", "proto", "lua", "r", "dart", "ex", "exs",
        "cs", "fs", "vb", "clj", "cljs", "elm", "hs", "ml", "mli",
        // Metal/Shaders
        "metal", "glsl", "hlsl", "vert", "frag"
    ]

    /// Maximum directory depth for LOC counting (to avoid slow scans)
    private static let maxRecurseDepth = 5

    /// Maximum number of files to count (for performance)
    private static let maxFilesToCount = 100

    /// Directories to always exclude when counting LOC
    private static let excludedDirectories: Set<String> = [
        "node_modules", ".git", "vendor", "Pods", "Carthage",
        "build", "Build", "DerivedData", ".build",
        "dist", "out", "target", ".next", ".nuxt",
        "__pycache__", ".pytest_cache", "venv", ".venv",
        "coverage", ".coverage", "htmlcov"
    ]

    /// Count lines of code in a git repository
    /// Uses git ls-files to respect .gitignore
    static func countLinesOfCode(at url: URL) -> Int {
        // Use git ls-files to get tracked files (respects .gitignore)
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/git")
        process.arguments = ["-C", url.path, "ls-files"]
        process.currentDirectoryURL = url

        let outputPipe = Pipe()
        process.standardOutput = outputPipe
        process.standardError = Pipe()

        do {
            try process.run()
        } catch {
            // Fallback to directory scan if git fails
            return countLinesOfCodeFallback(at: url)
        }

        process.waitUntilExit()
        guard process.terminationStatus == 0 else {
            return countLinesOfCodeFallback(at: url)
        }

        let data = outputPipe.fileHandleForReading.readDataToEndOfFile()
        guard let output = String(data: data, encoding: .utf8) else { return 0 }

        let files = output.split(separator: "\n").map { String($0) }
        return countLinesInFiles(files, baseURL: url)
    }

    /// Fallback LOC counting when git ls-files isn't available
    private static func countLinesOfCodeFallback(at url: URL) -> Int {
        let fm = FileManager.default
        var totalLines = 0
        var filesProcessed = 0
        let basePathCount = url.pathComponents.count

        guard let enumerator = fm.enumerator(
            at: url,
            includingPropertiesForKeys: [.isRegularFileKey, .isDirectoryKey],
            options: [.skipsHiddenFiles]
        ) else { return 0 }

        while let fileURL = enumerator.nextObject() as? URL {
            // Stop if we've hit the file limit
            if filesProcessed >= maxFilesToCount { break }

            // Skip excluded directories
            if excludedDirectories.contains(fileURL.lastPathComponent) {
                enumerator.skipDescendants()
                continue
            }

            // Skip files deeper than maxRecurseDepth
            let depth = fileURL.pathComponents.count - basePathCount - 1
            if depth > maxRecurseDepth {
                continue
            }

            // Check if it's a source file
            let ext = fileURL.pathExtension.lowercased()
            guard sourceExtensions.contains(ext) else { continue }

            // Count lines
            totalLines += countLines(in: fileURL)
            filesProcessed += 1
        }

        return totalLines
    }

    /// Count lines in a list of relative file paths
    private static func countLinesInFiles(_ files: [String], baseURL: URL) -> Int {
        var totalLines = 0
        var filesProcessed = 0

        for relativePath in files {
            // Stop if we've hit the file limit
            if filesProcessed >= maxFilesToCount { break }

            // Skip excluded directories
            let components = relativePath.split(separator: "/")
            if components.contains(where: { excludedDirectories.contains(String($0)) }) {
                continue
            }

            // Skip files deeper than maxRecurseDepth
            let depth = components.count - 1
            if depth > maxRecurseDepth {
                continue
            }

            // Check if it's a source file
            let ext = (relativePath as NSString).pathExtension.lowercased()
            guard sourceExtensions.contains(ext) else { continue }

            // Count lines
            let fileURL = baseURL.appendingPathComponent(relativePath)
            totalLines += countLines(in: fileURL)
            filesProcessed += 1
        }

        return totalLines
    }

    /// Count non-empty lines in a single file
    private static func countLines(in url: URL) -> Int {
        guard let data = try? Data(contentsOf: url),
              let content = String(data: data, encoding: .utf8) else { return 0 }

        // Count non-empty lines
        return content.split(separator: "\n", omittingEmptySubsequences: false)
            .filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
            .count
    }

    /// Format LOC count for display (e.g., "12.3K", "1.2M")
    static func formatLOC(_ count: Int) -> String {
        if count >= 1_000_000 {
            let millions = Double(count) / 1_000_000.0
            return String(format: "%.1fM", millions)
        } else if count >= 1_000 {
            let thousands = Double(count) / 1_000.0
            return String(format: "%.1fK", thousands)
        } else {
            return "\(count)"
        }
    }
}
