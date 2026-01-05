import Foundation
import Metal
import CryptoKit

final class TextureGenerator {
    static func generateTexture(device: MTLDevice, seed: String, width: Int = 256, height: Int = 256) -> MTLTexture? {
        let descriptor = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: .rgba8Unorm,
            width: width,
            height: height,
            mipmapped: false
        )
        descriptor.usage = .shaderRead
        
        guard let texture = device.makeTexture(descriptor: descriptor) else { return nil }
        
        var rng = DeterministicRNG(seed: seed)
        
        let rBase = Int(rng.next() % 150) + 50
        let gBase = Int(rng.next() % 150) + 50
        let bBase = Int(rng.next() % 150) + 50
        
        var pixelData = [UInt8](repeating: 0, count: width * height * 4)
        
        for y in 0..<height {
            for x in 0..<width {
                // Simple pattern: Checkerboard + Noise
                let scale = 32
                let check = ((x / scale) + (y / scale)) % 2 == 1
                
                let noise = Int(rng.next() % 41) - 20 // -20 to 20
                
                var r = clamp(value: rBase + (check ? 40 : 0) + noise, min: 0, max: 255)
                var g = clamp(value: gBase + (check ? 40 : 0) + noise, min: 0, max: 255)
                var b = clamp(value: bBase + (check ? 40 : 0) + noise, min: 0, max: 255)
                
                // Draw a "window" if it looks like a building
                let wx = x % 32
                let wy = y % 32
                if wx > 10 && wx < 22 && wy > 10 && wy < 22 {
                    r = 255
                    g = 255
                    b = 200
                }
                
                let index = (y * width + x) * 4
                pixelData[index] = UInt8(r)
                pixelData[index + 1] = UInt8(g)
                pixelData[index + 2] = UInt8(b)
                pixelData[index + 3] = 255 // Alpha
            }
        }
        
        texture.replace(
            region: MTLRegionMake2D(0, 0, width, height),
            mipmapLevel: 0,
            withBytes: pixelData,
            bytesPerRow: width * 4
        )
        
        return texture
    }
    
    private static func clamp(value: Int, min: Int, max: Int) -> Int {
        return value < min ? min : (value > max ? max : value)
    }
}

// Simple LCG (Linear Congruential Generator) for deterministic randomness
struct DeterministicRNG {
    private var state: UInt64
    
    init(seed: String) {
        // Use SHA256 to hash the string seed into a UInt64 state
        let data = seed.data(using: .utf8)!
        let hash = SHA256.hash(data: data)
        // Take first 8 bytes
        let sub = hash.withUnsafeBytes { ptr in
            ptr.load(as: UInt64.self)
        }
        self.state = sub
    }
    
    mutating func next() -> UInt64 {
        // Constants from Knuth/MMIX
        state = state &* 6364136223846793005 &+ 1442695040888963407
        return state
    }
}
