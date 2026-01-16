import AppKit

final class SoundManager {
    static let shared = SoundManager()

    private var soundPool: [NSSound] = []
    private var currentSoundIndex = 0
    private let soundPoolSize = 16

    init() {
        // Pre-load sound pool to allow simultaneous playback
        for _ in 0..<soundPoolSize {
            if let sound = NSSound(named: NSSound.Name("Glass")) {
                soundPool.append(sound)
            }
        }
    }

    private func playSound() {
        guard !soundPool.isEmpty else { return }
        let sound = soundPool[currentSoundIndex]
        currentSoundIndex = (currentSoundIndex + 1) % soundPool.count
        sound.stop()  // Stop any current playback to allow immediate restart
        sound.play()
    }

    func playHoverSound() {
        DispatchQueue.global(qos: .userInitiated).async {
            self.playSound()
        }
    }

    func playClickSound() {
        DispatchQueue.global(qos: .userInitiated).async {
            self.playSound()
            Thread.sleep(forTimeInterval: 0.05)
            self.playSound()
        }
    }

    func playSatelliteSelectSound() {
        DispatchQueue.global(qos: .userInitiated).async {
            self.playSound()
            Thread.sleep(forTimeInterval: 0.08)
            self.playSound()
            Thread.sleep(forTimeInterval: 0.05)
            self.playSound()
        }
    }
}
