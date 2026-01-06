import Foundation
import Darwin

struct FileActivityEvent {
    let kind: ActivityKind
    let processName: String
    let url: URL
}

final class FileActivityWatcher {
    private let rootURL: URL
    private let onActivity: (FileActivityEvent) -> Void
    private var process: Process?
    private var buffer = Data()
    private let queue = DispatchQueue(label: "filecity.fs_usage")
    private var outputHandle: FileHandle?
    private var lastEventByKey: [String: CFTimeInterval] = [:]
    private let throttleInterval: CFTimeInterval = 0.15
    private let sampleDuration: Int = 1
    private var shouldRestart = false

    init(rootURL: URL, onActivity: @escaping (FileActivityEvent) -> Void) {
        self.rootURL = rootURL
        self.onActivity = onActivity
    }

    func start() {
        stop()
        guard getuid() == 0 else { return }
        shouldRestart = true
        DispatchQueue.global(qos: .utility).async { [weak self] in
            guard let self else { return }
            let pids = self.fetchPIDs()
            guard !pids.isEmpty else { return }
            self.startFsUsage(pids: pids)
        }
    }

    private func startFsUsage(pids: [Int]) {
        guard shouldRestart else { return }
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/usr/sbin/fs_usage")
        task.arguments = ["-w", "-t", "\(sampleDuration)", "-f", "pathname"] + pids.map { String($0) }
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
            DispatchQueue.global(qos: .utility).asyncAfter(deadline: .now() + 0.4) {
                self.start()
            }
        }
        do {
            try task.run()
            self.process = task
        } catch {
            pipe.fileHandleForReading.readabilityHandler = nil
        }
    }

    func stop() {
        shouldRestart = false
        if let process {
            process.terminate()
        }
        outputHandle?.readabilityHandler = nil
        outputHandle = nil
        process = nil
        buffer.removeAll()
        lastEventByKey.removeAll()
    }

    private func fetchPIDs() -> [Int] {
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/bin/ps")
        task.arguments = ["-ax", "-o", "pid=,comm=,args="]
        let pipe = Pipe()
        task.standardOutput = pipe
        task.standardError = Pipe()
        do {
            try task.run()
        } catch {
            return []
        }
        task.waitUntilExit()
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        let output = String(data: data, encoding: .utf8) ?? ""
        let lines = output.split(separator: "\n")
        var pids: [Int] = []
        for line in lines {
            let lower = line.lowercased()
            guard lower.contains("codex") || lower.contains("claude") || lower.contains("gemini") else { continue }
            if lower.contains("rg -i") || lower.contains("ps -ax") { continue }
            let parts = line.split(separator: " ", maxSplits: 1, omittingEmptySubsequences: true)
            if let pidPart = parts.first, let pid = Int(pidPart) {
                pids.append(pid)
            }
        }
        return pids
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
        guard line.contains(rootURL.path) else { return }
        guard let processName = line.split(whereSeparator: { $0 == " " || $0 == "\t" }).first.map(String.init) else { return }
        let lower = line.lowercased()
        let kind = inferKind(from: lower)
        guard let kind else { return }
        guard let url = extractURL(from: line) else { return }
        let now = CFAbsoluteTimeGetCurrent()
        let key = "\(processName)|\(kind.rawValue)|\(url.path)"
        if let last = lastEventByKey[key], now - last < throttleInterval {
            return
        }
        lastEventByKey[key] = now
        DispatchQueue.main.async { [onActivity] in
            onActivity(FileActivityEvent(kind: kind, processName: processName, url: url))
        }
    }

    private func inferKind(from line: String) -> ActivityKind? {
        let writeHints = ["write", "pwrite", "truncate", "create", "rename", "unlink", "mkdir", "rmdir"]
        let readHints = ["read", "pread", "open", "stat", "getattr", "mmap"]
        if writeHints.contains(where: { line.contains($0) }) { return .write }
        if readHints.contains(where: { line.contains($0) }) { return .read }
        return nil
    }

    private func extractURL(from line: String) -> URL? {
        guard let range = line.range(of: rootURL.path) else { return nil }
        let tail = line[range.lowerBound...]
        let pathToken = tail.split(whereSeparator: { $0 == " " || $0 == "\t" }).first
        guard let pathToken else { return nil }
        return URL(fileURLWithPath: String(pathToken))
    }
}
