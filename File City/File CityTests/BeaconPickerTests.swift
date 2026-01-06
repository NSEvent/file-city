import XCTest
import simd
@testable import File_City

final class BeaconPickerTests: XCTestCase {
    func testPickBeaconHit() {
        let nodeID = UUID()
        let boxes = [
            BeaconPicker.Box(nodeID: nodeID, min: SIMD3<Float>(-1, -1, -1), max: SIMD3<Float>(1, 1, 1))
        ]
        let ray = RayTracer.Ray(origin: SIMD3<Float>(0, 0, 5), direction: SIMD3<Float>(0, 0, -1))
        let picked = BeaconPicker.pick(ray: ray, boxes: boxes)
        XCTAssertEqual(picked, nodeID)
    }

    func testPickBeaconMiss() {
        let boxes = [
            BeaconPicker.Box(nodeID: UUID(), min: SIMD3<Float>(2.5, -0.5, -0.5), max: SIMD3<Float>(3.5, 0.5, 0.5))
        ]
        let ray = RayTracer.Ray(origin: SIMD3<Float>(0, 0, 5), direction: SIMD3<Float>(0, 0, -1))
        let picked = BeaconPicker.pick(ray: ray, boxes: boxes)
        XCTAssertNil(picked)
    }

    func testPickBeaconClosest() {
        let nearID = UUID()
        let farID = UUID()
        let boxes = [
            BeaconPicker.Box(nodeID: farID, min: SIMD3<Float>(-1, -1, -11), max: SIMD3<Float>(1, 1, -9)),
            BeaconPicker.Box(nodeID: nearID, min: SIMD3<Float>(-1, -1, -1), max: SIMD3<Float>(1, 1, 1))
        ]
        let ray = RayTracer.Ray(origin: SIMD3<Float>(0, 0, 5), direction: SIMD3<Float>(0, 0, -1))
        let picked = BeaconPicker.pick(ray: ray, boxes: boxes)
        XCTAssertEqual(picked, nearID)
    }
}
