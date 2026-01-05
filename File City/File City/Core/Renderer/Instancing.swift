import Foundation
import simd

struct VoxelInstance {
    var position: SIMD3<Float>
    var scale: SIMD3<Float>
    var materialID: UInt32
}
