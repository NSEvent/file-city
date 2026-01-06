import Foundation
import simd

struct CityBlock: Identifiable, Hashable {
    let id: UUID
    let nodeID: UUID
    let position: SIMD3<Float>
    let footprint: SIMD2<Int32>
    let height: Int32
    let materialID: Int32
    let textureIndex: Int32
    let shapeID: Int32
    let isPinned: Bool
}
