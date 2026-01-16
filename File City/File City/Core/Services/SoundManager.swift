import AppKit

final class SoundManager {
    static let shared = SoundManager()

    private var satelliteHoverSounds: [NSSound] = []
    private var satelliteHoverIndex = 0

    private var otherHoverSounds: [NSSound] = []
    private var otherHoverIndex = 0

    private var clickSounds: [NSSound] = []
    private var clickIndex = 0

    private let soundPoolSize = 16

    init() {
        // Pre-load sound pools for different sound types
        for _ in 0..<soundPoolSize {
            if let sound = NSSound(named: NSSound.Name("Glass")) {
                satelliteHoverSounds.append(sound)
            }
            if let sound = NSSound(named: NSSound.Name("Pop")) {
                otherHoverSounds.append(sound)
            }
            if let sound = NSSound(named: NSSound.Name("Submarine")) {
                clickSounds.append(sound)
            }
        }
    }

    private func playFromPool(_ pool: inout [NSSound], index: inout Int) {
        guard !pool.isEmpty else { return }
        let sound = pool[index]
        index = (index + 1) % pool.count
        sound.stop()  // Stop any current playback to allow immediate restart
        sound.play()
    }

    func playSatelliteHoverSound() {
        DispatchQueue.global(qos: .userInitiated).async {
            self.playFromPool(&self.satelliteHoverSounds, index: &self.satelliteHoverIndex)
        }
    }

    func playOtherHoverSound() {
        DispatchQueue.global(qos: .userInitiated).async {
            self.playFromPool(&self.otherHoverSounds, index: &self.otherHoverIndex)
        }
    }

    func playClickSound() {
        DispatchQueue.global(qos: .userInitiated).async {
            self.playFromPool(&self.clickSounds, index: &self.clickIndex)
        }
    }
}
