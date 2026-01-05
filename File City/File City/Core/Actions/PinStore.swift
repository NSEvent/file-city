import Foundation

final class PinStore {
    private var pins: Set<String> = []

    func isPinned(pathHash: String) -> Bool {
        pins.contains(pathHash)
    }

    func setPinned(_ pinned: Bool, pathHash: String) {
        if pinned {
            pins.insert(pathHash)
        } else {
            pins.remove(pathHash)
        }
    }
}
