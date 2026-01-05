import Foundation
import simd

final class CityMapper {
    func map(root: FileNode, rules: LayoutRules, pinStore: PinStore) -> [CityBlock] {
        let nodes = root.children
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
            let block = CityBlock(
                id: UUID(),
                nodeID: node.id,
                position: SIMD3<Float>(x, 0, z),
                footprint: footprint,
                height: Int32(height),
                materialID: Int32(materialID),
                textureIndex: textureIndexFor(node: node),
                isPinned: pinned
            )
            blocks.append(block)
        }

        return blocks
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
        var hasher = Hasher()
        hasher.combine(node.name)
        let hash = abs(hasher.finalize())
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
        let size = node.type == .file ? rules.maxBlockSize : rules.minBlockSize
        return SIMD2<Int32>(Int32(size), Int32(size))
    }

    private func materialFor(node: FileNode) -> Int {
        var hasher = Hasher()
        switch node.type {
        case .folder:
            hasher.combine(node.name.lowercased())
            return abs(hasher.finalize() % 4)
        case .symlink:
            hasher.combine(node.name.lowercased())
            return 11
        case .file:
            hasher.combine(node.url.pathExtension.lowercased())
            let index = abs(hasher.finalize() % 8)
            return 4 + index
        }
    }
}
