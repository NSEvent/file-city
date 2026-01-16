import AVFoundation
import Foundation

final class SoundManager {
    static let shared = SoundManager()

    private var audioEngine: AVAudioEngine
    private var mixerNode: AVAudioMixerNode

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
        playSineWave(frequency: 800, duration: 0.1, volume: 0.15)
    }

    func playClickSound() {
        // Short beep for clicking
        playSineWave(frequency: 1200, duration: 0.15, volume: 0.25)
    }

    func playSatelliteSelectSound() {
        // Ascending tone for satellite selection
        let queue = DispatchQueue.global(qos: .userInitiated)
        queue.async {
            self.playSineWave(frequency: 600, duration: 0.1, volume: 0.2)
            Thread.sleep(forTimeInterval: 0.05)
            self.playSineWave(frequency: 900, duration: 0.15, volume: 0.2)
        }
    }

    private func playSineWave(frequency: Float, duration: TimeInterval, volume: Float) {
        let format = audioEngine.outputNode.outputFormat(forBus: 0)
        let sampleRateDouble = format.sampleRate
        let sampleRate = Float(sampleRateDouble)
        let sampleCount = Int(sampleRate * Float(duration))

        // Create audio buffer
        guard let format = AVAudioFormat(standardFormatWithSampleRate: Double(sampleRate), channels: 1) else {
            return
        }

        guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(sampleCount)) else {
            return
        }

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

        // Create player node
        let playerNode = AVAudioPlayerNode()
        audioEngine.attach(playerNode)

        // Connect to mixer
        audioEngine.connect(playerNode, to: mixerNode, format: format)

        do {
            try audioEngine.start()
            playerNode.play()
            playerNode.scheduleBuffer(buffer) {
                self.audioEngine.detach(playerNode)
            }
        } catch {
            NSLog("[SoundManager] Failed to play sound: %@", error.localizedDescription)
        }
    }
}
