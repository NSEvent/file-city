import Foundation
import CryptoKit
import simd

final class CityMapper {
    private enum BuildingStyle {
        case standard
        case taper
        case pyramid
        case slantX
        case slantZ
        case cylinder
        case bulbous
    }

    func map(root: FileNode, rules: LayoutRules, pinStore: PinStore) -> [CityBlock] {
        let nodes = root.children.sorted { lhs, rhs in
            let lhsType = nodeTypeRank(lhs)
            let rhsType = nodeTypeRank(rhs)
            if lhsType != rhsType { return lhsType < rhsType }

            let lhsDepth = pathDepth(lhs.url.path)
            let rhsDepth = pathDepth(rhs.url.path)
            if lhsDepth != rhsDepth { return lhsDepth < rhsDepth }

            if lhs.sizeBytes != rhs.sizeBytes { return lhs.sizeBytes > rhs.sizeBytes }
            return lhs.url.path < rhs.url.path
        }
        let gridSize = Int(ceil(sqrt(Double(nodes.count))))
        let spacing = Float(rules.maxBlockSize + rules.roadWidth)
        var blocks: [CityBlock] = []
        blocks.reserveCapacity(nodes.count)

        for (index, node) in nodes.enumerated() {
            let row = index / max(gridSize, 1)
            let col = index % max(gridSize, 1)
            let x = Float(col) * spacing
            let z = Float(row) * spacing
            let height = heightFor(node: node, maxHeight: rules.maxBuildingHeight, minHeight: max(4, rules.minBlockSize))
            let footprint = footprintFor(node: node, rules: rules)
            let materialID = materialFor(node: node)
            let pinned = pinStore.isPinned(pathHash: PinStore.pathHash(node.url))
            let seed = buildingSeed(node: node)
            let basePosition = SIMD3<Float>(x, 0, z)
            let textureIndex = textureIndexFor(node: node)
            let style = buildingStyleFor(node: node, height: height, footprint: footprint, seed: seed)

            if shouldStackSkyscraper(node: node, height: height, footprint: footprint, seed: seed) {
                let towerBlocks = buildSkyscraperBlocks(
                    position: basePosition,
                    nodeID: node.id,
                    height: Int32(height),
                    footprint: footprint,
                    materialID: Int32(materialID),
                    textureIndex: textureIndex,
                    pinned: pinned,
                    seed: seed
                )
                blocks.append(contentsOf: towerBlocks)
            } else if style == .bulbous {
                let bulbousBlocks = buildBulbousBlocks(
                    position: basePosition,
                    nodeID: node.id,
                    height: Int32(height),
                    footprint: footprint,
                    materialID: Int32(materialID),
                    textureIndex: textureIndex,
                    pinned: pinned
                )
                blocks.append(contentsOf: bulbousBlocks)
            } else {
                let block = CityBlock(
                    id: UUID(),
                    nodeID: node.id,
                    position: basePosition,
                    footprint: footprint,
                    height: Int32(height),
                    materialID: Int32(materialID),
                    textureIndex: textureIndex,
                    shapeID: shapeIDFor(style: style),
                    isPinned: pinned
                )
                blocks.append(block)
            }
        }

        return blocks
    }

    private func shouldStackSkyscraper(node: FileNode, height: Int, footprint: SIMD2<Int32>, seed: UInt32) -> Bool {
        guard node.type == .folder else { return false }
        let maxFootprint = max(footprint.x, footprint.y)
        return height >= 14 && maxFootprint >= 6 && seed % 3 == 0
    }

    private func buildingStyleFor(node: FileNode, height: Int, footprint: SIMD2<Int32>, seed: UInt32) -> BuildingStyle {
        guard node.type == .folder, height > 5, footprint.x < 10 else { return .standard }
        switch seed % 12 {
        case 0...5:
            return .standard
        case 6:
            return .slantX
        case 7:
            return .slantZ
        case 8:
            return .pyramid
        case 9:
            return .taper
        case 10:
            return .cylinder
        default:
            return .bulbous
        }
    }

