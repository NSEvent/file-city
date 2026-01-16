import AVFoundation
import Foundation

final class SoundManager {
    static let shared = SoundManager()

    private var audioEngine: AVAudioEngine
    private var mixerNode: AVAudioMixerNode
    private var activePlayerNodes: [AVAudioPlayerNode] = []
    private let playerLock = NSLock()

    init() {
        audioEngine = AVAudioEngine()
        mixerNode = audioEngine.mainMixerNode

        do {
            try audioEngine.start()
        } catch {
            NSLog("[SoundManager] Failed to start audio engine: %@", error.localizedDescription)
        }
    }

    func playHoverSound() {
        // Soft ping for hovering over objects
        DispatchQueue.global(qos: .userInitiated).async {
            self.playSineWave(frequency: 800, duration: 0.1, volume: 0.15)
        }
    }

    func playClickSound() {
        // Short beep for clicking
        DispatchQueue.global(qos: .userInitiated).async {
            self.playSineWave(frequency: 1200, duration: 0.15, volume: 0.25)
        }
    }

    func playSatelliteSelectSound() {
        // Ascending tone for satellite selection
        DispatchQueue.global(qos: .userInitiated).async {
            self.playSineWave(frequency: 600, duration: 0.1, volume: 0.2)
            Thread.sleep(forTimeInterval: 0.05)
            self.playSineWave(frequency: 900, duration: 0.15, volume: 0.2)
        }
    }

    private func playSineWave(frequency: Float, duration: TimeInterval, volume: Float) {
        // Check if audio engine is running
        guard audioEngine.attachedNodes.count >= 0 else {
            return
        }

        let sampleRate: Float = 44100
        let sampleCount = Int(sampleRate * Float(duration))

        // Create audio buffer
        let format = AVAudioFormat(standardFormatWithSampleRate: Double(sampleRate), channels: 1)!
        let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(sampleCount))!
        buffer.frameLength = AVAudioFrameCount(sampleCount)

        // Fill buffer with sine wave
        if let channelData = buffer.floatChannelData {
            let data = channelData[0]
            let phaseIncrement = (2.0 * Float.pi * frequency) / sampleRate

            for i in 0..<sampleCount {
                let phase = phaseIncrement * Float(i)
                // Fade in/out for smoother sound
                let envelope: Float
                let fadeFrames = Int(sampleRate * 0.01) // 10ms fade
                if i < fadeFrames {
                    envelope = Float(i) / Float(fadeFrames)
                } else if i > sampleCount - fadeFrames {
                    let remainingFrames = sampleCount - i
                    envelope = Float(remainingFrames) / Float(fadeFrames)
                } else {
                    envelope = 1.0
                }
                data[i] = sin(phase) * volume * envelope
            }
        }

        // Create player node and keep reference
        let playerNode = AVAudioPlayerNode()

        playerLock.lock()
        defer { playerLock.unlock() }

        // Only attach if audio engine is running
        guard !audioEngine.attachedNodes.contains(playerNode) else {
            return
        }

        audioEngine.attach(playerNode)
        activePlayerNodes.append(playerNode)

        // Connect to mixer
        audioEngine.connect(playerNode, to: mixerNode, format: format)

        do {
            // Ensure engine is running
            if !audioEngine.isRunning {
                try audioEngine.start()
            }

            playerNode.play()
            playerNode.scheduleBuffer(buffer) { [weak self] in
                self?.playerLock.lock()
                self?.activePlayerNodes.removeAll { $0 === playerNode }
                self?.playerLock.unlock()
                self?.audioEngine.detach(playerNode)
            }
        } catch {
            playerLock.lock()
            activePlayerNodes.removeAll { $0 === playerNode }
            playerLock.unlock()
            audioEngine.detach(playerNode)
            NSLog("[SoundManager] Failed to play sound: %@", error.localizedDescription)
        }
    }
}
