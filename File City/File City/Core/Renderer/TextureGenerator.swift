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
        } else if lowerSeed.contains("ai") || lowerSeed.contains("bot") || lowerSeed.contains("gpt") {
            drawAI(width: width, height: height, pixels: &pixelData)
        } else if lowerSeed.contains("bank") || lowerSeed.contains("money") || lowerSeed.contains("finance") || lowerSeed.contains("card") {
            drawFinance(width: width, height: height, pixels: &pixelData)
        } else if lowerSeed.contains("real") || lowerSeed.contains("estate") || lowerSeed.contains("house") || lowerSeed.contains("mortgage") || lowerSeed.contains("rent") || lowerSeed.contains("zillow") {
            drawRealEstate(width: width, height: height, pixels: &pixelData)
        } else if lowerSeed.contains("audio") || lowerSeed.contains("voice") || lowerSeed.contains("sound") || lowerSeed.contains("speech") || lowerSeed.contains("say") || lowerSeed.contains("dtmf") || lowerSeed.contains("mouth") {
            drawAudio(width: width, height: height, pixels: &pixelData)
        } else if lowerSeed.contains("camera") || lowerSeed.contains("photo") || lowerSeed.contains("image") || lowerSeed.contains("video") || lowerSeed.contains("face") || lowerSeed.contains("glitch") {
            drawCamera(width: width, height: height, pixels: &pixelData)
        } else if lowerSeed.contains("web") || lowerSeed.contains("chrome") || lowerSeed.contains("browser") || lowerSeed.contains("link") || lowerSeed.contains("site") || lowerSeed.contains("scrape") {
            drawWeb(width: width, height: height, pixels: &pixelData)
        } else if lowerSeed.contains("swift") {
            drawSwift(width: width, height: height, pixels: &pixelData)
        } else if lowerSeed.contains("code") || lowerSeed.contains("json") || lowerSeed.contains("js") || lowerSeed.contains("c++") {
            drawCode(width: width, height: height, pixels: &pixelData)
        } else if lowerSeed.contains("text") || lowerSeed.contains("md") || lowerSeed.contains("doc") {
            drawTextDoc(width: width, height: height, pixels: &pixelData)
        } else if lowerSeed.contains("img") || lowerSeed.contains("png") || lowerSeed.contains("jpg") {
            drawImageFile(width: width, height: height, pixels: &pixelData)
        } else if lowerSeed.contains("audio_file") || lowerSeed.contains("mp3") || lowerSeed.contains("wav") {
            drawAudioFile(width: width, height: height, pixels: &pixelData)
        } else if lowerSeed.contains("video_file") || lowerSeed.contains("mp4") || lowerSeed.contains("mov") {
            drawVideoFile(width: width, height: height, pixels: &pixelData)
        } else if lowerSeed.contains("archive_file") || lowerSeed.contains("zip") || lowerSeed.contains("tar") {
            drawArchiveFile(width: width, height: height, pixels: &pixelData)
        } else if lowerSeed.contains("db_file") || lowerSeed.contains("sql") || lowerSeed.contains("sqlite") {
            drawDatabaseFile(width: width, height: height, pixels: &pixelData)
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
    
    private static func drawAudioFile(width: Int, height: Int, pixels: inout [UInt8]) {
        // Purple with music note
        for y in 0..<height {
            for x in 0..<width {
                var r = 150, g = 100, b = 255
                
                // Note shape (simplified)
                let dx = x - width/2
                let dy = y - height/2
                
                // Circle head
                if (dx-10)*(dx-10) + (dy+20)*(dy+20) < 200 {
                    r = 255; g = 255; b = 255
                }
                // Stem
                if dx > 0 && dx < 10 && dy > -40 && dy < 20 {
                    r = 255; g = 255; b = 255
                }
                // Flag
                if dx >= 10 && dx < 30 && dy > -40 && dy < -20 {
                    r = 255; g = 255; b = 255
                }
                
                let index = (y * width + x) * 4
                pixels[index] = UInt8(r)
                pixels[index + 1] = UInt8(g)
                pixels[index + 2] = UInt8(b)
                pixels[index + 3] = 255
            }
        }
    }

    private static func drawVideoFile(width: Int, height: Int, pixels: inout [UInt8]) {
        // Film strip teal
        for y in 0..<height {
            for x in 0..<width {
                var r = 0, g = 150, b = 150
                
                // Film holes
                if x < 40 || x > width - 40 {
                    r = 20; g = 20; b = 20
                    if (y % 40) > 20 && x > 10 && x < 30 { r = 255; g = 255; b = 255 } // Left holes
                    if (y % 40) > 20 && x > width - 30 && x < width - 10 { r = 255; g = 255; b = 255 } // Right holes
                }
                
                let index = (y * width + x) * 4
                pixels[index] = UInt8(r)
                pixels[index + 1] = UInt8(g)
                pixels[index + 2] = UInt8(b)
                pixels[index + 3] = 255
            }
        }
    }

    private static func drawArchiveFile(width: Int, height: Int, pixels: inout [UInt8]) {
        // Brown box with zipper
        for y in 0..<height {
            for x in 0..<width {
                var r = 160, g = 130, b = 100
                
                // Zipper
                if abs(x - width/2) < 15 {
                    r = 100; g = 100; b = 100
                    if (y / 10 + x / 10) % 2 == 0 {
                        r = 200; g = 200; b = 100 // Gold teeth
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

    private static func drawDatabaseFile(width: Int, height: Int, pixels: inout [UInt8]) {
        // Grey cylinder stack
        for y in 0..<height {
            for x in 0..<width {
                var r = 200, g = 200, b = 200
                
                // Stack layers
                if (y % 60) > 50 {
                    r = 150; g = 150; b = 150 // Separator
                }
                
                // Shading for 3D effect
                let nx = Double(x)/Double(width)
                if nx < 0.2 || nx > 0.8 {
                    r -= 50; g -= 50; b -= 50
                }
                
                let index = (y * width + x) * 4
                pixels[index] = UInt8(r)
                pixels[index + 1] = UInt8(g)
                pixels[index + 2] = UInt8(b)
                pixels[index + 3] = 255
            }
        }
    }
    
    private static func drawSwift(width: Int, height: Int, pixels: inout [UInt8]) {
        // Orange with white diagonal shape (abstract bird)
        for y in 0..<height {
            for x in 0..<width {
                var r = 250, g = 120, b = 20
                
                // Abstract curve
                let nx = Double(x)/Double(width)
                let ny = Double(y)/Double(height)
                let curve = sin(nx * 3.14) * 0.5 + 0.2
                
                if abs(ny - curve) < 0.15 {
                    r = 255; g = 255; b = 255
                }
                
                let index = (y * width + x) * 4
                pixels[index] = UInt8(r)
                pixels[index + 1] = UInt8(g)
                pixels[index + 2] = UInt8(b)
                pixels[index + 3] = 255
            }
        }
    }

    private static func drawCode(width: Int, height: Int, pixels: inout [UInt8]) {
        // Dark background with colored syntax highlighting lines
        for y in 0..<height {
            for x in 0..<width {
                var r = 30, g = 30, b = 35 // Dark IDE bg
                
                // Lines of code
                if (y % 20) > 10 {
                    // "Text"
                    if x > 20 && x < width - 20 {
                        let seg = (x / 10) % 5
                        if seg == 0 { r = 200; g = 100; b = 200 } // Keyword
                        else if seg == 2 { r = 100; g = 200; b = 255 } // Var
                        else { r = 180; g = 180; b = 180 } // Normal
                        
                        // Random gaps
                        if (x + y) % 7 == 0 { r = 30; g = 30; b = 35 }
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

    private static func drawTextDoc(width: Int, height: Int, pixels: inout [UInt8]) {
        // White paper with lines
        for y in 0..<height {
            for x in 0..<width {
                var r = 245, g = 245, b = 245
                
                // Lines
                if (y % 25) > 22 {
                     r = 200; g = 200; b = 220
                }
                
                // Margins
                if x < 30 || x > width - 30 {
                    r = 230; g = 230; b = 230
                }
                
                let index = (y * width + x) * 4
                pixels[index] = UInt8(r)
                pixels[index + 1] = UInt8(g)
                pixels[index + 2] = UInt8(b)
                pixels[index + 3] = 255
            }
        }
    }

    private static func drawImageFile(width: Int, height: Int, pixels: inout [UInt8]) {
        // Image placeholder icon (Mountain/Sun)
        for y in 0..<height {
            for x in 0..<width {
                var r = 220, g = 220, b = 230
                
                let nx = Double(x)/Double(width)
                let ny = Double(y)/Double(height)
                
                // Sun
                let dx = nx - 0.75
                let dy = ny - 0.25
                if sqrt(dx*dx + dy*dy) < 0.1 {
                    r = 255; g = 200; b = 50
                }
                
                // Mountains
                let m1 = 1.0 - abs(nx - 0.3) * 2.5
                let m2 = 1.0 - abs(nx - 0.7) * 2.0
                if ny > (1.0 - max(m1, m2) * 0.5) {
                    r = 100; g = 180; b = 100
                }
                
                let index = (y * width + x) * 4
                pixels[index] = UInt8(r)
                pixels[index + 1] = UInt8(g)
                pixels[index + 2] = UInt8(b)
                pixels[index + 3] = 255
            }
        }
    }
    
    private static func drawRealEstate(width: Int, height: Int, pixels: inout [UInt8]) {
        // Brick red with roof
        for y in 0..<height {
            for x in 0..<width {
                var r = 180, g = 80, b = 60 // Brick
                if (x / 20 + y / 10) % 2 == 0 {
                    r -= 20; g -= 10
                }
                
                // Roof
                if Double(y) < Double(height) / 3.0 {
                    let dx = abs(Double(x - width / 2))
                    let roofY = dx
                    if Double(y) > roofY {
                        r = 80; g = 40; b = 30
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

    private static func drawAudio(width: Int, height: Int, pixels: inout [UInt8]) {
        // Waveform
        for y in 0..<height {
            for x in 0..<width {
                var r = 20, g = 20, b = 30
                
                let amp = sin(Double(x)/10.0) * sin(Double(x)/50.0) * (Double(height)/3.0)
                if abs(Double(y - height/2)) < abs(amp) {
                    r = 100; g = 200; b = 255
                }
                
                let index = (y * width + x) * 4
                pixels[index] = UInt8(r)
                pixels[index + 1] = UInt8(g)
                pixels[index + 2] = UInt8(b)
                pixels[index + 3] = 255
            }
        }
    }

    private static func drawCamera(width: Int, height: Int, pixels: inout [UInt8]) {
        // Aperture
        for y in 0..<height {
            for x in 0..<width {
                let dx = Double(x - width/2)
                let dy = Double(y - height/2)
                let dist = sqrt(dx*dx + dy*dy)
                
                var r = 50, g = 50, b = 50
                if dist < 100 {
                    let angle = atan2(dy, dx)
                    r = 20; g = 20; b = 20
                    if Int(angle * 6) % 2 == 0 {
                        r = 40; g = 40; b = 40
                    }
                    if dist < 40 { // Lens
                        r = 20; g = 0; b = 80
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

    private static func drawWeb(width: Int, height: Int, pixels: inout [UInt8]) {
        // Grid/Globe
        for y in 0..<height {
            for x in 0..<width {
                var r = 255, g = 255, b = 255
                
                // Latitude/Longitude grid
                if x % 30 == 0 || y % 30 == 0 {
                    r = 200; g = 200; b = 255
                }
                
                // "Browser" header
                if y < 40 {
                    r = 220; g = 220; b = 220
                    if x > 200 { // Close btn
                        r = 255; g = 100; b = 100
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
    
    private static func drawAI(width: Int, height: Int, pixels: inout [UInt8]) {
        // Circuit board green/black
        for y in 0..<height {
            for x in 0..<width {
                var r = 0, g = 20, b = 0
                
                // Lines
                if x % 30 == 0 || y % 30 == 0 {
                    r = 0; g = 150; b = 0
                }
                
                // Nodes
                if x % 60 == 0 && y % 60 == 0 {
                     r = 100; g = 255; b = 100
                }
                
                let index = (y * width + x) * 4
                pixels[index] = UInt8(r)
                pixels[index + 1] = UInt8(g)
                pixels[index + 2] = UInt8(b)
                pixels[index + 3] = 255
            }
        }
    }

    private static func drawFinance(width: Int, height: Int, pixels: inout [UInt8]) {
        // Green charts
        for y in 0..<height {
            for x in 0..<width {
                var r = 240, g = 255, b = 240
                
                // Chart line
                let chartY = Double(height) - (Double(x) / Double(width)) * (Double(height) * 0.8) - 20.0 + sin(Double(x)/10.0)*20.0
                if abs(Double(y) - chartY) < 2.0 {
                    r = 0; g = 180; b = 0
                } else if Double(y) > chartY {
                    r = 200; g = 250; b = 200
                }
                
                let index = (y * width + x) * 4
                pixels[index] = UInt8(r)
                pixels[index + 1] = UInt8(g)
                pixels[index + 2] = UInt8(b)
                pixels[index + 3] = 255
            }
        }
    }
    
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
