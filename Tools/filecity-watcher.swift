#!/usr/bin/env swift
//
// filecity-watcher.swift
// Monitors file activity for LLM tools and sends events to File City via Unix socket
//
// Usage: sudo swift filecity-watcher.swift [projects_path]
// Default: /Users/kevin/projects
//

import Foundation

let socketPath = "/tmp/filecity-activity.sock"
let projectsPath = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "/Users/kevin/projects"

// Clean up old socket
unlink(socketPath)

// Create socket
let serverSocket = socket(AF_UNIX, SOCK_STREAM, 0)
guard serverSocket >= 0 else {
    print("Failed to create socket")
    exit(1)
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
    print("Failed to bind socket")
    exit(1)
}

guard listen(serverSocket, 5) >= 0 else {
    print("Failed to listen")
    exit(1)
}

// Make socket world-writable so non-root app can connect
chmod(socketPath, 0o777)

print("File City Activity Watcher")
print("Socket: \(socketPath)")
print("Watching: \(projectsPath)")
print("Waiting for File City to connect...")

var clients: [Int32] = []
let clientLock = NSLock()

// Accept connections in background
DispatchQueue.global().async {
    while true {
        let clientSocket = accept(serverSocket, nil, nil)
        if clientSocket >= 0 {
            clientLock.lock()
            clients.append(clientSocket)
            clientLock.unlock()
            print("Client connected (total: \(clients.count))")
        }
    }
}

func sendToClients(_ message: String) {
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

// Run fs_usage and process output - monitors all processes, filters by path
func runFsUsage() {
    while true {
        print("Monitoring all file activity in: \(projectsPath)")

        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/usr/sbin/fs_usage")
        // Monitor all processes, filter by path in output processing
        task.arguments = ["-w", "-f", "pathname"]

        let pipe = Pipe()
        task.standardOutput = pipe
        task.standardError = Pipe()

        var buffer = Data()
        let writeHints = ["write", "pwrite", "truncate", "create", "rename", "unlink", "mkdir", "rmdir"]
        let readHints = ["read", "pread", "open", "stat", "getattr", "mmap"]
        var lastEventByKey: [String: Date] = [:]
        let throttleInterval: TimeInterval = 0.15

        pipe.fileHandleForReading.readabilityHandler = { handle in
            let data = handle.availableData
            guard !data.isEmpty else { return }
            buffer.append(data)

            while let newlineRange = buffer.range(of: Data([0x0A])) {
                let lineData = buffer.subdata(in: buffer.startIndex..<newlineRange.lowerBound)
                buffer.removeSubrange(buffer.startIndex...newlineRange.lowerBound)

                guard let line = String(data: lineData, encoding: .utf8),
                      line.contains(projectsPath) else { continue }

                let lower = line.lowercased()
                var kind: String?
                if writeHints.contains(where: { lower.contains($0) }) {
                    kind = "write"
                } else if readHints.contains(where: { lower.contains($0) }) {
                    kind = "read"
                }
                guard let kind else { continue }

                // Extract path
                guard let pathRange = line.range(of: projectsPath) else { continue }
                let tail = line[pathRange.lowerBound...]
                let pathToken = tail.split(whereSeparator: { $0 == " " || $0 == "\t" }).first
                guard let pathToken else { continue }
                let path = String(pathToken)

                // Extract process name
                let processName = line.split(whereSeparator: { $0 == " " || $0 == "\t" }).first.map(String.init) ?? "unknown"

                // Throttle
                let key = "\(processName)|\(kind)|\(path)"
                let now = Date()
                if let last = lastEventByKey[key], now.timeIntervalSince(last) < throttleInterval {
                    continue
                }
                lastEventByKey[key] = now

                // Send to clients: process|kind|path
                let message = "\(processName)|\(kind)|\(path)"
                sendToClients(message)
                print("[\(kind.uppercased())] \(processName): \(path)")
            }
        }

        try? task.run()
        task.waitUntilExit()

        pipe.fileHandleForReading.readabilityHandler = nil
        print("fs_usage exited, restarting...")
        sleep(1)
    }
}

// Handle cleanup
signal(SIGINT) { _ in
    unlink(socketPath)
    exit(0)
}
signal(SIGTERM) { _ in
    unlink(socketPath)
    exit(0)
}

runFsUsage()
