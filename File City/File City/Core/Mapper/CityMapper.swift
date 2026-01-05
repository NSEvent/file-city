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
        // Only texturize folders (buildings)
        guard node.type == .folder else { return -1 }
        
        // Hash the name to pick a consistent texture from the palette of 16
        var hasher = Hasher()
        hasher.combine(node.name)
        let hash = abs(hasher.finalize())
        return Int32(hash % 16)
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
