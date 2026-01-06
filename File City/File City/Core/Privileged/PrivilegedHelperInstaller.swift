import Foundation
import ServiceManagement
import Security

final class PrivilegedHelperInstaller {
    static let shared = PrivilegedHelperInstaller()
    private var isInstalling = false

    func ensureInstalled(completion: @escaping (Bool) -> Void) {
        if isInstalling { return }
        isInstalling = true
        DispatchQueue.global(qos: .utility).async {
            let success = self.installHelper()
            DispatchQueue.main.async {
                self.isInstalling = false
                completion(success)
            }
        }
    }

    private func installHelper() -> Bool {
        var authRef: AuthorizationRef?
        let status = AuthorizationCreate(nil, nil, [.interactionAllowed, .extendRights], &authRef)
        guard status == errAuthorizationSuccess, let authRef else { return false }
        defer { AuthorizationFree(authRef, []) }

        var item = AuthorizationItem(name: kSMRightBlessPrivilegedHelper, valueLength: 0, value: nil, flags: 0)
        var rights = AuthorizationRights(count: 1, items: &item)
        let flags: AuthorizationFlags = [.interactionAllowed, .extendRights, .preAuthorize]
        let copyStatus = AuthorizationCopyRights(authRef, &rights, nil, flags, nil)
        guard copyStatus == errAuthorizationSuccess else { return false }

        var error: Unmanaged<CFError>?
        let blessed = SMJobBless(kSMDomainSystemLaunchd, PrivilegedHelper.bundleIdentifier as CFString, authRef, &error)
        if !blessed {
            if let error {
                let message = String(describing: error.takeRetainedValue())
                DebugLog.write("[helper] SMJobBless failed: \(message)")
            } else {
                DebugLog.write("[helper] SMJobBless failed: unknown error")
            }
        } else {
            DebugLog.write("[helper] SMJobBless succeeded")
        }
        return blessed
    }
}
