import Foundation
import simd

struct VoxelInstance {
    var position: SIMD3<Float>
    var _pad0: Float = 0
    var scale: SIMD3<Float>
    var _pad1: Float = 0
    var materialID: UInt32
    var highlight: Float = 0
    var hover: Float = 0
    var textureIndex: Int32 = -1
    var shapeID: Int32 = 0
}