    private func buildSkyscraperBlocks(
        position: SIMD3<Float>,
        nodeID: UUID,
        height: Int32,
        footprint: SIMD2<Int32>,
        materialID: Int32,
        textureIndex: Int32,
        pinned: Bool,
        seed: UInt32
    ) -> [CityBlock] {
        let tierCount = tierCountFor(height: height, seed: seed)

        let baseHeight: Int32
        let midHeight: Int32
        let upperHeight: Int32
        let crownHeight: Int32

        if tierCount == 4 {
            baseHeight = max(8, Int32(Float(height) * 0.45))
            midHeight = max(6, Int32(Float(height) * 0.25))
            upperHeight = max(5, Int32(Float(height) * 0.18))
            crownHeight = max(3, height - baseHeight - midHeight - upperHeight)
        } else if tierCount == 3 {
            baseHeight = max(7, Int32(Float(height) * 0.55))
            midHeight = max(5, Int32(Float(height) * 0.25))
            upperHeight = 0
            crownHeight = max(3, height - baseHeight - midHeight)
        } else {
            baseHeight = max(6, Int32(Float(height) * 0.7))
            midHeight = 0
            upperHeight = 0
            crownHeight = max(3, height - baseHeight)
        }

        var heights: [Int32]
        switch tierCount {
        case 4:
            heights = [baseHeight, midHeight, upperHeight, crownHeight]
        case 3:
            heights = [baseHeight, midHeight, crownHeight]
        default:
            heights = [baseHeight, crownHeight]
        }
        normalizeHeights(total: height, heights: &heights, minHeight: 3)

        let baseFootprint = footprint
        let midFootprint = shrinkFootprint(baseFootprint, by: 2, min: 4)
        let upperFootprint = shrinkFootprint(midFootprint, by: 2, min: 3)
        let crownFootprint = shrinkFootprint(upperFootprint, by: 2, min: 2)

        var blocks: [CityBlock] = []
        blocks.reserveCapacity(heights.count)

        var currentY: Float = position.y
        for (index, segmentHeight) in heights.enumerated() {
            let segmentFootprint: SIMD2<Int32>
            let shapeID: Int32

            switch tierCount {
            case 4:
                switch index {
                case 0:
                    segmentFootprint = baseFootprint
                    shapeID = 0
                case 1:
                    segmentFootprint = midFootprint
                    shapeID = 0
                case 2:
                    segmentFootprint = upperFootprint
                    shapeID = 0
                default:
                    segmentFootprint = crownFootprint
                    shapeID = crownShape(seed: seed)
                }
            case 3:
                switch index {
                case 0:
                    segmentFootprint = baseFootprint
                    shapeID = 0
                case 1:
                    segmentFootprint = midFootprint
                    shapeID = 0
                default:
                    segmentFootprint = crownFootprint
                    shapeID = crownShape(seed: seed)
                }
            default:
                if index == 0 {
                    segmentFootprint = baseFootprint
                    shapeID = 0
                } else {
                    segmentFootprint = shrinkFootprint(baseFootprint, by: 2, min: 3)
                    shapeID = crownShape(seed: seed)
                }
            }

            let block = CityBlock(
                id: UUID(),
                nodeID: nodeID,
                position: SIMD3<Float>(position.x, currentY, position.z),
                footprint: segmentFootprint,
                height: segmentHeight,
                materialID: materialID,
                textureIndex: textureIndex,
                shapeID: shapeID,
                isPinned: pinned
            )
            blocks.append(block)
            currentY += Float(segmentHeight)
        }

        return blocks
    }

    private func buildBulbousBlocks(
        position: SIMD3<Float>,
        nodeID: UUID,
        height: Int32,
        footprint: SIMD2<Int32>,
        materialID: Int32,
        textureIndex: Int32,
        pinned: Bool
    ) -> [CityBlock] {
        var heights: [Int32] = [
            max(4, Int32(Float(height) * 0.3)),
            max(4, Int32(Float(height) * 0.4)),
            max(4, height - Int32(Float(height) * 0.7))
        ]
        normalizeHeights(total: height, heights: &heights, minHeight: 3)

        let midFootprint = footprint
        let baseFootprint = shrinkFootprint(midFootprint, by: 2, min: 4)
        let topFootprint = shrinkFootprint(midFootprint, by: 2, min: 4)
        let segmentFootprints = [baseFootprint, midFootprint, topFootprint]

        var blocks: [CityBlock] = []
        blocks.reserveCapacity(3)

        var currentY: Float = position.y
        for (index, segmentHeight) in heights.enumerated() {
            let block = CityBlock(
                id: UUID(),
                nodeID: nodeID,
                position: SIMD3<Float>(position.x, currentY, position.z),
                footprint: segmentFootprints[index],
                height: segmentHeight,
                materialID: materialID,
                textureIndex: textureIndex,
                shapeID: 5,
                isPinned: pinned
            )
            blocks.append(block)
            currentY += Float(segmentHeight)
        }

        return blocks
    }

    private func tierCountFor(height: Int32, seed: UInt32) -> Int {
        if height >= 40 {
            return seed % 2 == 0 ? 4 : 3
        }
        if height >= 24 {
            return seed % 2 == 0 ? 3 : 2
        }
        return 2
    }

    private func crownShape(seed: UInt32) -> Int32 {
        if seed % 5 == 0 {
            return 0
        }
        let pick = seed % 4
        switch pick {
        case 0:
            return 1 // Taper
        case 1:
            return 2 // Pyramid
        case 2:
            return 3 // Slant X
        default:
            return 4 // Slant Z
        }
    }

    private func normalizeHeights(total: Int32, heights: inout [Int32], minHeight: Int32) {
        for index in heights.indices {
            if heights[index] < minHeight {
                heights[index] = minHeight
            }
        }

        let sum = heights.reduce(0, +)
        if sum < total {
            heights[0] += total - sum
            return
        }

        var excess = sum - total
        for index in heights.indices {
            let available = heights[index] - minHeight
            if available <= 0 { continue }
            let delta = min(available, excess)
            heights[index] -= delta
            excess -= delta
            if excess == 0 { break }
        }
    }

