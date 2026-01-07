import Foundation
import simd

struct CityBlock: Identifiable, Hashable {
    let id: UUID
    let nodeID: UUID
    let name: String
    let position: SIMD3<Float>
    let footprint: SIMD2<Int32>
    let height: Int32
    let materialID: Int32
    let textureIndex: Int32
    let shapeID: Int32
    let isPinned: Bool
    let isGitRepo: Bool
    let isGitClean: Bool
}

extension CityBlock {
    func withGitClean(_ isGitClean: Bool) -> CityBlock {
        CityBlock(
            id: id,
            nodeID: nodeID,
            name: name,
            position: position,
            footprint: footprint,
            height: height,
            materialID: materialID,
            textureIndex: textureIndex,
            shapeID: shapeID,
            isPinned: isPinned,
            isGitRepo: isGitRepo,
            isGitClean: isGitClean
        )
    }
}
