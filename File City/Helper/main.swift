#!/usr/bin/env swift
//
// File City Privileged Helper
// Monitors file activity using fs_usage and sends events via Unix socket
// Installed via SMJobBless, runs as root
//

import Foundation

// MARK: - Helper Delegate

final class HelperDelegate: NSObject, NSXPCListenerDelegate, HelperProtocol {
    func listener(_ listener: NSXPCListener, shouldAcceptNewConnection newConnection: NSXPCConnection) -> Bool {
        newConnection.exportedInterface = NSXPCInterface(with: HelperProtocol.self)
        newConnection.exportedObject = self
        newConnection.resume()
        return true
    }

    func getVersion(withReply reply: @escaping (String) -> Void) {
        reply(HelperConstants.helperVersion)
    }

    func uninstall(withReply reply: @escaping (Bool) -> Void) {
        // Remove the helper from launchd and delete the binary
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/launchctl")
        process.arguments = ["remove", HelperConstants.machServiceName]
        try? process.run()
        process.waitUntilExit()

        let helperPath = "/Library/PrivilegedHelperTools/\(HelperConstants.machServiceName)"
        let success = (try? FileManager.default.removeItem(atPath: helperPath)) != nil
        reply(success)
        exit(0)
    }
}

// MARK: - Socket Server

final class SocketServer {
    private let socketPath: String
    private var serverSocket: Int32 = -1
    private var clients: [Int32] = []
    private let clientLock = NSLock()

    init(socketPath: String) {
        self.socketPath = socketPath
    }

    func start() {
        // Clean up old socket
        unlink(socketPath)

        // Create socket
        serverSocket = socket(AF_UNIX, SOCK_STREAM, 0)
        guard serverSocket >= 0 else {
            NSLog("[Helper] Failed to create socket")
            return
        }

        var addr = sockaddr_un()
        addr.sun_family = sa_family_t(AF_UNIX)
        withUnsafeMutablePointer(to: &addr.sun_path.0) { ptr in
            _ = socketPath.withCString { strncpy(ptr, $0, 104) }
        }

        let bindResult = withUnsafePointer(to: &addr) { ptr in
            ptr.withMemoryRebound(to: sockaddr.self, capacity: 1) { sockPtr in
                bind(serverSocket, sockPtr, socklen_t(MemoryLayout<sockaddr_un>.size))
            }
        }
        guard bindResult >= 0 else {
            NSLog("[Helper] Failed to bind socket")
            return
        }

        guard listen(serverSocket, 5) >= 0 else {
            NSLog("[Helper] Failed to listen on socket")
            return
        }

        // Make socket world-writable so non-root app can connect
        chmod(socketPath, 0o777)

        NSLog("[Helper] Socket server started at %@", socketPath)

        // Accept connections in background
        DispatchQueue.global().async { [weak self] in
            self?.acceptLoop()
        }
    }

    private func acceptLoop() {
        while true {
            let clientSocket = accept(serverSocket, nil, nil)
            if clientSocket >= 0 {
                clientLock.lock()
                clients.append(clientSocket)
                clientLock.unlock()
                NSLog("[Helper] Client connected (total: %d)", clients.count)
            }
        }
    }

    func broadcast(_ message: String) {
        clientLock.lock()
        let data = (message + "\n").data(using: .utf8)!
        clients = clients.filter { client in
            let result = data.withUnsafeBytes { ptr in
                send(client, ptr.baseAddress!, data.count, 0)
            }
            if result < 0 {
                close(client)
                return false
            }
            return true
        }
        clientLock.unlock()
    }

    func stop() {
        if serverSocket >= 0 {
            close(serverSocket)
            serverSocket = -1
        }
        unlink(socketPath)
    }
}

// MARK: - fs_usage Monitor

final class FSUsageMonitor {
    private let projectsPath: String
    private let socketServer: SocketServer
    private var task: Process?

    private let writeHints = ["write", "pwrite", "truncate", "create", "rename", "unlink", "mkdir", "rmdir"]
    private let readHints = ["read", "pread", "open", "stat", "getattr", "mmap"]
    private var lastEventByKey: [String: Date] = [:]
    private let throttleInterval: TimeInterval = 0.15

    init(projectsPath: String, socketServer: SocketServer) {
        self.projectsPath = projectsPath
        self.socketServer = socketServer
    }

    func start() {
        DispatchQueue.global().async { [weak self] in
            self?.runLoop()
        }
    }