    private func shrinkFootprint(_ footprint: SIMD2<Int32>, by amount: Int32, min: Int32) -> SIMD2<Int32> {
        let x = max(min, footprint.x - amount)
        let z = max(min, footprint.y - amount)
        return SIMD2<Int32>(x, z)
    }

    private func buildingSeed(node: FileNode) -> UInt32 {
        return UInt32(truncatingIfNeeded: deterministicHash(node.url.path))
    }

    private func shapeIDFor(style: BuildingStyle) -> Int32 {
        switch style {
        case .standard:
            return 0
        case .taper:
            return 1
        case .pyramid:
            return 2
        case .slantX:
            return 3
        case .slantZ:
            return 4
        case .cylinder:
            return 5
        case .bulbous:
            return 0
        }
    }

    private func textureIndexFor(node: FileNode) -> Int32 {
        let lowerName = node.name.lowercased()
        
        if node.type == .file {
             let ext = node.url.pathExtension.lowercased()
             if ext == "swift" { return 14 }
             if ["json", "js", "ts", "py", "c", "cpp", "h", "hpp", "sh", "yml", "xml", "plist"].contains(ext) { return 15 }
             if ["txt", "md", "rtf", "doc", "docx", "pdf"].contains(ext) { return 16 }
             if ["png", "jpg", "jpeg", "bmp", "tga", "gif", "svg"].contains(ext) { return 17 }
             if ["mp3", "wav", "aac", "ogg", "flac", "m4a"].contains(ext) { return 18 }
             if ["mp4", "mov", "avi", "mkv", "webm"].contains(ext) { return 19 }
             if ["zip", "tar", "gz", "rar", "7z", "iso"].contains(ext) { return 20 }
             if ["sql", "db", "sqlite", "sqlite3", "db3"].contains(ext) { return 21 }
             // Default file texture? Maybe random or untextured. 
             // Let's use 16 (text) as fallback for now or leave untextured (-1)
             return -1
        }
        
        // Manual mapping to match MetalRenderer's palette order
        if lowerName.contains("file city") { return 0 }
        if lowerName.contains("appshell") { return 1 }
        if lowerName.contains("core") { return 2 }
        if lowerName.contains("tiktok") { return 3 }
        if lowerName.contains("imsg") || lowerName.contains("msg") { return 4 }
        if lowerName.contains("pokemon") { return 5 }
        if lowerName.contains("python") { return 6 }
        if lowerName.contains("rust") { return 7 }
        if lowerName.contains("ai") || lowerName.contains("bot") || lowerName.contains("gpt") { return 8 }
        if lowerName.contains("bank") || lowerName.contains("finance") || lowerName.contains("card") || lowerName.contains("money") { return 9 }
        if lowerName.contains("real") || lowerName.contains("estate") || lowerName.contains("house") || lowerName.contains("rent") || lowerName.contains("landlord") || lowerName.contains("zillow") { return 10 }
        if lowerName.contains("audio") || lowerName.contains("voice") || lowerName.contains("sound") || lowerName.contains("speech") || lowerName.contains("say") || lowerName.contains("dtmf") || lowerName.contains("mouth") { return 11 }
        if lowerName.contains("camera") || lowerName.contains("photo") || lowerName.contains("image") || lowerName.contains("video") || lowerName.contains("face") || lowerName.contains("glitch") { return 12 }
        if lowerName.contains("web") || lowerName.contains("chrome") || lowerName.contains("browser") || lowerName.contains("link") || lowerName.contains("site") || lowerName.contains("scrape") { return 13 }
        
        // Hash the name to pick a consistent texture from the remaining palette
        // We reserved 0-21 for semantics, use 22-31 for random styles
        let hash = abs(deterministicHash(node.name))
        return Int32(22 + (hash % 10))
    }

    private func heightFor(node: FileNode, maxHeight: Int, minHeight: Int) -> Int {
        if node.type != .folder {
            return minHeight
        }
        let base = max(1.0, log10(Double(max(node.sizeBytes, 1))))
        return min(maxHeight, Int(base * 8.0))
    }

    private func footprintFor(node: FileNode, rules: LayoutRules) -> SIMD2<Int32> {
        let size = node.type == .folder ? (rules.maxBlockSize / 2) : rules.maxBlockSize
        return SIMD2<Int32>(Int32(size), Int32(size))
    }

    private func materialFor(node: FileNode) -> Int {
        switch node.type {
        case .folder:
            return Int(abs(deterministicHash(node.url.path.lowercased())) % 4)
        case .symlink:
            return 11
        case .file:
            let index = Int(abs(deterministicHash(node.url.pathExtension.lowercased())) % 8)
            return 4 + index
        }
    }

    private func nodeTypeRank(_ node: FileNode) -> Int {
        switch node.type {
        case .folder:
            return 0
        case .file:
            return 1
        case .symlink:
            return 2
        }
    }

    private func pathDepth(_ path: String) -> Int {
        return path.split(separator: "/").count
    }

    private func deterministicHash(_ value: String) -> Int64 {
        let data = value.data(using: .utf8) ?? Data()
        let digest = SHA256.hash(data: data)
        return digest.withUnsafeBytes { ptr in
            ptr.load(as: Int64.self)
        }
    }
}
