import Foundation

final class PinStore {
    private var pins: Set<String> = []
    private var pinURLs: [String: URL] = [:]

    func isPinned(pathHash: String) -> Bool {
        pins.contains(pathHash)
    }

    func setPinned(_ pinned: Bool, pathHash: String, url: URL? = nil) {
        if pinned {
            pins.insert(pathHash)
            if let url {
                pinURLs[pathHash] = url
            }
        } else {
            pins.remove(pathHash)
            pinURLs.removeValue(forKey: pathHash)
        }
    }

    func allPinnedURLs() -> [URL] {
        Array(pinURLs.values).sorted { $0.path < $1.path }
    }

    static func pathHash(_ url: URL) -> String {
        var hasher = Hasher()
        hasher.combine(url.path)
        return String(hasher.finalize())
    }
}
