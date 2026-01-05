import Foundation
import simd

final class Camera {
    var position = SIMD3<Float>(0, 0, 0)
    var target = SIMD3<Float>(0, 0, 0)
    var zoom: Float = 1.0
    var pitch: Float = 0.6
    var yaw: Float = 0.8
}
