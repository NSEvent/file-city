import Foundation
import Metal
import CryptoKit
import AppKit

final class TextureGenerator {
    private enum FacadeStyle: UInt64 {
        case glassCurtain = 0
        case concreteGrid = 1
        case stoneCladding = 2
        case metalPanels = 3
        case nightWindows = 4
    }

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
        
        let lowerSeed = seed.lowercased()
        if lowerSeed.contains("plane-body") {
            drawPlaneBody(width: width, height: height, pixels: &pixelData, seed: seed)
        } else if lowerSeed.contains("road-asphalt") {
            drawRoadAsphalt(width: width, height: height, pixels: &pixelData)
        } else if lowerSeed.contains("car-paint") {
            drawCarPaint(width: width, height: height, pixels: &pixelData, seed: seed)
        } else if lowerSeed.contains("audio_file") || lowerSeed.contains("audio-file") {
            drawAudioFile(width: width, height: height, pixels: &pixelData)
        } else if lowerSeed.contains("video_file") || lowerSeed.contains("video-file") {
            drawVideoFile(width: width, height: height, pixels: &pixelData)
        } else if lowerSeed.contains("archive_file") || lowerSeed.contains("archive-file") {
            drawArchiveFile(width: width, height: height, pixels: &pixelData)
        } else if lowerSeed.contains("db_file") || lowerSeed.contains("db-file") {
            drawDatabaseFile(width: width, height: height, pixels: &pixelData)
        } else if lowerSeed.contains("image-file") {
            drawImageFile(width: width, height: height, pixels: &pixelData)
        } else if lowerSeed.contains("text-doc") {
            drawTextDoc(width: width, height: height, pixels: &pixelData)
        } else if lowerSeed.contains("code-json") {
            drawCode(width: width, height: height, pixels: &pixelData)
        } else if lowerSeed.contains("swift-file") {
            drawSwift(width: width, height: height, pixels: &pixelData)
        } else {
            var rng = DeterministicRNG(seed: seed)
        let styleRoll = rng.next() % 20
        let style: FacadeStyle
        switch styleRoll {
        case 0...9:
            style = .glassCurtain
        case 10...14:
            style = .metalPanels
        case 15...16:
            style = .nightWindows
        case 17...18:
            style = .concreteGrid
        default:
            style = .stoneCladding
        }
        switch style {
        case .glassCurtain:
            drawGlassCurtain(width: width, height: height, pixels: &pixelData, rng: &rng)
        case .concreteGrid:
            drawConcreteGrid(width: width, height: height, pixels: &pixelData, rng: &rng)
        case .stoneCladding:
            drawStoneCladding(width: width, height: height, pixels: &pixelData, rng: &rng)
        case .metalPanels:
            drawMetalPanels(width: width, height: height, pixels: &pixelData, rng: &rng)
        case .nightWindows:
            drawNightWindows(width: width, height: height, pixels: &pixelData, rng: &rng)
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
    
    // MARK: - Themes
    private static func drawGlassCurtain(width: Int, height: Int, pixels: inout [UInt8], rng: inout DeterministicRNG) {
        let tintR = Int(rng.next() % 30) + 110
        let tintG = Int(rng.next() % 40) + 150
        let tintB = Int(rng.next() % 40) + 190
        let mullion = Int(rng.next() % 2) + 2
        let gridW = Int(rng.next() % 24) + 32
        let gridH = Int(rng.next() % 48) + 64
        let seed = rng.next()
        let accent = vibrantAccent(seed: seed)

        for y in 0..<height {
            let ny = Double(y) / Double(height)
            for x in 0..<width {
                let index = (y * width + x) * 4
                if x % gridW < mullion || y % gridH < mullion {
                    setColor(index: index, r: accent.r, g: accent.g, b: accent.b, pixels: &pixels)
                    continue
                }

                let nx = Double(x) / Double(width)
                let wave = sin(nx * 6.2 + ny * 3.7) * 12.0
                let haze = Double(hash2D(x: x, y: y, seed: seed) % 9) - 4.0

                let r = clamp(value: tintR + Int(wave * 0.6 + haze), min: 0, max: 255)
                let g = clamp(value: tintG + Int(wave * 0.5 - ny * 20.0 + haze), min: 0, max: 255)
                let b = clamp(value: tintB + Int(wave * 0.7 - ny * 28.0), min: 0, max: 255)
                setColor(index: index, r: r, g: g, b: b, pixels: &pixels)
            }
        }
    }

    private static func drawConcreteGrid(width: Int, height: Int, pixels: inout [UInt8], rng: inout DeterministicRNG) {
        let cellW = Int(rng.next() % 24) + 36
        let cellH = Int(rng.next() % 24) + 36
        let frame = Int(rng.next() % 3) + 5
        let seed = rng.next()
        let accent = vibrantAccent(seed: seed)

        for y in 0..<height {
            for x in 0..<width {
                let index = (y * width + x) * 4
                let lx = x % cellW
                let ly = y % cellH

                if lx < frame || ly < frame {
                    let noise = Int(hash2D(x: x, y: y, seed: seed) % 25)
                    let base = 165 + noise
                    setColor(index: index, r: base + accent.r / 4, g: base + accent.g / 5, b: base + accent.b / 6, pixels: &pixels)
                } else {
                    if lx < frame + 2 || ly < frame + 2 {
                        setColor(index: index, r: 22, g: 24, b: 28, pixels: &pixels)
                    } else {
                        setColor(index: index, r: 70, g: 90, b: 110, pixels: &pixels)
                    }
                }
            }
        }
        overlayWindows(width: width, height: height, pixels: &pixels, seed: seed, density: 0.1)
    }

    private static func drawStoneCladding(width: Int, height: Int, pixels: inout [UInt8], rng: inout DeterministicRNG) {
        let blockW = Int(rng.next() % 32) + 48
        let blockH = Int(rng.next() % 20) + 24
        let seed = rng.next()
        let accent = vibrantAccent(seed: seed)

        for y in 0..<height {
            let row = y / blockH
            let offset = (row % 2 == 0) ? 0 : blockW / 2
            for x in 0..<width {
                let index = (y * width + x) * 4
                let ex = (x + offset) % width
                let lx = ex % blockW
                let ly = y % blockH

                if lx < 2 || ly < 2 {
                    setColor(index: index, r: 78, g: 74, b: 70, pixels: &pixels)
                    continue
                }

                let blockHash = hash2D(x: ex / blockW, y: row, seed: seed) % 30
                let noise = hash2D(x: x, y: y, seed: seed) % 40
                let base = 145 + Int(blockHash + noise / 2)
                setColor(
                    index: index,
                    r: clamp(value: base + 10 + accent.r / 6, min: 0, max: 255),
                    g: clamp(value: base + 4 + accent.g / 7, min: 0, max: 255),
                    b: clamp(value: base - 4 + accent.b / 8, min: 0, max: 255),
                    pixels: &pixels
                )
            }
        }
        overlayWindows(width: width, height: height, pixels: &pixels, seed: seed, density: 0.08)
    }

    private static func drawMetalPanels(width: Int, height: Int, pixels: inout [UInt8], rng: inout DeterministicRNG) {
        let panelW = Int(rng.next() % 40) + 48
        let panelH = Int(rng.next() % 80) + 96
        let seed = rng.next()
        let verticalBrush = (rng.next() % 2) == 0
        let accent = vibrantAccent(seed: seed)

        for y in 0..<height {
            for x in 0..<width {
                let index = (y * width + x) * 4
                if x % panelW < 2 || y % panelH < 2 {
                    setColor(index: index, r: accent.r, g: accent.g, b: accent.b, pixels: &pixels)
                    continue
                }

                let stripe = verticalBrush ? hash2D(x: x, y: 0, seed: seed) : hash2D(x: 0, y: y, seed: seed)
                let noise = hash2D(x: x, y: y, seed: seed) % 18
                let val = 180 + Int((stripe % 55) + noise)
                setColor(
                    index: index,
                    r: clamp(value: val + accent.r / 5, min: 0, max: 255),
                    g: clamp(value: val + accent.g / 7, min: 0, max: 255),
                    b: clamp(value: val + 16 + accent.b / 8, min: 0, max: 255),
                    pixels: &pixels
                )
            }
        }
        overlayWindows(width: width, height: height, pixels: &pixels, seed: seed, density: 0.1)
    }

    private static func drawNightWindows(width: Int, height: Int, pixels: inout [UInt8], rng: inout DeterministicRNG) {
        let winW = Int(rng.next() % 8) + 14
        let winH = Int(rng.next() % 12) + 20
        let gap = Int(rng.next() % 6) + 6
        let seed = rng.next()
        let roofBand = Int(Double(height) * 0.18)
        let accent = vibrantAccent(seed: seed)

        for y in 0..<height {
            for x in 0..<width {
                let index = (y * width + x) * 4
                if y < roofBand {
                    setColor(index: index, r: accent.r / 2, g: accent.g / 3, b: accent.b / 3, pixels: &pixels)
                    continue
                }
                let cellX = x / (winW + gap)
                let cellY = y / (winH + gap)
                let lx = x % (winW + gap)
                let ly = y % (winH + gap)

                if lx >= winW || ly >= winH {
                    setColor(index: index, r: 9, g: 10, b: 14, pixels: &pixels)
                    continue
                }

                let winHash = hash2D(x: cellX, y: cellY, seed: seed)
                let lit = (winHash % 100) < 45
                if lit {
                    if winHash % 2 == 0 {
                        setColor(index: index, r: 255, g: 230, b: 170, pixels: &pixels)
                    } else {
                        setColor(index: index, r: 170, g: 205, b: 255, pixels: &pixels)
                    }
                } else {
                    setColor(index: index, r: 10, g: 12, b: 16, pixels: &pixels)
                }
            }
        }
    }

    private static func overlayWindows(width: Int, height: Int, pixels: inout [UInt8], seed: UInt64, density: Double) {
        let winW = 12
        let winH = 18
        let gapX = 16
        let gapY = 18
        let strideX = winW + gapX
        let strideY = winH + gapY

        for y in 0..<height {
            for x in 0..<width {
                let lx = x % strideX
                let ly = y % strideY
                if lx >= winW || ly >= winH {
                    continue
                }

                let cellX = x / strideX
                let cellY = y / strideY
                let winHash = hash2D(x: cellX, y: cellY, seed: seed)
                let lit = Double(winHash % 100) < density * 100.0

                let index = (y * width + x) * 4
                if lit {
                    if winHash % 2 == 0 {
                        setColor(index: index, r: 255, g: 220, b: 165, pixels: &pixels)
                    } else {
                        setColor(index: index, r: 170, g: 200, b: 255, pixels: &pixels)
                    }
                } else {
                    setColor(index: index, r: 20, g: 24, b: 30, pixels: &pixels)
                }
            }
        }
    }
    
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

    private static func drawRoadAsphalt(width: Int, height: Int, pixels: inout [UInt8]) {
        let seed: UInt64 = 0xA5A5_5A5A
        let centerX = width / 2
        let leftEdge = width / 6
        let rightEdge = width - leftEdge

        for y in 0..<height {
            for x in 0..<width {
                let index = (y * width + x) * 4
                let noise = Int(hash2D(x: x, y: y, seed: seed) % 18)
                let base = 30 + noise
                var r = base
                var g = base + 2
                var b = base + 4

                let dash = (y % 28) < 14
                if abs(x - centerX) < 2 && dash {
                    r = 220; g = 200; b = 90
                } else if abs(x - leftEdge) < 2 || abs(x - rightEdge) < 2 {
                    r = 200; g = 200; b = 200
                }

                setColor(index: index, r: r, g: g, b: b, pixels: &pixels)
            }
        }
    }

    private static func drawCarPaint(width: Int, height: Int, pixels: inout [UInt8], seed: String) {
        var rng = DeterministicRNG(seed: seed)
        let accent = vibrantAccent(seed: rng.next())
        let baseR = clamp(value: accent.r + 40, min: 0, max: 255)
        let baseG = clamp(value: accent.g + 20, min: 0, max: 255)
        let baseB = clamp(value: accent.b + 20, min: 0, max: 255)

        let windshieldTop = height / 4
        let windshieldBottom = height / 2
        let windshieldLeft = width / 4
        let windshieldRight = width - windshieldLeft

        for y in 0..<height {
            for x in 0..<width {
                let index = (y * width + x) * 4
                var r = baseR
                var g = baseG
                var b = baseB

                if y > windshieldTop && y < windshieldBottom && x > windshieldLeft && x < windshieldRight {
                    r = 40; g = 60; b = 80
                } else if x < 6 || x > width - 6 || y < 6 || y > height - 6 {
                    r = clamp(value: baseR - 30, min: 0, max: 255)
                    g = clamp(value: baseG - 30, min: 0, max: 255)
                    b = clamp(value: baseB - 30, min: 0, max: 255)
                }

                setColor(index: index, r: r, g: g, b: b, pixels: &pixels)
            }
        }
    }

    private static func drawPlaneBody(width: Int, height: Int, pixels: inout [UInt8], seed: String) {
        var rng = DeterministicRNG(seed: seed)
        let accent = vibrantAccent(seed: rng.next())
        let stripe = (accent.r + accent.g + accent.b) % 2 == 0
        let nose = width / 6
        let tail = width - nose
        let wingBand = height / 2
        let wingThickness = 4
        let wingSpan = width / 3

        for y in 0..<height {
            for x in 0..<width {
                let index = (y * width + x) * 4
                var r = 220
                var g = 225
                var b = 230

                if stripe && y > height / 3 && y < height / 3 + 4 {
                    r = accent.r; g = accent.g; b = accent.b
                }

                if x < nose {
                    r = 200; g = 210; b = 225
                } else if x > tail {
                    r = 180; g = 190; b = 205
                }

                let windowBand = y > height / 2 && y < height / 2 + 3
                if windowBand && x > nose && x < tail && x % 8 < 4 {
                    r = 40; g = 60; b = 80
                }

                if y >= wingBand - wingThickness && y <= wingBand + wingThickness {
                    if x > nose / 2 && x < nose / 2 + wingSpan {
                        r = accent.r; g = accent.g; b = accent.b
                    }
                    if x > tail - wingSpan && x < tail + wingSpan / 2 {
                        r = accent.r; g = accent.g; b = accent.b
                    }
                }

                setColor(index: index, r: r, g: g, b: b, pixels: &pixels)
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

    private static func setColor(index: Int, r: Int, g: Int, b: Int, pixels: inout [UInt8]) {
        pixels[index] = UInt8(clamp(value: r, min: 0, max: 255))
        pixels[index + 1] = UInt8(clamp(value: g, min: 0, max: 255))
        pixels[index + 2] = UInt8(clamp(value: b, min: 0, max: 255))
        pixels[index + 3] = 255
    }

    private static func vibrantAccent(seed: UInt64) -> (r: Int, g: Int, b: Int) {
        switch seed % 5 {
        case 0:
            return (r: 70, g: 235, b: 255) // teal
        case 1:
            return (r: 255, g: 200, b: 70) // amber
        case 2:
            return (r: 255, g: 110, b: 190) // pink
        case 3:
            return (r: 160, g: 230, b: 110) // lime
        default:
            return (r: 120, g: 140, b: 255) // periwinkle
        }
    }

    private static func hash2D(x: Int, y: Int, seed: UInt64) -> UInt64 {
        var h = UInt64(bitPattern: Int64(x)) &* 374761393
        h = (h ^ (h >> 13)) &* 1274126177
        h &+= UInt64(bitPattern: Int64(y)) &* 668265263
        h ^= seed
        return h ^ (h >> 16)
    }

    private static func clamp(value: Int, min: Int, max: Int) -> Int {
        return value < min ? min : (value > max ? max : value)
    }

    // MARK: - Font Atlas
    /// Generates a font atlas texture with ASCII characters 32-127
    /// Layout: 16 columns x 16 rows, each cell 16x16 pixels = 256x256 texture
    /// Only first 96 cells (6 rows) contain characters, rest is empty
    static func generateFontAtlas(device: MTLDevice) -> MTLTexture? {
        let cellSize = 16
        let cols = 16
        let rows = 16  // Match 256x256 texture size
        let width = cellSize * cols   // 256
        let height = cellSize * rows  // 256

        // Create NSImage and draw text
        let image = NSImage(size: NSSize(width: width, height: height))
        image.lockFocus()

        // Fill with dark background for visibility
        NSColor(red: 0.15, green: 0.15, blue: 0.2, alpha: 1.0).setFill()
        NSRect(x: 0, y: 0, width: width, height: height).fill()

        let font = NSFont.monospacedSystemFont(ofSize: 11, weight: .bold)
        let attributes: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: NSColor.white
        ]

        // Draw ASCII characters 32-127 (96 characters)
        for i in 0..<96 {
            let char = Character(UnicodeScalar(32 + i)!)
            let col = i % cols
            let row = i / cols
            // Position in texture (row 0 at top)
            let x = CGFloat(col * cellSize) + 3
            let y = CGFloat(height - (row + 1) * cellSize) + 2
            String(char).draw(at: NSPoint(x: x, y: y), withAttributes: attributes)
        }

        image.unlockFocus()

        // Convert to pixel data
        guard let cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else { return nil }

        var pixelData = [UInt8](repeating: 0, count: width * height * 4)
        let context = CGContext(
            data: &pixelData,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: width * 4,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        )
        context?.draw(cgImage, in: CGRect(x: 0, y: 0, width: width, height: height))

        let descriptor = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: .rgba8Unorm,
            width: width,
            height: height,
            mipmapped: false
        )
        descriptor.usage = .shaderRead

        guard let texture = device.makeTexture(descriptor: descriptor) else { return nil }
        texture.replace(
            region: MTLRegionMake2D(0, 0, width, height),
            mipmapLevel: 0,
            withBytes: pixelData,
            bytesPerRow: width * 4
        )

        return texture
    }

    // MARK: - Sign Labels
    /// Generates a pre-baked texture for a sign label (128x32 pixels)
    static func generateSignLabel(device: MTLDevice, text: String) -> MTLTexture? {
        let width = 128
        let height = 32

        let image = NSImage(size: NSSize(width: width, height: height))
        image.lockFocus()

        // Dark background
        NSColor(red: 0.2, green: 0.18, blue: 0.15, alpha: 1.0).setFill()
        NSRect(x: 0, y: 0, width: width, height: height).fill()

        // Draw text centered
        let displayText = String(text.prefix(10))
        let font = NSFont.systemFont(ofSize: 14, weight: .bold)
        let attributes: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: NSColor.white
        ]

        let textSize = displayText.size(withAttributes: attributes)
        let x = (CGFloat(width) - textSize.width) / 2
        let y = (CGFloat(height) - textSize.height) / 2
        displayText.draw(at: NSPoint(x: x, y: y), withAttributes: attributes)

        image.unlockFocus()

        guard let cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else { return nil }

        var pixelData = [UInt8](repeating: 0, count: width * height * 4)
        let context = CGContext(
            data: &pixelData,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: width * 4,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        )
        context?.draw(cgImage, in: CGRect(x: 0, y: 0, width: width, height: height))

        let descriptor = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: .rgba8Unorm,
            width: width,
            height: height,
            mipmapped: false
        )
        descriptor.usage = .shaderRead

        guard let texture = device.makeTexture(descriptor: descriptor) else { return nil }
        texture.replace(
            region: MTLRegionMake2D(0, 0, width, height),
            mipmapLevel: 0,
            withBytes: pixelData,
            bytesPerRow: width * 4
        )

        return texture
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
