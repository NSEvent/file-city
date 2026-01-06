import Foundation

final class PrivilegedHelperService: NSObject, NSXPCListenerDelegate, PrivilegedHelperProtocol {
    private var connection: NSXPCConnection?
    private var process: Process?
    private var outputHandle: FileHandle?
    private var buffer = Data()
    private let queue = DispatchQueue(label: "filecity.helper.fs_usage")
    private var lastEventByKey: [String: CFTimeInterval] = [:]
    private let throttleInterval: CFTimeInterval = 0.12
    private let sampleDuration: Int = 1
    private var shouldRestart = false
    private var rootPath: String = ""
    private var debugLinesRemaining = 20

    func listener(_ listener: NSXPCListener, shouldAcceptNewConnection newConnection: NSXPCConnection) -> Bool {
        newConnection.exportedInterface = NSXPCInterface(with: PrivilegedHelperProtocol.self)
        newConnection.exportedObject = self
        newConnection.remoteObjectInterface = NSXPCInterface(with: PrivilegedHelperClientProtocol.self)
        newConnection.invalidationHandler = { [weak self] in
            self?.stopWatching()
        }
        newConnection.resume()
        connection = newConnection
        DebugLog.write("[helper] connection accepted")
        return true
    }

    func startWatching(rootPath: String, reply: @escaping (Bool) -> Void) {
        self.rootPath = rootPath
        shouldRestart = true
        DebugLog.write("[helper] startWatching \(rootPath)")
        startFsUsage()
        reply(true)
    }

    func stopWatching() {
        shouldRestart = false
        if let process {
            process.terminate()
        }
        outputHandle?.readabilityHandler = nil
        outputHandle = nil
        process = nil
        buffer.removeAll()
        lastEventByKey.removeAll()
        DebugLog.write("[helper] stopWatching")
    }

    private func startFsUsage() {
        guard shouldRestart else { return }
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/usr/sbin/fs_usage")
        task.arguments = ["-w", "-t", "\(sampleDuration)", "-f", "pathname"]
        let pipe = Pipe()
        task.standardOutput = pipe
        task.standardError = Pipe()
        let handle = pipe.fileHandleForReading
        outputHandle = handle
        handle.readabilityHandler = { [weak self] handle in
            self?.queue.async {
                self?.consumeData(handle.availableData)
            }
        }
        task.terminationHandler = { [weak self] _ in
            guard let self, self.shouldRestart else { return }
            DispatchQueue.global(qos: .utility).asyncAfter(deadline: .now() + 0.3) {
                self.startFsUsage()
            }
        }
        do {
            try task.run()
            process = task
            DebugLog.write("[helper] fs_usage started")
        } catch {
            pipe.fileHandleForReading.readabilityHandler = nil
            DebugLog.write("[helper] fs_usage failed to start")
        }
    }

    private func consumeData(_ data: Data) {
        guard !data.isEmpty else { return }
        buffer.append(data)
        if buffer.count > 1_000_000 {
            buffer.removeAll(keepingCapacity: true)
            return
        }
        while let range = buffer.range(of: Data([0x0A])) {
            let lineData = buffer.subdata(in: buffer.startIndex..<range.lowerBound)
            buffer.removeSubrange(buffer.startIndex...range.lowerBound)
            if let line = String(data: lineData, encoding: .utf8) {
                handleLine(line)
            }
        }
    }

    private func handleLine(_ line: String) {
        guard !rootPath.isEmpty, line.contains(rootPath) else { return }
        captureDebugLine(line)
        let lower = line.lowercased()
        guard let kind = inferKind(from: lower) else { return }
        guard let (path, processName) = extractPathAndProcess(from: line) else { return }
        let now = CFAbsoluteTimeGetCurrent()
        let key = "\(processName)|\(kind.rawValue)|\(path)"
        if let last = lastEventByKey[key], now - last < throttleInterval {
            return
        }
        lastEventByKey[key] = now
        if let client = connection?.remoteObjectProxy as? PrivilegedHelperClientProtocol {
            client.emitActivity(kind: kind.rawValue, processName: processName, path: path)
        }
    }

    private func inferKind(from line: String) -> ActivityKind? {
        let writeHints = ["write", "pwrite", "truncate", "create", "rename", "unlink", "mkdir", "rmdir"]
        let readHints = ["read", "pread", "open", "stat", "getattr", "mmap"]
        if writeHints.contains(where: { line.contains($0) }) { return .write }
        if readHints.contains(where: { line.contains($0) }) { return .read }
        return nil
    }

    private func extractPathAndProcess(from line: String) -> (String, String)? {
        let parts = line.split(whereSeparator: { $0 == " " || $0 == "\t" })
        guard parts.count >= 4 else { return nil }
        guard let pathStart = parts.firstIndex(where: { $0.hasPrefix(rootPath) }) else { return nil }
        let processName = String(parts[parts.count - 1])
        let pathParts = parts[pathStart..<(parts.count - 2)]
        let path = pathParts.joined(separator: " ")
        return (path, processName)
    }

    private func captureDebugLine(_ line: String) {
        guard debugLinesRemaining > 0 else { return }
        debugLinesRemaining -= 1
        DebugLog.write("[helper] line: \(line)")
    }
}
