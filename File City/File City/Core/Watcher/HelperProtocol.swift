import Foundation

/// Protocol for XPC communication with the privileged helper
@objc protocol HelperProtocol {
    /// Get the version of the installed helper
    func getVersion(withReply reply: @escaping (String) -> Void)

    /// Uninstall the helper (removes from launchd and deletes binary)
    func uninstall(withReply reply: @escaping (Bool) -> Void)
}
