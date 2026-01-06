import Foundation

@objc protocol PrivilegedHelperProtocol {
    func startWatching(rootPath: String, reply: @escaping (Bool) -> Void)
    func stopWatching()
}

@objc protocol PrivilegedHelperClientProtocol {
    func emitActivity(kind: Int32, processName: String, path: String)
}
