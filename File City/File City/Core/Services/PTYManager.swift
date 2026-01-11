import Foundation
import Combine

@MainActor
final class PTYManager: ObservableObject {
    struct Session {
        let id: UUID
        let process: Process
        let pipe: Pipe
        let workingDirectory: URL
        var ptyPath: String
        var lastOutputTime: Date
        var state: ClaudeSession.SessionState
    }

    @Published private(set) var sessions: [UUID: Session] = [:]

    let sessionStateChanged = PassthroughSubject<UUID, Never>()
    let sessionExited = PassthroughSubject<UUID, Never>()

    private var idleTimers: [UUID: Timer] = [:]

    private let idleThreshold: TimeInterval = 2.0

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
            activate
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

        // Send interrupt to the terminal session
        let script = """
        tell application "iTerm2"
            repeat with w in windows
                repeat with t in tabs of w
                    repeat with s in sessions of t
                        if tty of s is "\(session.ptyPath)" then
                            tell s to write text "exit"
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
        guard let session = sessions[sessionID] else { return }

        let script = """
        tell application "iTerm2"
            activate
            repeat with w in windows
                repeat with t in tabs of w
                    repeat with s in sessions of t
                        if tty of s is "\(session.ptyPath)" then
                            tell w to select
                            tell t to select
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
    }

    private func startIdleTimer(sessionID: UUID) {
        let timer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.checkSessionActivity(sessionID: sessionID)
            }
        }
        idleTimers[sessionID] = timer
    }

    private func checkSessionActivity(sessionID: UUID) {
        guard let session = sessions[sessionID] else {
            idleTimers[sessionID]?.invalidate()
            idleTimers.removeValue(forKey: sessionID)
            return
        }

        NSLog("[PTYManager] checkSessionActivity for %@, ptyPath: %@", sessionID.uuidString, session.ptyPath)

        // Check if the iTerm session exists and get its contents to detect Claude state
        let checkScript = """
        tell application "iTerm2"
            repeat with w in windows
                repeat with t in tabs of w
                    repeat with s in sessions of t
                        if tty of s is "\(session.ptyPath)" then
                            set sessionContents to contents of s
                            return "exists:" & sessionContents
                        end if
                    end repeat
                end repeat
            end repeat
            return "gone"
        end tell
        """

        // Run AppleScript in background, then update state on main actor
        let scriptToRun = checkScript
        Task.detached {
            let task = Process()
            let pipe = Pipe()
            task.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
            task.arguments = ["-e", scriptToRun]
            task.standardOutput = pipe
            task.standardError = FileHandle.nullDevice
            try? task.run()
            task.waitUntilExit()

            let output = String(data: pipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""

            // Process result on main actor
            await MainActor.run {
                self.processSessionCheckResult(sessionID: sessionID, output: output)
            }
        }
    }

    private func processSessionCheckResult(sessionID: UUID, output: String) {
        if output.contains("gone") {
            handleSessionExit(sessionID: sessionID)
        } else if output.hasPrefix("exists:") {
            let contents = String(output.dropFirst("exists:".count))
            let newState = detectClaudeState(from: contents)

            guard let currentState = sessions[sessionID]?.state,
                  currentState != .launching && currentState != .exiting else { return }

            if currentState != newState {
                NSLog("[PTYManager] State change: %d -> %d, sending signal", currentState.rawValue, newState.rawValue)
                sessions[sessionID]?.state = newState
                sessionStateChanged.send(sessionID)
                NSLog("[PTYManager] Signal sent for session %@", sessionID.uuidString)
            }
        }
    }

    /// Detect Claude's state from terminal contents
    private func detectClaudeState(from contents: String) -> ClaudeSession.SessionState {
        // Get the last portion of the terminal content
        let recentContent = String(contents.suffix(2000))

        // First, check if Claude is waiting for input (prompt at end)
        // The prompt line looks like: ❯ followed by optional input
        // Check the last few lines for the prompt
        let lines = recentContent.components(separatedBy: .newlines)
        let lastLines = lines.suffix(10).joined(separator: "\n")

        // If the very end shows the prompt, Claude is idle
        // The prompt appears as "❯" possibly followed by user input
        if lastLines.contains("❯") && !lastLines.contains("(esc to interrupt") {
            return .idle
        }

        // Check for active work indicators in recent content
        // "(esc to interrupt" appears in the status line during activity
        if lastLines.contains("(esc to interrupt") || lastLines.contains("Running…") {
            return .generating
        }

        // Check for tool execution patterns (these show as ⏺ ToolName(...))
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
