import Foundation
import ServiceManagement
import Security

/// Manages the privileged helper tool installation and communication
final class HelperManager {
    static let helperLabel = "com.kevintang.filecity.helper"
    private static let helperPath = "/Library/PrivilegedHelperTools/\(helperLabel)"

    /// Check if helper is installed
    static func isHelperInstalled() -> Bool {
        FileManager.default.fileExists(atPath: helperPath)
    }

    /// Check if helper is running by testing socket connection
    static func isHelperRunning() -> Bool {
        let socket = Darwin.socket(AF_UNIX, SOCK_STREAM, 0)
        guard socket >= 0 else { return false }
        defer { close(socket) }

        var addr = sockaddr_un()
        addr.sun_family = sa_family_t(AF_UNIX)
        let socketPath = "/tmp/filecity-activity.sock"
        withUnsafeMutablePointer(to: &addr.sun_path.0) { ptr in
            _ = socketPath.withCString { strncpy(ptr, $0, 104) }
        }

        let result = withUnsafePointer(to: &addr) { ptr in
            ptr.withMemoryRebound(to: sockaddr.self, capacity: 1) { sockPtr in
                Darwin.connect(socket, sockPtr, socklen_t(MemoryLayout<sockaddr_un>.size))
            }
        }
        return result >= 0
    }

    /// Install or update the helper using SMJobBless
    /// Returns true if installation succeeded, false otherwise
    @discardableResult
    static func installHelper() -> Bool {
        NSLog("[HelperManager] installHelper: starting authorization...")
        var authRef: AuthorizationRef?
        var authItem = AuthorizationItem(
            name: kSMRightBlessPrivilegedHelper,
            valueLength: 0,
            value: nil,
            flags: 0
        )
        var authRights = AuthorizationRights(count: 1, items: &authItem)
        let flags: AuthorizationFlags = [.interactionAllowed, .preAuthorize, .extendRights]

        NSLog("[HelperManager] installHelper: calling AuthorizationCreate...")
        let status = AuthorizationCreate(&authRights, nil, flags, &authRef)
        NSLog("[HelperManager] installHelper: AuthorizationCreate returned %d", status)
        guard status == errAuthorizationSuccess, let auth = authRef else {
            NSLog("[HelperManager] Authorization failed with status: %d", status)
            return false
        }
        defer { AuthorizationFree(auth, []) }

        NSLog("[HelperManager] installHelper: calling SMJobBless...")
        var error: Unmanaged<CFError>?
        let result = SMJobBless(
            kSMDomainSystemLaunchd,
            helperLabel as CFString,
            auth,
            &error
        )
        NSLog("[HelperManager] installHelper: SMJobBless returned %@", result ? "true" : "false")

        if !result {
            if let err = error?.takeRetainedValue() {
                NSLog("[HelperManager] SMJobBless failed: %@", String(describing: err))
            } else {
                NSLog("[HelperManager] SMJobBless failed with unknown error")
            }
        } else {
            NSLog("[HelperManager] Helper installed successfully")
        }

        return result
    }

    /// Get version of installed helper via XPC
    static func getHelperVersion(completion: @escaping (String?) -> Void) {
        let connection = NSXPCConnection(machServiceName: helperLabel, options: .privileged)
        connection.remoteObjectInterface = NSXPCInterface(with: HelperProtocol.self)
        connection.resume()

        let helper = connection.remoteObjectProxyWithErrorHandler { error in
            NSLog("[HelperManager] XPC error: %@", error.localizedDescription)
            completion(nil)
        } as? HelperProtocol

        helper?.getVersion { version in
            completion(version)
            connection.invalidate()
        }
    }

    /// Uninstall the helper via XPC
    static func uninstallHelper(completion: @escaping (Bool) -> Void) {
        let connection = NSXPCConnection(machServiceName: helperLabel, options: .privileged)
        connection.remoteObjectInterface = NSXPCInterface(with: HelperProtocol.self)
        connection.resume()

        let helper = connection.remoteObjectProxyWithErrorHandler { error in
            NSLog("[HelperManager] XPC error: %@", error.localizedDescription)
            completion(false)
        } as? HelperProtocol

        helper?.uninstall { success in
            completion(success)
            connection.invalidate()
        }
    }

    /// Ensure helper is installed and running
    /// Returns true if helper is ready, false if installation failed
    static func ensureHelperReady() -> Bool {
        NSLog("[HelperManager] ensureHelperReady called")

        if isHelperRunning() {
            NSLog("[HelperManager] Helper already running")
            return true
        }
        NSLog("[HelperManager] Helper not running")

        if !isHelperInstalled() {
            NSLog("[HelperManager] Helper not installed, attempting to install...")
            if !installHelper() {
                NSLog("[HelperManager] Installation failed")
                return false
            }
            NSLog("[HelperManager] Installation succeeded, waiting for helper to start...")
            // Give it a moment to start
            Thread.sleep(forTimeInterval: 1.0)
        } else {
            NSLog("[HelperManager] Helper is installed but not running")
        }

        let running = isHelperRunning()
        NSLog("[HelperManager] After install, helper running: %@", running ? "yes" : "no")
        return running
    }
}

