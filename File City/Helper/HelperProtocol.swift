import Foundation

/// Protocol for XPC communication with the privileged helper
@objc protocol HelperProtocol {
    /// Get the version of the installed helper
    func getVersion(withReply reply: @escaping (String) -> Void)

    /// Uninstall the helper (removes from launchd and deletes binary)
    func uninstall(withReply reply: @escaping (Bool) -> Void)
}

/// Shared constants between app and helper
enum HelperConstants {
    static let machServiceName = "com.kevintang.filecity.helper"
    static let socketPath = "/tmp/filecity-activity.sock"
    static let helperVersion = "1.0"
}
