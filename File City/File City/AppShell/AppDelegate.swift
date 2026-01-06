import AppKit

final class AppDelegate: NSObject, NSApplicationDelegate {
    private static var pendingOpenURL: URL?

    func applicationDidFinishLaunching(_ notification: Notification) {
        observeWindowEvents()
        bringToFront()
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        true
    }

    func application(_ application: NSApplication, open urls: [URL]) {
        guard let url = urls.first else { return }
        let target = url.hasDirectoryPath ? url : url.deletingLastPathComponent()
        Self.pendingOpenURL = target
        NotificationCenter.default.post(name: .fileCityOpenURL, object: target)
        bringToFront()
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows: Bool) -> Bool {
        bringToFront()
        return true
    }

    private func observeWindowEvents() {
        let center = NotificationCenter.default
        let names: [Notification.Name] = [
            NSWindow.didBecomeMainNotification,
            NSWindow.didBecomeKeyNotification
        ]
        for name in names {
            center.addObserver(forName: name, object: nil, queue: .main) { notification in
                guard let window = notification.object as? NSWindow else { return }
                self.focus(window: window)
            }
        }
    }

    private func bringToFront() {
        let delays: [TimeInterval] = [0.0, 0.05, 0.1, 0.2, 0.4, 0.8]
        for delay in delays {
            DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
                self.ensureVisible()
            }
        }
    }

    private func ensureVisible() {
        NSApp.unhide(nil)
        NSApp.activate(ignoringOtherApps: true)
        let windows = NSApp.windows
        if windows.isEmpty { return }
        for window in windows {
            focus(window: window)
        }
    }

    private func focus(window: NSWindow) {
        window.orderFrontRegardless()
        window.makeKeyAndOrderFront(nil)
    }

    static func takePendingOpenURL() -> URL? {
        defer { pendingOpenURL = nil }
        return pendingOpenURL
    }
}
