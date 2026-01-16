import Foundation
import Combine
import AppKit

@MainActor
final class PTYManager: ObservableObject {
    struct Session {
        let id: UUID
        let process: Process?  // Optional for reconnected sessions
        let pipe: Pipe?        // Optional for reconnected sessions
        let workingDirectory: URL
        var ptyPath: String
        var lastOutputTime: Date
        var state: ClaudeSession.SessionState
        var lastOutputLines: [String] = []  // Last few lines of terminal output
        var isReconnected: Bool = false     // True if reconnected to existing session
        var outputHistory: [String] = []    // Full output history for selected session
        var lastKnownSnapshot: String = ""  // For diff-based detection
    }

    @Published private(set) var sessions: [UUID: Session] = [:]

    let sessionStateChanged = PassthroughSubject<UUID, Never>()
    let sessionExited = PassthroughSubject<UUID, Never>()
    let sessionDiscovered = PassthroughSubject<UUID, Never>()  // For reconnected sessions
    let sessionOutputUpdated = PassthroughSubject<UUID, Never>()  // When output changes for selected session

    private var idleTimers: [UUID: Timer] = [:]
    private var pendingIdleTransitions: [UUID: Timer] = [:]  // Grace period before transitioning to idle
    private var activityCheckTimer: Timer?  // Single timer for all session checks
    private var foregroundPollTimer: Timer?  // High-frequency polling for selected session
    private var selectedSessionID: UUID?     // Currently selected session for output capture

    private let idleThreshold: TimeInterval = 2.0
    private let generatingToIdleGracePeriod: TimeInterval = 3.0  // Wait 3 seconds before committing to idle

    /// Serial queue for AppleScript operations to avoid overwhelming iTerm2
    private let appleScriptQueue = DispatchQueue(label: "com.filecity.applescript", qos: .userInitiated)
    private var isCheckingActivity = false  // Prevent overlapping activity checks

