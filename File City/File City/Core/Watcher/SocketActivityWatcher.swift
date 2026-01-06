import Foundation

/// Connects to the filecity-watcher helper daemon via Unix socket to receive file activity events.
/// The helper runs with sudo and monitors LLM tool file access, sending events over the socket.
final class SocketActivityWatcher {
    private let socketPath: String
    private let rootURL: URL
    private let onActivity: (FileActivityEvent) -> Void
    private var socket: Int32 = -1
    private var buffer = Data()
    private let queue = DispatchQueue(label: "filecity.socket")
    private var shouldReconnect = false
    private var readSource: DispatchSourceRead?

    init(socketPath: String = "/tmp/filecity-activity.sock", rootURL: URL, onActivity: @escaping (FileActivityEvent) -> Void) {
        self.socketPath = socketPath
        self.rootURL = rootURL
        self.onActivity = onActivity
    }

    func start() {
        stop()
        shouldReconnect = true
        attemptConnect()
    }

    func stop() {
        shouldReconnect = false
        readSource?.cancel()
        readSource = nil
        if socket >= 0 {
            close(socket)
            socket = -1
        }
        buffer.removeAll()
    }

    private func attemptConnect() {
        guard shouldReconnect else { return }
        queue.async { [weak self] in
            self?.connect()
        }
    }

    private func connect() {
        guard shouldReconnect else { return }
        socket = Darwin.socket(AF_UNIX, SOCK_STREAM, 0)
        guard socket >= 0 else {
            scheduleReconnect()
            return
        }

        var addr = sockaddr_un()
        addr.sun_family = sa_family_t(AF_UNIX)
        withUnsafeMutablePointer(to: &addr.sun_path.0) { ptr in
            _ = socketPath.withCString { strncpy(ptr, $0, 104) }
        }

        let connectResult = withUnsafePointer(to: &addr) { ptr in
            ptr.withMemoryRebound(to: sockaddr.self, capacity: 1) { sockPtr in
                Darwin.connect(socket, sockPtr, socklen_t(MemoryLayout<sockaddr_un>.size))
            }
        }

        guard connectResult >= 0 else {
            close(socket)
            socket = -1
            scheduleReconnect()
            return
        }

        NSLog("[SocketActivityWatcher] Connected to helper daemon")
        startReading()
    }

    private func scheduleReconnect() {
        guard shouldReconnect else { return }
        queue.asyncAfter(deadline: .now() + 2.0) { [weak self] in
            self?.attemptConnect()
        }
    }

    private func startReading() {
        let source = DispatchSource.makeReadSource(fileDescriptor: socket, queue: queue)
        source.setEventHandler { [weak self] in
            self?.readAvailable()
        }
        source.setCancelHandler { [weak self] in
            guard let self, self.socket >= 0 else { return }
            close(self.socket)
            self.socket = -1
            self.scheduleReconnect()
        }
        readSource = source
        source.resume()
    }

    private func readAvailable() {
        var buf = [UInt8](repeating: 0, count: 4096)
        let bytesRead = recv(socket, &buf, buf.count, 0)
        if bytesRead <= 0 {
            readSource?.cancel()
            return
        }
        buffer.append(contentsOf: buf[0..<bytesRead])
        processBuffer()
    }

    private func processBuffer() {
        while let newlineIndex = buffer.firstIndex(of: 0x0A) {
            let lineData = buffer[buffer.startIndex..<newlineIndex]
            buffer.removeSubrange(buffer.startIndex...newlineIndex)

            guard let line = String(data: Data(lineData), encoding: .utf8) else { continue }
            handleLine(line)
        }
    }

    private func handleLine(_ line: String) {
        // Format: process|kind|path
        let parts = line.split(separator: "|", maxSplits: 2, omittingEmptySubsequences: false)
        guard parts.count == 3 else { return }

        let processName = String(parts[0])
        let kindStr = String(parts[1])
        let path = String(parts[2])

        // Only handle events within our root
        guard path.hasPrefix(rootURL.path) else { return }

        let kind: ActivityKind
        switch kindStr {
        case "read":
            kind = .read
        case "write":
            kind = .write
        default:
            return
        }

        let url = URL(fileURLWithPath: path)
        DispatchQueue.main.async { [onActivity] in
            onActivity(FileActivityEvent(kind: kind, processName: processName, url: url))
        }
    }
}
