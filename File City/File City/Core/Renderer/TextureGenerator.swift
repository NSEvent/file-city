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
        
        var pixelData = [UInt8](repeating: 0, count: width * height * 4)
        
        // Detect Theme
        let lowerSeed = seed.lowercased()
        
        if lowerSeed.contains("tiktok") {
            drawTikTok(width: width, height: height, pixels: &pixelData)
        } else if lowerSeed.contains("file-city") || lowerSeed.contains("file city") {
            drawFileCity(width: width, height: height, pixels: &pixelData)
        } else if lowerSeed.contains("pokemon") {
            drawPokemon(width: width, height: height, pixels: &pixelData)
        } else if lowerSeed.contains("msg") || lowerSeed.contains("chat") {
            drawIMessage(width: width, height: height, pixels: &pixelData)
        } else if lowerSeed.contains("rust") {
            drawRust(width: width, height: height, pixels: &pixelData)
        } else if lowerSeed.contains("python") {
            drawPython(width: width, height: height, pixels: &pixelData)
        } else if lowerSeed.contains("ios") || lowerSeed.contains("app") {
            drawIOS(width: width, height: height, pixels: &pixelData)
        } else {
            drawDefault(seed: seed, width: width, height: height, pixels: &pixelData)
        }
        
        texture.replace(
            region: MTLRegionMake2D(0, 0, width, height),
            mipmapLevel: 0,
            withBytes: pixelData,
            bytesPerRow: width * 4
        )
        
        return texture
    }
    
    // MARK: - Themes
    
    private static func drawTikTok(width: Int, height: Int, pixels: inout [UInt8]) {
        // Black background
        // Cyan and Magenta glitch circle/note
        for y in 0..<height {
            for x in 0..<width {
                let dx = x - width / 2
                let dy = y - height / 2
                let dist = sqrt(Double(dx*dx + dy*dy))
                
                // Base black
                var r: Int = 20, g: Int = 20, b: Int = 20
                
                // Music Note Shape (Approximated by circles/rects)
                // Glitch effect: Cyan shifted left, Magenta shifted right
                
                let shape = { (ox: Int, oy: Int) -> Bool in
                    // Simple "Note" shape: Circle at bottom left, Stem up, Flag right
                    let nx = ox + 40
                    let ny = oy + 40
                    let head = sqrt(Double((nx-40)*(nx-40) + (ny-160)*(ny-160))) < 30
                    let stem = nx > 60 && nx < 80 && ny > 40 && ny < 160
                    let flag = nx >= 80 && nx < 120 && ny > 40 && ny < 80 && (nx - 80) < (ny - 40) + 40
                    return head || stem
                }
                
                if shape(x + 5, y) { // Cyan channel (Shifted)
                    b = 255
                    g = 255
                }
                if shape(x - 5, y) { // Magenta channel (Shifted)
                    r = 255
                }
                if shape(x, y) { // White overlap
                   if r == 255 && b == 255 {
                       // Center is white
                       r = 255; g = 255; b = 255;
                   }
                }
                
                let index = (y * width + x) * 4
                pixels[index] = UInt8(clamp(value: r, min: 0, max: 255))
                pixels[index + 1] = UInt8(clamp(value: g, min: 0, max: 255))
                pixels[index + 2] = UInt8(clamp(value: b, min: 0, max: 255))
                pixels[index + 3] = 255
            }
        }
    }
    
    private static func drawFileCity(width: Int, height: Int, pixels: inout [UInt8]) {
        // Floppy Disk Icon
        for y in 0..<height {
            for x in 0..<width {
                // Background Blue
                var r = 50, g = 100, b = 200
                
                let nx = Float(x) / Float(width)
                let ny = Float(y) / Float(height)
                
                // Floppy Body (Rect)
                if nx > 0.1 && nx < 0.9 && ny > 0.1 && ny < 0.9 {
                    r = 80; g = 80; b = 220
                    
                    // White Label (Top)
                    if nx > 0.2 && nx < 0.8 && ny > 0.55 && ny < 0.9 {
                         r = 240; g = 240; b = 240
                    }
                    
                    // Metal Shutter (Bottom)
                    if nx > 0.25 && nx < 0.75 && ny > 0.1 && ny < 0.4 {
                        r = 180; g = 180; b = 190
                        // Sliding window
                        if nx > 0.3 && nx < 0.45 && ny > 0.15 && ny < 0.35 {
                            r = 40; g = 40; b = 40
                        }
                    }
                }

                let index = (y * width + x) * 4
                pixels[index] = UInt8(r)
                pixels[index + 1] = UInt8(g)
                pixels[index + 2] = UInt8(b)
                pixels[index + 3] = 255
            }
        }
    }
    
    private static func drawPokemon(width: Int, height: Int, pixels: inout [UInt8]) {
        // Pokeball: Red Top, White Bottom, Black Band
        for y in 0..<height {
            for x in 0..<width {
                let dx = x - width / 2
                let dy = y - height / 2
                let dist = sqrt(Double(dx*dx + dy*dy))
                
                var r = 200, g = 200, b = 200 // Default background (grey)
                
                if dist < 110 { // Ball
                    if dy > 5 { // Top (Inverted Y in Metal usually? let's assume standard image coords where y=0 is top... wait, Metal texture 0,0 is usually top-left for replaceRegion but rendering depends on UVs. Let's assume dy > 0 is one half)
                        // Actually, let's just draw geometry
                        if dy < -10 {
                             // Top
                             r = 220; g = 40; b = 40
                        } else if dy > 10 {
                             // Bottom
                             r = 240; g = 240; b = 240
                        } else {
                             // Band
                             r = 20; g = 20; b = 20
                        }
                    } else { // dy <= 5
                         if dy < -10 { r = 220; g = 40; b = 40 }
                         else if dy > 10 { r = 240; g = 240; b = 240 }
                         else { r = 20; g = 20; b = 20 }
                    }
                    
                    // Button
                    if dist < 30 {
                        r = 20; g = 20; b = 20 // Outer rim
                        if dist < 20 {
                            r = 255; g = 255; b = 255 // Inner button
                        }
                    }
                }

                let index = (y * width + x) * 4
                pixels[index] = UInt8(r)
                pixels[index + 1] = UInt8(g)
                pixels[index + 2] = UInt8(b)
                pixels[index + 3] = 255
            }
        }
    }

    private static func drawIMessage(width: Int, height: Int, pixels: inout [UInt8]) {
        // Green/Blue Bubble
        for y in 0..<height {
            for x in 0..<width {
                // Background White
                var r = 255, g = 255, b = 255
                
                let dx = Double(x - width / 2)
                let dy = Double(y - height / 2)
                
                // Bubble Shape (Rounded Rect)
                let inX = abs(dx) < 80
                let inY = abs(dy) < 50
                let distCorner = sqrt(pow(abs(dx)-80, 2) + pow(abs(dy)-50, 2))
                
                if (inX && inY) || (abs(dx) < 80 && abs(dy) < 70) || (abs(dx) < 100 && abs(dy) < 50) || (distCorner < 20) {
                     // Blue gradient
                     let gradient = Double(y) / Double(height)
                     r = 0
                     g = Int(120 + gradient * 50)
                     b = 255
                }
                
                // Tail
                if x > 160 && x < 190 && y > 150 && y < 180 {
                     if x - 160 < 180 - y {
                         r = 0; g = 120; b = 255
                     }
                }

                let index = (y * width + x) * 4
                pixels[index] = UInt8(r)
                pixels[index + 1] = UInt8(g)
                pixels[index + 2] = UInt8(b)
                pixels[index + 3] = 255
            }
        }
    }
    
    private static func drawRust(width: Int, height: Int, pixels: inout [UInt8]) {
        var rng = DeterministicRNG(seed: "rust")
        for y in 0..<height {
            for x in 0..<width {
                let noise = Int(rng.next() % 50)
                let gear = sqrt(pow(Double(x - width/2), 2) + pow(Double(y - height/2), 2)) < 80
                var r = 40, g = 40, b = 40
                
                if gear {
                    // Rust Orange
                    r = 180 + noise
                    g = 90 + noise
                    b = 40
                    
                    // Holes
                    if (x % 40 > 30) { r -= 40; g -= 20 }
                }
                
                let index = (y * width + x) * 4
                pixels[index] = UInt8(clamp(value: r, min: 0, max: 255))
                pixels[index + 1] = UInt8(clamp(value: g, min: 0, max: 255))
                pixels[index + 2] = UInt8(clamp(value: b, min: 0, max: 255))
                pixels[index + 3] = 255
            }
        }
    }
    
    private static func drawPython(width: Int, height: Int, pixels: inout [UInt8]) {
        for y in 0..<height {
            for x in 0..<width {
                var r = 50, g = 50, b = 50
                
                // Blue and Yellow snakes (Approximated by sine waves)
                let ny = Double(y) / 20.0
                let sinX = sin(ny) * 20.0
                
                if abs(Double(x - width/3) + sinX) < 15 {
                    // Blue Snake
                    r = 50; g = 100; b = 200
                }
                
                if abs(Double(x - 2*width/3) - sinX) < 15 {
                    // Yellow Snake
                    r = 220; g = 200; b = 50
                }
                
                let index = (y * width + x) * 4
                pixels[index] = UInt8(r)
                pixels[index + 1] = UInt8(g)
                pixels[index + 2] = UInt8(b)
                pixels[index + 3] = 255
            }
        }
    }

    private static func drawIOS(width: Int, height: Int, pixels: inout [UInt8]) {
        for y in 0..<height {
            for x in 0..<width {
                // Apple-esque rounding
                var r = 240, g = 240, b = 240
                
                // App Icon grid
                let gx = (x % 64)
                let gy = (y % 64)
                
                if gx > 10 && gx < 54 && gy > 10 && gy < 54 {
                    // Colorful icons
                    r = (x * 5) % 255
                    g = (y * 5) % 255
                    b = 200
                }
                
                let index = (y * width + x) * 4
                pixels[index] = UInt8(r)
                pixels[index + 1] = UInt8(g)
                pixels[index + 2] = UInt8(b)
                pixels[index + 3] = 255
            }
        }
    }

    private static func drawDefault(seed: String, width: Int, height: Int, pixels: inout [UInt8]) {
        var rng = DeterministicRNG(seed: seed)
        
        let rBase = Int(rng.next() % 150) + 50
        let gBase = Int(rng.next() % 150) + 50
        let bBase = Int(rng.next() % 150) + 50
        
        for y in 0..<height {
            for x in 0..<width {
                // Simple pattern: Checkerboard + Noise
                let scale = 32
                let check = ((x / scale) + (y / scale)) % 2 == 1
                
                let noise = Int(rng.next() % 41) - 20 // -20 to 20
                
                var r = clamp(value: rBase + (check ? 40 : 0) + noise, min: 0, max: 255)
                var g = clamp(value: gBase + (check ? 40 : 0) + noise, min: 0, max: 255)
                var b = clamp(value: bBase + (check ? 40 : 0) + noise, min: 0, max: 255)
                
                // Windows
                let wx = x % 32
                let wy = y % 32
                if wx > 10 && wx < 22 && wy > 10 && wy < 22 {
                    r = 255
                    g = 255
                    b = 200
                }
                
                let index = (y * width + x) * 4
                pixels[index] = UInt8(r)
                pixels[index + 1] = UInt8(g)
                pixels[index + 2] = UInt8(b)
                pixels[index + 3] = 255
            }
        }
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
