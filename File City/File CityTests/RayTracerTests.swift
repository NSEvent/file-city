import XCTest
import simd
@testable import File_City

final class RayTracerTests: XCTestCase {
    
    var tracer: RayTracer!
    
    override func setUp() {
        super.setUp()
        tracer = RayTracer()
    }
    
    // Helper to create a block
    func createBlock(position: SIMD3<Float>, width: Int32, height: Int32, shapeID: Int32 = 0) -> CityBlock {
        return CityBlock(
            id: UUID(),
            nodeID: UUID(),
            position: position,
            footprint: SIMD2<Int32>(width, width), // Square footprint for simplicity
            height: height,
            materialID: 0,
            textureIndex: 0,
            shapeID: shapeID,
            isPinned: false
        )
    }
    
    func testIntersectStandardBlock() {
        // Block at (0,0,0) width 10, height 10.
        // Bounds: x: -5..5, y: 0..10, z: -5..5
        let block = createBlock(position: SIMD3<Float>(0, 0, 0), width: 10, height: 10, shapeID: 0)
        
        // Ray from (0, 5, 20) pointing towards (0, 0, -1) -> (0, 5, 0)
        let rayOrigin = SIMD3<Float>(0, 5, 20)
        let rayDir = SIMD3<Float>(0, 0, -1)
        let ray = RayTracer.Ray(origin: rayOrigin, direction: rayDir)
        
        let hit = tracer.intersect(ray: ray, blocks: [block])
        
        XCTAssertNotNil(hit, "Should hit the standard block")
        // Hit distance should be dist from 20 to 5 = 15
        XCTAssertEqual(hit!.distance, 15.0, accuracy: 0.001)
        XCTAssertEqual(hit?.blockID, block.nodeID)
    }
    
    func testMissStandardBlock() {
        let block = createBlock(position: SIMD3<Float>(0, 0, 0), width: 10, height: 10, shapeID: 0)
        
        // Ray aimed too high (y=15)
        let ray = RayTracer.Ray(origin: SIMD3<Float>(0, 15, 20), direction: SIMD3<Float>(0, 0, -1))
        
        let hit = tracer.intersect(ray: ray, blocks: [block])
        XCTAssertNil(hit, "Should miss above the block")
    }

    func testIntersectRaisedBlock() {
        // Block base at y=10, height 10 -> top at y=20.
        let block = createBlock(position: SIMD3<Float>(0, 10, 0), width: 10, height: 10, shapeID: 0)

        let ray = RayTracer.Ray(origin: SIMD3<Float>(0, 15, 20), direction: SIMD3<Float>(0, 0, -1))
        let hit = tracer.intersect(ray: ray, blocks: [block])

        XCTAssertNotNil(hit, "Should hit a raised block")
    }
    
    func testIntersectPyramidTip() {
        // Pyramid block: Height 10.
        // Vertex shader logic: Top becomes 1.5x height = 15.
        // Tip is at (0, 15, 0).
        let block = createBlock(position: SIMD3<Float>(0, 0, 0), width: 10, height: 10, shapeID: 2) // 2 = Pyramid
        
        // Ray aiming at y=14 (near tip)
        // At y=14, the pyramid should be very narrow but hittable at x=0, z=0
        let ray = RayTracer.Ray(origin: SIMD3<Float>(0, 14, 20), direction: SIMD3<Float>(0, 0, -1))
        
        let hit = tracer.intersect(ray: ray, blocks: [block])
        XCTAssertNotNil(hit, "Should hit the pyramid tip")
    }
    
    func testMissPyramidEmptySpace() {
        // Pyramid block: Height 10.
        // AABB would be height 15 (1.5x) or 17.5 (1.75x) depending on logic.
        // Width at base is 10 (-5..5).
        // At y=10 (original top), the pyramid is narrower than the base.
        // Base (-5..5). Tip (0). Height 1.5h = 15. Waist 0.5h = 5.
        // From y=5 to y=15, it tapers from width 10 to 0.
        // At y=10, it is halfway between waist and tip? No.
        // Waist is at y=5 (0.5h). Tip is at y=15.
        // y=10 is midpoint of upper section. Width should be ~50% of waist width (which is full width 10).
        // So width at y=10 is approx 5 (-2.5..2.5).
        
        let block = createBlock(position: SIMD3<Float>(0, 0, 0), width: 10, height: 10, shapeID: 2)
        
        // Ray aiming at y=10, x=4. This is inside the AABB (x range -5..5) but outside the pyramid (width ~5 range -2.5..2.5)
        let ray = RayTracer.Ray(origin: SIMD3<Float>(4, 10, 20), direction: SIMD3<Float>(0, 0, -1))
        
        let hit = tracer.intersect(ray: ray, blocks: [block])
        XCTAssertNil(hit, "Should miss the empty space around the pyramid")
    }
    
    func testIntersectTaperedBlock() {
        // Taper block (1).
        // Top is scaled by 0.4. Height 1.5x.
        // Base width 10. Top width 4.
        let block = createBlock(position: SIMD3<Float>(0, 0, 0), width: 10, height: 10, shapeID: 1)
        
        // Aim at the top flat cap. y > 14? Top is at 15.
        // Let's aim at the side near the top. y=10.
        // At y=10 (mid of top section), width is lerp(10, 4, 0.5) = 7?
        // Actually vertex shader: top vertices moved to 0.4x.
        // So top quad is size 4x4.
        // Bottom of top section (waist) is size 10x10.
        // At y=10 (midway 5..15), width is 7.
        
        // Ray at x=0 should definitely hit
        let rayHit = RayTracer.Ray(origin: SIMD3<Float>(0, 10, 20), direction: SIMD3<Float>(0, 0, -1))
        XCTAssertNotNil(tracer.intersect(ray: rayHit, blocks: [block]))
        
        // Ray at x=4.5 (width 9) should miss (width is ~7)
        let rayMiss = RayTracer.Ray(origin: SIMD3<Float>(4.5, 10, 20), direction: SIMD3<Float>(0, 0, -1))
        XCTAssertNil(tracer.intersect(ray: rayMiss, blocks: [block]), "Should miss the tapered side")
    }
}
