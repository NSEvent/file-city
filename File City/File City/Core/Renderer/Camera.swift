import Foundation
import simd

final class Camera {
    var target = SIMD3<Float>(0, 0, 0)
    var distance: Float = 60
    let pitch: Float = 0.75
    let yaw: Float = 0.7853982
    var aspect: Float = 1.0

    func zoom(delta: Float) {
        distance = max(0.02, distance - delta * 20)
    }

    func pan(deltaX: Float, deltaY: Float) {
        let right = SIMD3<Float>(cos(yaw), 0, -sin(yaw))
        let forward = SIMD3<Float>(sin(yaw), 0, cos(yaw))
        target += (right * deltaX + forward * deltaY) * 0.2
    }

    func viewMatrix() -> simd_float4x4 {
        let eye = SIMD3<Float>(
            target.x + distance * cos(pitch) * sin(yaw),
            target.y + distance * sin(pitch),
            target.z + distance * cos(pitch) * cos(yaw)
        )
        return lookAt(eye: eye, target: target, up: SIMD3<Float>(0, 1, 0))
    }

    func projectionMatrix() -> simd_float4x4 {
        perspective(fovY: 0.75, aspect: aspect, near: 0.01, far: 2000)
    }

    private func lookAt(eye: SIMD3<Float>, target: SIMD3<Float>, up: SIMD3<Float>) -> simd_float4x4 {
        let z = simd_normalize(eye - target)
        let x = simd_normalize(simd_cross(up, z))
        let y = simd_cross(z, x)
        let translation = SIMD3<Float>(-simd_dot(x, eye), -simd_dot(y, eye), -simd_dot(z, eye))
        return simd_float4x4(columns: (
            SIMD4<Float>(x.x, y.x, z.x, 0),
            SIMD4<Float>(x.y, y.y, z.y, 0),
            SIMD4<Float>(x.z, y.z, z.z, 0),
            SIMD4<Float>(translation.x, translation.y, translation.z, 1)
        ))
    }

    private func perspective(fovY: Float, aspect: Float, near: Float, far: Float) -> simd_float4x4 {
        let yScale = 1 / tan(fovY * 0.5)
        let xScale = yScale / max(aspect, 0.01)
        let zRange = far - near
        let zScale = -(far + near) / zRange
        let wzScale = -2 * far * near / zRange
        return simd_float4x4(columns: (
            SIMD4<Float>(xScale, 0, 0, 0),
            SIMD4<Float>(0, yScale, 0, 0),
            SIMD4<Float>(0, 0, zScale, -1),
            SIMD4<Float>(0, 0, wzScale, 0)
        ))
    }
}
