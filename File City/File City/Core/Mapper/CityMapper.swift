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
            let height = heightFor(node: node, maxHeight: rules.maxBuildingHeight)
            let materialID = materialFor(node: node)
            let pinned = pinStore.isPinned(pathHash: PinStore.pathHash(node.url))
            let block = CityBlock(
                id: UUID(),
                nodeID: node.id,
                position: SIMD3<Float>(x, 0, z),
                footprint: SIMD2<Int32>(Int32(rules.minBlockSize), Int32(rules.minBlockSize)),
                height: Int32(height),
                materialID: Int32(materialID),
                isPinned: pinned
            )
            blocks.append(block)
        }

        return blocks
    }

    private func heightFor(node: FileNode, maxHeight: Int) -> Int {
        let base = max(1.0, log10(Double(max(node.sizeBytes, 1))))
        return min(maxHeight, Int(base * 8.0))
    }

    private func materialFor(node: FileNode) -> Int {
        var hasher = Hasher()
        hasher.combine(node.url.pathExtension.lowercased())
        return abs(hasher.finalize() % 12)
    }
}
