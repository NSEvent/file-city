import Foundation
import simd

struct Material {
    let id: Int32
    let baseColor: SIMD4<Float>
    let emissive: SIMD3<Float>
}
