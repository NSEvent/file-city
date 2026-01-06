import Foundation

struct FileActivityEvent {
    let kind: ActivityKind
    let processName: String
    let url: URL
}

final class FileActivityWatcher: NSObject, PrivilegedHelperClientProtocol {
    private let rootURL: URL
    private let onActivity: (FileActivityEvent) -> Void
    private var connection: NSXPCConnection?

    init(rootURL: URL, onActivity: @escaping (FileActivityEvent) -> Void) {
        self.rootURL = rootURL
        self.onActivity = onActivity
    }

    func start() {
        PrivilegedHelperInstaller.shared.ensureInstalled { [weak self] success in
            guard let self, success else { return }
            self.connectIfNeeded()
            self.startWatching()
        }
    }

    func stop() {
        if let proxy = connection?.remoteObjectProxy as? PrivilegedHelperProtocol {
            proxy.stopWatching()
        }
        connection?.invalidate()
        connection = nil
    }

    private func connectIfNeeded() {
        guard connection == nil else { return }
        let connection = NSXPCConnection(machServiceName: PrivilegedHelper.machServiceName, options: .privileged)
        connection.remoteObjectInterface = NSXPCInterface(with: PrivilegedHelperProtocol.self)
        connection.exportedInterface = NSXPCInterface(with: PrivilegedHelperClientProtocol.self)
        connection.exportedObject = self
        connection.invalidationHandler = { [weak self] in
            DebugLog.write("[watcher] connection invalidated")
            self?.connection = nil
        }
        connection.resume()
        DebugLog.write("[watcher] connection resumed")
        self.connection = connection
    }

    private func startWatching() {
        guard let proxy = connection?.remoteObjectProxyWithErrorHandler({ error in
            DebugLog.write("[watcher] remote proxy error: \(error)")
        }) as? PrivilegedHelperProtocol else {
            DebugLog.write("[watcher] missing remote proxy")
            return
        }
        proxy.startWatching(rootPath: rootURL.path) { _ in }
    }

    func emitActivity(kind: Int32, processName: String, path: String) {
        let url = URL(fileURLWithPath: path)
        let activityKind = ActivityKind(rawValue: kind) ?? .read
        DispatchQueue.main.async { [onActivity] in
            onActivity(FileActivityEvent(kind: activityKind, processName: processName, url: url))
        }
    }
}
