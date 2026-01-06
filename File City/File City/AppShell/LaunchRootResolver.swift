import Foundation

enum LaunchRootResolver {
    static func resolve() -> URL? {
        if let envPath = ProcessInfo.processInfo.environment["FILE_CITY_ROOT"], !envPath.isEmpty {
            return urlIfValid(path: envPath)
        }

        var iterator = ProcessInfo.processInfo.arguments.dropFirst().makeIterator()
        while let arg = iterator.next() {
            if arg == "--root", let next = iterator.next() {
                if let url = urlIfValid(path: next) {
                    return url
                }
                continue
            }

            if arg.hasPrefix("-") {
                continue
            }

            if let url = urlIfValid(path: arg) {
                return url
            }
        }

        return nil
    }

    private static func urlIfValid(path: String) -> URL? {
        let expanded = (path as NSString).expandingTildeInPath
        let url = URL(fileURLWithPath: expanded)
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory) else {
            return nil
        }
        return isDirectory.boolValue ? url : url.deletingLastPathComponent()
    }
}