    private func runLoop() {
        while true {
            NSLog("[Helper] Starting fs_usage monitor for: %@", projectsPath)

            let task = Process()
            task.executableURL = URL(fileURLWithPath: "/usr/bin/fs_usage")
            task.arguments = ["-w", "-f", "pathname"]

            let pipe = Pipe()
            let errPipe = Pipe()
            task.standardOutput = pipe
            task.standardError = errPipe

            var buffer = Data()

            pipe.fileHandleForReading.readabilityHandler = { [weak self] handle in
                let data = handle.availableData
                guard !data.isEmpty else { return }
                buffer.append(data)
                self?.processBuffer(&buffer)
            }

            errPipe.fileHandleForReading.readabilityHandler = { handle in
                let data = handle.availableData
                if !data.isEmpty, let str = String(data: data, encoding: .utf8) {
                    NSLog("[Helper] fs_usage stderr: %@", str)
                }
            }

            do {
                try task.run()
                self.task = task
                task.waitUntilExit()
                NSLog("[Helper] fs_usage exited with code %d, restarting...", task.terminationStatus)
            } catch {
                NSLog("[Helper] Failed to launch fs_usage: %@", error.localizedDescription)
            }

            pipe.fileHandleForReading.readabilityHandler = nil
            errPipe.fileHandleForReading.readabilityHandler = nil
            sleep(1)
        }
    }

    private func processBuffer(_ buffer: inout Data) {
        while let newlineRange = buffer.range(of: Data([0x0A])) {
            let lineData = buffer.subdata(in: buffer.startIndex..<newlineRange.lowerBound)
            buffer.removeSubrange(buffer.startIndex...newlineRange.lowerBound)

            guard let line = String(data: lineData, encoding: .utf8),
                  line.contains(projectsPath) else { continue }

            processLine(line)
        }
    }

    private func processLine(_ line: String) {
        let lower = line.lowercased()
        var kind: String?
        if writeHints.contains(where: { lower.contains($0) }) {
            kind = "write"
        } else if readHints.contains(where: { lower.contains($0) }) {
            kind = "read"
        }
        guard let kind else { return }

        // Extract path
        guard let pathRange = line.range(of: projectsPath) else { return }
        let tail = line[pathRange.lowerBound...]
        let pathToken = tail.split(whereSeparator: { $0 == " " || $0 == "\t" }).first
        guard let pathToken else { return }
        let path = String(pathToken)

        // Extract process name (appears at end of fs_usage line)
        let processName = line.split(whereSeparator: { $0 == " " || $0 == "\t" }).last.map(String.init) ?? "unknown"

        // Filter to only LLM tools and their common child processes
        let processLower = processName.lowercased()
        let processBase = processLower.split(separator: ".").first.map(String.init) ?? processLower
        let isLLMTool = processLower.contains("claude") ||
                        processLower.contains("codex") ||
                        processLower.contains("gemini") ||
                        processLower.contains("cursor") ||
                        processLower.contains("node") ||
                        processBase == "cat" ||
                        processBase == "ls" ||
                        processBase == "head" ||
                        processBase == "tail" ||
                        processBase == "grep" ||
                        processBase == "rg" ||
                        processBase == "find" ||
                        processBase == "bash" ||
                        processBase == "zsh" ||
                        processBase == "sh"
        guard isLLMTool else { return }

        // Throttle
        let key = "\(processName)|\(kind)|\(path)"
        let now = Date()
        if let last = lastEventByKey[key], now.timeIntervalSince(last) < throttleInterval {
            return
        }
        lastEventByKey[key] = now

        // Send to clients
        let message = "\(processName)|\(kind)|\(path)"
        socketServer.broadcast(message)
    }

    func stop() {
        task?.terminate()
    }
}

// MARK: - Main

let delegate = HelperDelegate()

// Start XPC listener to keep helper alive and handle commands
let listener = NSXPCListener(machServiceName: HelperConstants.machServiceName)
listener.delegate = delegate
listener.resume()

// Start socket server
let socketServer = SocketServer(socketPath: HelperConstants.socketPath)
socketServer.start()

// Start fs_usage monitor - default to ~/projects but could be made configurable
let projectsPath = "/Users/kevin/projects"
let monitor = FSUsageMonitor(projectsPath: projectsPath, socketServer: socketServer)
monitor.start()

NSLog("[Helper] File City Helper started (version %@)", HelperConstants.helperVersion)

// Handle cleanup on termination
signal(SIGINT) { _ in
    socketServer.stop()
    exit(0)
}
signal(SIGTERM) { _ in
    socketServer.stop()
    exit(0)
}

// Run forever
RunLoop.current.run()
