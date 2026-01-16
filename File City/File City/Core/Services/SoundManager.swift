import AppKit

final class SoundManager {
    static let shared = SoundManager()

    func playHoverSound() {
        // Soft ping for hovering
        DispatchQueue.global(qos: .userInitiated).async {
            NSSound(named: NSSound.Name("Glass"))?.play()
        }
    }

    func playClickSound() {
        // Two beeps for clicking
        DispatchQueue.global(qos: .userInitiated).async {
            NSSound(named: NSSound.Name("Glass"))?.play()
            Thread.sleep(forTimeInterval: 0.05)
            NSSound(named: NSSound.Name("Glass"))?.play()
        }
    }

    func playSatelliteSelectSound() {
        // Three beeps for satellite selection (more distinctive)
        DispatchQueue.global(qos: .userInitiated).async {
            NSSound(named: NSSound.Name("Glass"))?.play()
            Thread.sleep(forTimeInterval: 0.08)
            NSSound(named: NSSound.Name("Glass"))?.play()
            Thread.sleep(forTimeInterval: 0.05)
            NSSound(named: NSSound.Name("Glass"))?.play()
        }
    }
}
