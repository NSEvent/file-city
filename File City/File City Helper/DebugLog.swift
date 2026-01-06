import Foundation

enum DebugLog {
    private static let logURL = URL(fileURLWithPath: "/tmp/filecity-helper.log")

    static func write(_ message: String) {
        let line = "\(message)\n"
        guard let data = line.data(using: .utf8) else { return }
        if FileManager.default.fileExists(atPath: logURL.path) {
            if let handle = try? FileHandle(forWritingTo: logURL) {
                defer { try? handle.close() }
                handle.seekToEndOfFile()
                try? handle.write(contentsOf: data)
            }
        } else {
            try? data.write(to: logURL)
        }
    }
}
