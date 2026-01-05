import Foundation
import simd

struct VoxelInstance {
    var position: SIMD3<Float>
    var _pad0: Float = 0
    var scale: SIMD3<Float>
    var _pad1: Float = 0
    var materialID: UInt32
    var _pad2: SIMD3<UInt32> = .init(0, 0, 0)
}