    /// Discover and reconnect to existing Claude sessions in iTerm2
    func discoverExistingSessions() {
        NSLog("[PTYManager] Discovering existing Claude sessions...")

        // Query iTerm2 for all sessions - check contents for claude patterns
        let script = #"""
tell application "iTerm2"
    set results to ""
    repeat with w in windows
        repeat with t in tabs of w
            repeat with s in sessions of t
                try
                    set ttyPath to tty of s
                    set fullContents to contents of s
                    if fullContents contains "claude" then
                        set results to results & ttyPath & "|||" & fullContents & "###"
                    end if
                end try
            end repeat
        end repeat
    end repeat
    return results
end tell
"""#

        // Run discovery in background to avoid blocking MainActor
        let scriptToRun = script
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            NSLog("[PTYManager] Starting AppleScript discovery task...")
            let task = Process()
            let outputPipe = Pipe()
            task.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
            task.arguments = ["-e", scriptToRun]
            task.standardOutput = outputPipe
            task.standardError = FileHandle.nullDevice

            // Read output asynchronously to avoid pipe buffer deadlock
            var outputData = Data()
            outputPipe.fileHandleForReading.readabilityHandler = { handle in
                let data = handle.availableData
                if !data.isEmpty {
                    outputData.append(data)
                }
            }

            do {
                try task.run()
            } catch {
                NSLog("[PTYManager] AppleScript launch failed: %@", error.localizedDescription)
                outputPipe.fileHandleForReading.readabilityHandler = nil
                return
            }

            task.waitUntilExit()
            outputPipe.fileHandleForReading.readabilityHandler = nil

            // Read any remaining data
            let remainingData = outputPipe.fileHandleForReading.readDataToEndOfFile()
            outputData.append(remainingData)

            let output = String(data: outputData, encoding: .utf8) ?? ""
            NSLog("[PTYManager] AppleScript completed with status: %d, output: %d chars",
                  task.terminationStatus, output.count)

            DispatchQueue.main.async {
                self?.processDiscoveredSessions(output: output)
            }
        }
    }

    private func processDiscoveredSessions(output: String) {
        NSLog("[PTYManager] Raw discovery output length: %d", output.count)
        let sessionBlocks = output.components(separatedBy: "###").filter { !$0.isEmpty }
        NSLog("[PTYManager] Found %d potential Claude sessions", sessionBlocks.count)

        if sessionBlocks.isEmpty && !output.isEmpty {
            NSLog("[PTYManager] Output was: %@", String(output.prefix(500)))
        }

        for block in sessionBlocks {
            let parts = block.components(separatedBy: "|||")
            guard parts.count >= 2 else {
                NSLog("[PTYManager] Block has insufficient parts: %d", parts.count)
                continue
            }

            let ttyPath = parts[0].trimmingCharacters(in: .whitespacesAndNewlines)
            let contents = parts[1]

            NSLog("[PTYManager] Checking session at %@, contents length: %d", ttyPath, contents.count)

            // Verify this is actually a Claude session by looking for specific patterns
            let isClaudeSession = contents.contains("--dangerously-skip-permissions") ||
                                  contents.contains("claude>") ||
                                  (contents.contains("claude") && contents.contains("❯"))

            guard isClaudeSession else {
                NSLog("[PTYManager] Session at %@ doesn't appear to be Claude", ttyPath)
                continue
            }

            // Skip if we already have this session
            if sessions.values.contains(where: { $0.ptyPath == ttyPath }) {
                NSLog("[PTYManager] Already tracking session at %@", ttyPath)
                continue
            }

            // Try to extract working directory from terminal contents
            // Look for patterns like "cd '/path/to/dir'" or directory in prompt
            let workingDirectory = extractWorkingDirectory(from: contents)

            guard let directory = workingDirectory else {
                NSLog("[PTYManager] Could not determine working directory for session at %@", ttyPath)
                NSLog("[PTYManager] Contents preview: %@", String(contents.prefix(300)))
                continue
            }

            NSLog("[PTYManager] Reconnecting to Claude session at %@ in %@", ttyPath, directory.path)

            let sessionID = UUID()
            let session = Session(
                id: sessionID,
                process: nil,
                pipe: nil,
                workingDirectory: directory,
                ptyPath: ttyPath,
                lastOutputTime: Date(),
                state: .idle,  // Assume idle until we detect otherwise
                lastOutputLines: [],
                isReconnected: true
            )
            sessions[sessionID] = session

            // Start monitoring
            startIdleTimer(sessionID: sessionID)

            // Notify about discovered session
            sessionDiscovered.send(sessionID)
        }
    }

    private func extractWorkingDirectory(from contents: String) -> URL? {
        // Look for "cd '/path'" pattern from our spawn command
        if let range = contents.range(of: "cd '([^']+)'", options: .regularExpression) {
            let match = String(contents[range])
            let path = match.replacingOccurrences(of: "cd '", with: "").replacingOccurrences(of: "'", with: "")
            return URL(fileURLWithPath: path)
        }

        // Look for directory path after prompt (common pattern: ~/path or /path)
        let lines = contents.components(separatedBy: .newlines)
        for line in lines.reversed() {
            // Look for absolute paths
            if let range = line.range(of: "(/[^\\s]+)", options: .regularExpression) {
                let path = String(line[range])
                var isDir: ObjCBool = false
                if FileManager.default.fileExists(atPath: path, isDirectory: &isDir), isDir.boolValue {
                    return URL(fileURLWithPath: path)
                }
            }
            // Look for ~ paths
            if let range = line.range(of: "(~/[^\\s]*)", options: .regularExpression) {
                let tilePath = String(line[range])
                let path = (tilePath as NSString).expandingTildeInPath
                var isDir: ObjCBool = false
                if FileManager.default.fileExists(atPath: path, isDirectory: &isDir), isDir.boolValue {
                    return URL(fileURLWithPath: path)
                }
            }
        }

        return nil
    }

    func spawnClaude(at directory: URL) -> UUID {
        let sessionID = UUID()

        // Create a process to run Claude in a new Terminal/iTerm window
        // This approach opens a new terminal window rather than using a raw PTY
        let process = Process()
        let pipe = Pipe()

        // Use osascript to open a new iTerm window with Claude
        process.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")

        let script = """
        tell application "iTerm2"
            set newWindow to (create window with default profile)
            tell current session of newWindow
                write text "cd '\(directory.path)' && claude --dangerously-skip-permissions"
            end tell
            return tty of current session of newWindow
        end tell
        """

        process.arguments = ["-e", script]
        process.standardOutput = pipe
        process.standardError = pipe

        do {
            try process.run()
            process.waitUntilExit()

            // Get the TTY path from output
            let outputData = pipe.fileHandleForReading.readDataToEndOfFile()
            let ptyPath = String(data: outputData, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""

            let session = Session(
                id: sessionID,
                process: process,
                pipe: pipe,
                workingDirectory: directory,
                ptyPath: ptyPath,
                lastOutputTime: Date(),
                state: .launching
            )
            sessions[sessionID] = session

            // Start monitoring for state changes
            startIdleTimer(sessionID: sessionID)

            // After startup delay, allow content-based state detection to take over
            Task { @MainActor in
                try? await Task.sleep(nanoseconds: 3_000_000_000) // 3 seconds for Claude to start
                if sessions[sessionID]?.state == .launching {
                    // Transition from launching - content detection will now manage state
                    sessions[sessionID]?.state = .idle
                    sessionStateChanged.send(sessionID)
                }
            }

        } catch {
            NSLog("[PTYManager] Failed to spawn Claude: %@", error.localizedDescription)
        }

        return sessionID
    }

    func terminateSession(id: UUID) {
        guard let session = sessions[id] else { return }

        // Stop monitoring
        idleTimers[id]?.invalidate()
        idleTimers.removeValue(forKey: id)

        pendingIdleTransitions[id]?.invalidate()
        pendingIdleTransitions.removeValue(forKey: id)

        // Close the iTerm session directly
        let script = """
        tell application "iTerm2"
            repeat with w in windows
                repeat with t in tabs of w
                    repeat with s in sessions of t
                        if tty of s is "\(session.ptyPath)" then
                            close s
                            return
                        end if
                    end repeat
                end repeat
            end repeat
        end tell
        """

        Task.detached {
            let task = Process()
            task.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
            task.arguments = ["-e", script]
            try? task.run()
            task.waitUntilExit()
        }

        // Update state
        sessions[id]?.state = .exiting
        sessionStateChanged.send(id)

        // Remove after delay
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 500_000_000) // 0.5s
            sessions.removeValue(forKey: id)
            sessionExited.send(id)
        }
    }

    func focusTerminal(sessionID: UUID) {
        guard let session = sessions[sessionID] else {
            NSLog("[PTYManager] focusTerminal: session not found")
            return
        }

        let script = """
        tell application "iTerm2"
            activate
            repeat with w in windows
                repeat with t in tabs of w
                    repeat with s in sessions of t
                        if tty of s is "\(session.ptyPath)" then
                            tell w to select
                            tell t to select
                            return "found"
                        end if
                    end repeat
                end repeat
            end repeat
            return "not_found"
        end tell
        """

        let scriptToRun = script

        // Use high-priority queue for focus operations (user-initiated action)
        DispatchQueue.global(qos: .userInteractive).async {
            let task = Process()
            task.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
            task.arguments = ["-e", scriptToRun]
            task.standardOutput = FileHandle.nullDevice
            task.standardError = FileHandle.nullDevice
            try? task.run()
            task.waitUntilExit()
        }
    }

    func sendInput(sessionID: UUID, text: String) {
        guard let session = sessions[sessionID] else {
            NSLog("[PTYManager] sendInput: session not found for ID %@", sessionID.uuidString)
            return
        }

        NSLog("[PTYManager] sendInput: Sending '%@' to session %@ at ptyPath %@", text, sessionID.uuidString, session.ptyPath)

        // Use AppleScript to send text and explicit Return key press
        let escapedText = text.replacingOccurrences(of: "\"", with: "\\\"")
        let script = """
        tell application "iTerm2"
            repeat with w in windows
                repeat with t in tabs of w
                    repeat with s in sessions of t
                        if tty of s is "\(session.ptyPath)" then
                            tell s
                                write text "\(escapedText)"
                            end tell
                            return "sent"
                        end if
                    end repeat
                end repeat
            end repeat
            return "not_found"
        end tell
        """

        // Execute asynchronously on AppleScript queue
        appleScriptQueue.async {
            // First, get the File City window ID before we change focus
            let getWindowScript = """
            tell application "System Events"
                set fileCityProcess to first application process whose bundle identifier is "com.kevintang.filecity"
                set fileCityWindowID to id of first window of fileCityProcess
                return fileCityWindowID
            end tell
            """

            var fileCityWindowID = ""
            let getWindowTask = Process()
            let getWindowPipe = Pipe()
            getWindowTask.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
            getWindowTask.arguments = ["-e", getWindowScript]
            getWindowTask.standardOutput = getWindowPipe
            getWindowTask.standardError = FileHandle.nullDevice

            do {
                try getWindowTask.run()
                getWindowTask.waitUntilExit()
                let windowData = getWindowPipe.fileHandleForReading.readDataToEndOfFile()
                fileCityWindowID = String(data: windowData, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                NSLog("[PTYManager] Captured File City window ID: %@", fileCityWindowID)
            } catch {
                NSLog("[PTYManager] Failed to get File City window ID: %@", error.localizedDescription)
            }

            // Now write the text
            let task = Process()
            let outputPipe = Pipe()
            let errorPipe = Pipe()

            task.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
            task.arguments = ["-e", script]
            task.standardOutput = outputPipe
            task.standardError = errorPipe

            do {
                try task.run()
                task.waitUntilExit()

                let outputData = outputPipe.fileHandleForReading.readDataToEndOfFile()
                let output = String(data: outputData, encoding: .utf8) ?? ""

                let errorData = errorPipe.fileHandleForReading.readDataToEndOfFile()
                let errorMsg = String(data: errorData, encoding: .utf8) ?? ""

                if task.terminationStatus == 0 && output.contains("sent") {
                    NSLog("[PTYManager] sendInput text succeeded for session %@", sessionID.uuidString)

                    // Now send the Return key press via AppleScript
                    let returnKeyScript = """
                    tell application "iTerm" to activate
                    delay 0.05

                    tell application "System Events"
                        key code 36
                    end tell
                    """

                    let returnTask = Process()
                    returnTask.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
                    returnTask.arguments = ["-e", returnKeyScript]
                    returnTask.standardOutput = FileHandle.nullDevice
                    returnTask.standardError = FileHandle.nullDevice

                    try returnTask.run()
                    returnTask.waitUntilExit()
                    NSLog("[PTYManager] sendInput Return key sent for session %@", sessionID.uuidString)

                    // Restore focus to File City using native Swift API on the main thread
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
                        NSApplication.shared.activate(ignoringOtherApps: true)
                        if let window = NSApplication.shared.windows.first {
                            window.makeKeyAndOrderFront(nil)
                        }
                    }
                } else {
                    NSLog("[PTYManager] sendInput result: status=%d, output='%@', error='%@'", task.terminationStatus, output, errorMsg)
                }
            } catch {
                NSLog("[PTYManager] sendInput exception: %@", error.localizedDescription)
            }
        }
    }

    private func startIdleTimer(sessionID: UUID) {
        // Just track that this session needs monitoring
        idleTimers[sessionID] = nil  // Placeholder

        // Start the global activity check timer if not already running
        if activityCheckTimer == nil {
            activityCheckTimer = Timer.scheduledTimer(withTimeInterval: 2.0, repeats: true) { [weak self] _ in
                Task { @MainActor [weak self] in
                    self?.checkAllSessionsActivity()
                }
            }
        }
    }

    func setHighFrequencyPolling(for sessionID: UUID, enabled: Bool) {
        if enabled {
            selectedSessionID = sessionID
            startForegroundPolling()
        } else {
            selectedSessionID = nil
            stopForegroundPolling()
        }
    }

    private func startForegroundPolling() {
        stopForegroundPolling()

        // Immediately fetch current output before starting polling
        pollSelectedSession()

        foregroundPollTimer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.pollSelectedSession()
            }
        }
    }

    private func stopForegroundPolling() {
        foregroundPollTimer?.invalidate()
        foregroundPollTimer = nil
    }

    private func pollSelectedSession() {
        guard let sessionID = selectedSessionID,
              sessions[sessionID] != nil else { return }

        let script = """
        tell application "iTerm2"
            repeat with w in windows
                repeat with t in tabs of w
                    repeat with s in sessions of t
                        try
                            set ttyPath to tty of s
                            if ttyPath is not "" then
                                set fullContents to contents of s
                                if (count of fullContents) > 10000 then
                                    set sessionContents to text -10000 thru -1 of fullContents
                                else
                                    set sessionContents to fullContents
                                end if
                                return ttyPath & "|||" & sessionContents
                            end if
                        end try
                    end repeat
                end repeat
            end repeat
            return ""
        end tell
        """

        let scriptToRun = script
        appleScriptQueue.async { [weak self] in
            let task = Process()
            let pipe = Pipe()
            task.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
            task.arguments = ["-e", scriptToRun]
            task.standardOutput = pipe
            task.standardError = FileHandle.nullDevice

            do {
                try task.run()
                task.waitUntilExit()
            } catch {
                NSLog("[PTYManager] pollSelectedSession failed: %@", error.localizedDescription)
                return
            }

            let output = String(data: pipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""

            DispatchQueue.main.async {
                self?.processSelectedSessionOutput(output: output, sessionID: sessionID)
            }
        }
    }

    private func processSelectedSessionOutput(output: String, sessionID: UUID) {
        guard let session = sessions[sessionID] else { return }

        let parts = output.components(separatedBy: "|||")
        guard parts.count >= 2 else { return }

        let ptyPath = parts[0]
        let fullContents = parts[1]

        // Only process if this is the correct session
        guard session.ptyPath == ptyPath else { return }

        processFullOutput(sessionID: sessionID, fullContents: fullContents)
    }

    private func processFullOutput(sessionID: UUID, fullContents: String) {
        guard var session = sessions[sessionID] else { return }

        // Strip ANSI codes for cleaner comparison
        let cleanContents = stripANSI(fullContents)

        // Only process if content has actually changed
        if cleanContents == session.lastKnownSnapshot {
            return
        }

        // If this is the first poll, initialize with content from the last prompt onwards
        if session.lastKnownSnapshot.isEmpty {
            let lines = cleanContents.components(separatedBy: .newlines)
            let meaningfulLines = lines.filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }

            // Find the last prompt to avoid old scrollback
            if let lastPromptIndex = meaningfulLines.lastIndex(where: { $0.contains("❯") }) {
                session.outputHistory = Array(meaningfulLines[lastPromptIndex...])
            } else {
                // No prompt found, use all meaningful lines
                session.outputHistory = meaningfulLines
            }

            session.lastKnownSnapshot = cleanContents
            sessions[sessionID] = session
            sessionOutputUpdated.send(sessionID)
            return
        }

        // For subsequent polls, only add NEW content we haven't captured yet
        let lines = cleanContents.components(separatedBy: .newlines)
        let allMeaningfulLines = lines.filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }

        // Extract only lines that aren't already in our history
        // Match by trimmed content to avoid whitespace differences
        let newLines = allMeaningfulLines.filter { newLine in
            !session.outputHistory.contains(where: { existing in
                existing.trimmingCharacters(in: .whitespaces) == newLine.trimmingCharacters(in: .whitespaces)
            })
        }

        if !newLines.isEmpty {
            session.outputHistory.append(contentsOf: newLines)
        }

        // Limit history to 5000 lines to prevent memory bloat
        if session.outputHistory.count > 5000 {
            session.outputHistory.removeFirst(session.outputHistory.count - 5000)
        }

        session.lastKnownSnapshot = cleanContents
        sessions[sessionID] = session
        sessionOutputUpdated.send(sessionID)
    }

    private func stripANSI(_ string: String) -> String {
        // Remove ANSI escape sequences like \x1B[...m
        string.replacingOccurrences(
            of: "\\x1B\\[[0-9;]*[mK]|\\e\\[[0-9;]*[mK]",
            with: "",
            options: .regularExpression
        )
    }

    /// Check all sessions in a single batched AppleScript call
    private func checkAllSessionsActivity() {
        guard !sessions.isEmpty else { return }
        guard !isCheckingActivity else { return }

        isCheckingActivity = true

        // Build list of ptyPaths to check
        let sessionPaths = sessions.map { ($0.key, $0.value.ptyPath) }

        // Build a batched AppleScript that checks all sessions at once
        let pathList = sessionPaths.map { "\"\($0.1)\"" }.joined(separator: ", ")
        let script = """
        tell application "iTerm2"
            set targetPaths to {\(pathList)}
            set results to ""
            repeat with w in windows
                repeat with t in tabs of w
                    repeat with s in sessions of t
                        try
                            set ttyPath to tty of s
                            if targetPaths contains ttyPath then
                                set fullContents to contents of s
                                if (count of fullContents) > 3000 then
                                    set sessionContents to text -3000 thru -1 of fullContents
                                else
                                    set sessionContents to fullContents
                                end if
                                set results to results & ttyPath & "|||" & sessionContents & "###"
                            end if
                        end try
                    end repeat
                end repeat
            end repeat
            return results
        end tell
        """

        let scriptToRun = script
        let pathMap = Dictionary(uniqueKeysWithValues: sessionPaths.map { ($0.1, $0.0) })

        appleScriptQueue.async { [weak self] in
            let task = Process()
            let pipe = Pipe()
            task.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
            task.arguments = ["-e", scriptToRun]
            task.standardOutput = pipe
            task.standardError = FileHandle.nullDevice

            do {
                try task.run()
                task.waitUntilExit()
            } catch {
                NSLog("[PTYManager] Activity check failed: %@", error.localizedDescription)
                DispatchQueue.main.async { self?.isCheckingActivity = false }
                return
            }

            let output = String(data: pipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""

            DispatchQueue.main.async {
                self?.processBatchedActivityResults(output: output, pathMap: pathMap)
                self?.isCheckingActivity = false
            }
        }
    }

    /// Process batched activity check results
    private func processBatchedActivityResults(output: String, pathMap: [String: UUID]) {
        // Parse results: "ptyPath|||contents###ptyPath|||contents###..."
        let blocks = output.components(separatedBy: "###").filter { !$0.isEmpty }

        // Track which sessions we found
        var foundPaths = Set<String>()

        for block in blocks {
            let parts = block.components(separatedBy: "|||")
            guard parts.count >= 2 else { continue }

            let ptyPath = parts[0].trimmingCharacters(in: .whitespacesAndNewlines)
            let contents = parts[1]
            foundPaths.insert(ptyPath)

            guard let sessionID = pathMap[ptyPath] else { continue }

            processSessionCheckResult(sessionID: sessionID, output: "exists:" + contents)
        }

        // Mark sessions not found as gone
        for (ptyPath, sessionID) in pathMap {
            if !foundPaths.contains(ptyPath) {
                handleSessionExit(sessionID: sessionID)
            }
        }
    }

    private func processSessionCheckResult(sessionID: UUID, output: String) {
        if output.contains("gone") {
            handleSessionExit(sessionID: sessionID)
        } else if output.hasPrefix("exists:") {
            let contents = String(output.dropFirst("exists:".count))
            let newState = detectClaudeState(from: contents)

            guard let currentState = sessions[sessionID]?.state else { return }

            // Log state detection for debugging
            if currentState != newState {
                NSLog("[PTYManager] State detection: current=%d, new=%d for session %@", currentState.rawValue, newState.rawValue, sessionID.uuidString)
                let lastChars = String(contents.suffix(200))
                NSLog("[PTYManager] Last 200 chars: %@", lastChars)
            }

            // Extract and store last output lines for hover display
            let lastLines = extractLastOutputLines(from: contents)
            sessions[sessionID]?.lastOutputLines = lastLines

            // Also accumulate full output history even during background polling
            processFullOutput(sessionID: sessionID, fullContents: contents)

            guard currentState != .launching && currentState != .exiting else { return }

            if currentState != newState {
                // Cancel any pending idle transition when state changes
                pendingIdleTransitions[sessionID]?.invalidate()
                pendingIdleTransitions[sessionID] = nil

                // Apply state change immediately
                NSLog("[PTYManager] State change: %d -> %d, sending signal", currentState.rawValue, newState.rawValue)
                sessions[sessionID]?.state = newState
                sessionStateChanged.send(sessionID)
                NSLog("[PTYManager] Signal sent for session %@", sessionID.uuidString)
            }
        }
    }

    /// Extract the last meaningful output lines from terminal contents
    private func extractLastOutputLines(from contents: String) -> [String] {
        let lines = contents.components(separatedBy: .newlines)

        // Filter out empty lines, prompt lines, and control sequences
        let meaningfulLines = lines.filter { line in
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            // Skip empty lines
            guard !trimmed.isEmpty else { return false }
            // Skip prompt lines
            if trimmed.hasPrefix("❯") { return false }
            // Skip status/spinner lines
            if trimmed.contains("(esc to interrupt") { return false }
            if trimmed.contains("Running…") { return false }
            // Skip ANSI escape sequences only lines
            if trimmed.hasPrefix("\u{1B}[") && trimmed.count < 20 { return false }
            return true
        }

        // Return last 12 meaningful lines for hover preview
        return Array(meaningfulLines.suffix(12))
    }

    /// Detect Claude's state from terminal contents
    private func detectClaudeState(from contents: String) -> ClaudeSession.SessionState {
        // Get the last portion of the terminal content
        let recentContent = String(contents.suffix(2000))

        // Split into lines and find non-empty ones
        let lines = recentContent.components(separatedBy: .newlines)
        let nonEmptyLines = lines.filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }

        guard !nonEmptyLines.isEmpty else {
            return .idle
        }

        // HIGHEST PRIORITY: If the very last non-empty line starts with a prompt, Claude is IDLE
        // This takes absolute precedence over any stale indicators from earlier
        let lastLine = nonEmptyLines.last ?? ""
        let trimmedLastLine = lastLine.trimmingCharacters(in: .whitespaces)
        if trimmedLastLine.starts(with: "❯") {
            return .idle
        }

        // Check the last 10 lines for active work indicators
        let lastLines = nonEmptyLines.suffix(10).joined(separator: "\n")

        // Check for active work indicators in recent content
        // "(esc to interrupt" appears in the status line during activity
        if lastLines.contains("(esc to interrupt") || lastLines.contains("Running…") {
            return .generating
        }

        // Check for tool execution patterns (these show as ⏺ ToolName(...))
        // Only count as GENERATING if BOTH tool pattern AND "Running" are present
        let toolPatterns = ["⏺ Read(", "⏺ Edit(", "⏺ Write(", "⏺ Bash(", "⏺ Grep(", "⏺ Glob(", "⏺ Task("]
        for pattern in toolPatterns {
            if lastLines.contains(pattern) && lastLines.contains("Running") {
                return .generating
            }
        }

        // Default to idle
        return .idle
    }

    private func handleSessionExit(sessionID: UUID) {
        idleTimers[sessionID]?.invalidate()
        idleTimers.removeValue(forKey: sessionID)

        pendingIdleTransitions[sessionID]?.invalidate()
        pendingIdleTransitions.removeValue(forKey: sessionID)

        sessions[sessionID]?.state = .exiting
        sessionStateChanged.send(sessionID)

        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 1_000_000_000) // 1s
            sessions.removeValue(forKey: sessionID)
            sessionExited.send(sessionID)
        }
    }

    /// Update session state from external observation (e.g., file activity)
    func updateSessionState(sessionID: UUID, state: ClaudeSession.SessionState) {
        guard sessions[sessionID] != nil else { return }
        sessions[sessionID]?.state = state
        sessions[sessionID]?.lastOutputTime = Date()
        sessionStateChanged.send(sessionID)
    }
}
