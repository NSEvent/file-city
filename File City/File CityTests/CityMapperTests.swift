import XCTest
import simd
@testable import File_City

final class CityMapperTests: XCTestCase {

    var mapper: CityMapper!
    var pinStore: PinStore!

    override func setUp() {
        super.setUp()
        mapper = CityMapper()
        pinStore = PinStore()
    }

    // MARK: - Helper to create FileNodes

    func createFileNode(name: String, type: FileNode.NodeType, sizeBytes: Int64 = 1000, children: [FileNode] = [], isGitRepo: Bool = false) -> FileNode {
        return FileNode(
            id: UUID(),
            url: URL(fileURLWithPath: "/test/\(name)"),
            name: name,
            type: type,
            sizeBytes: sizeBytes,
            modifiedAt: Date(),
            children: children,
            isHidden: false,
            isGitRepo: isGitRepo,
            isGitClean: false
        )
    }

    // MARK: - Basic Mapping Tests

    func testMapEmptyRoot() {
        let root = createFileNode(name: "empty", type: .folder, children: [])
        let blocks = mapper.map(root: root, rules: .default, pinStore: pinStore)

        // Empty folder produces no blocks (only children are mapped)
        XCTAssertEqual(blocks.count, 0)
    }

    func testMapSingleFile() {
        let file = createFileNode(name: "test.txt", type: .file, sizeBytes: 100)
        let root = createFileNode(name: "root", type: .folder, children: [file])
        let blocks = mapper.map(root: root, rules: .default, pinStore: pinStore)

        XCTAssertEqual(blocks.count, 1)
        XCTAssertTrue(blocks.contains { $0.name == "test.txt" })
    }

    func testMapMultipleFiles() {
        let files = (0..<5).map { i in
            createFileNode(name: "file\(i).txt", type: .file, sizeBytes: Int64(100 * (i + 1)))
        }
        let root = createFileNode(name: "root", type: .folder, children: files)
        let blocks = mapper.map(root: root, rules: .default, pinStore: pinStore)

        XCTAssertEqual(blocks.count, 5)
    }

    func testMapNestedFolders() {
        let innerFile = createFileNode(name: "inner.txt", type: .file)
        let innerFolder = createFileNode(name: "inner", type: .folder, children: [innerFile])
        let root = createFileNode(name: "root", type: .folder, children: [innerFolder])

        let blocks = mapper.map(root: root, rules: .default, pinStore: pinStore)

        XCTAssertTrue(blocks.contains { $0.name == "inner" })
    }

    // MARK: - Position Tests

    func testBlocksDoNotOverlap() {
        let files = (0..<10).map { i in
            createFileNode(name: "file\(i).txt", type: .file, sizeBytes: Int64(100 * (i + 1)))
        }
        let root = createFileNode(name: "root", type: .folder, children: files)
        let blocks = mapper.map(root: root, rules: .default, pinStore: pinStore)

        // Check that blocks don't have overlapping base positions
        var positions = Set<String>()
        for block in blocks {
            let key = "\(Int(block.position.x)),\(Int(block.position.z))"
            XCTAssertFalse(positions.contains(key), "Duplicate position found at \(key)")
            positions.insert(key)
        }
    }

    func testBlocksArePlacedAtGroundLevel() {
        let files = (0..<4).map { i in
            createFileNode(name: "file\(i).txt", type: .file)
        }
        let root = createFileNode(name: "root", type: .folder, children: files)
        let blocks = mapper.map(root: root, rules: .default, pinStore: pinStore)

        // Non-stacked blocks should be at ground level (y=0)
        for block in blocks {
            XCTAssertGreaterThanOrEqual(block.position.y, 0)
        }
    }

    // MARK: - Building Properties Tests

    func testLargerFilesTallerBuildings() {
        let smallFile = createFileNode(name: "small.txt", type: .file, sizeBytes: 100)
        let largeFile = createFileNode(name: "large.txt", type: .file, sizeBytes: 1000000)
        let root = createFileNode(name: "root", type: .folder, children: [smallFile, largeFile])

        let blocks = mapper.map(root: root, rules: .default, pinStore: pinStore)

        let smallBlock = blocks.first { $0.name == "small.txt" }
        let largeBlock = blocks.first { $0.name == "large.txt" }

        XCTAssertNotNil(smallBlock)
        XCTAssertNotNil(largeBlock)
        XCTAssertGreaterThanOrEqual(largeBlock!.height, smallBlock!.height)
    }

    // MARK: - Git Repository Tests

    func testGitRepoFlagged() {
        let folder = createFileNode(name: "gitrepo", type: .folder, children: [], isGitRepo: true)
        let root = createFileNode(name: "root", type: .folder, children: [folder])

        let blocks = mapper.map(root: root, rules: .default, pinStore: pinStore)

        let repoBlock = blocks.first { $0.name == "gitrepo" }
        XCTAssertNotNil(repoBlock)
        XCTAssertTrue(repoBlock!.isGitRepo)
    }

    // MARK: - Determinism Tests

    func testMappingIsDeterministic() {
        let files = (0..<5).map { i in
            createFileNode(name: "file\(i).txt", type: .file)
        }
        let root = createFileNode(name: "root", type: .folder, children: files)

        let blocks1 = mapper.map(root: root, rules: .default, pinStore: pinStore)
        let blocks2 = mapper.map(root: root, rules: .default, pinStore: pinStore)

        // Same input should produce same output
        XCTAssertEqual(blocks1.count, blocks2.count)

        for (b1, b2) in zip(blocks1, blocks2) {
            XCTAssertEqual(b1.name, b2.name)
            XCTAssertEqual(b1.materialID, b2.materialID)
            XCTAssertEqual(b1.textureIndex, b2.textureIndex)
            XCTAssertEqual(b1.shapeID, b2.shapeID)
        }
    }

    // MARK: - Shape ID Tests

    func testValidShapeIDs() {
        let files = (0..<20).map { i in
            createFileNode(name: "file\(i).txt", type: .file, sizeBytes: Int64(1000 * (i + 1)))
        }
        let root = createFileNode(name: "root", type: .folder, children: files)

        let blocks = mapper.map(root: root, rules: .default, pinStore: pinStore)

        // All shape IDs should be valid (0-5 for buildings)
        for block in blocks {
            XCTAssertGreaterThanOrEqual(block.shapeID, 0)
            XCTAssertLessThanOrEqual(block.shapeID, 5, "Invalid shapeID: \(block.shapeID) for \(block.name)")
        }
    }

    // MARK: - Texture Index Tests

    func testValidTextureIndices() {
        let files = (0..<10).map { i in
            createFileNode(name: "file\(i).txt", type: .file)
        }
        let root = createFileNode(name: "root", type: .folder, children: files)

        let blocks = mapper.map(root: root, rules: .default, pinStore: pinStore)

        // Texture indices should be in valid range
        for block in blocks {
            XCTAssertGreaterThanOrEqual(block.textureIndex, 0)
            XCTAssertLessThan(block.textureIndex, 36, "Invalid textureIndex: \(block.textureIndex)")
        }
    }

    // MARK: - CityBlock Extension Tests

    func testVisualTopYStandard() {
        let block = CityBlock(
            id: UUID(),
            nodeID: UUID(),
            name: "test",
            position: SIMD3<Float>(0, 0, 0),
            footprint: SIMD2<Int32>(5, 5),
            height: 10,
            materialID: 0,
            textureIndex: 0,
            shapeID: 0,
            isPinned: false,
            isGitRepo: false,
            isGitClean: false
        )

        // Standard shape: visualTopY = baseTopY = position.y + height
        XCTAssertEqual(block.visualTopY, 10.0, accuracy: 0.001)
        XCTAssertEqual(block.baseTopY, 10.0, accuracy: 0.001)
    }

    func testVisualTopYTaper() {
        let block = CityBlock(
            id: UUID(),
            nodeID: UUID(),
            name: "test",
            position: SIMD3<Float>(0, 0, 0),
            footprint: SIMD2<Int32>(5, 5),
            height: 10,
            materialID: 0,
            textureIndex: 0,
            shapeID: 1, // Taper
            isPinned: false,
            isGitRepo: false,
            isGitClean: false
        )

        // Taper: visualTopY = baseTopY + height * 0.5 = 10 + 5 = 15
        XCTAssertEqual(block.baseTopY, 10.0, accuracy: 0.001)
        XCTAssertEqual(block.visualTopY, 15.0, accuracy: 0.001)
    }

    func testVisualTopYWedge() {
        let block = CityBlock(
            id: UUID(),
            nodeID: UUID(),
            name: "test",
            position: SIMD3<Float>(0, 0, 0),
            footprint: SIMD2<Int32>(5, 5),
            height: 10,
            materialID: 0,
            textureIndex: 0,
            shapeID: 3, // SlantX
            isPinned: false,
            isGitRepo: false,
            isGitClean: false
        )

        // Wedge: visualTopY = baseTopY + height * 0.75 = 10 + 7.5 = 17.5
        XCTAssertEqual(block.baseTopY, 10.0, accuracy: 0.001)
        XCTAssertEqual(block.visualTopY, 17.5, accuracy: 0.001)
        XCTAssertTrue(block.isWedge)
    }

    func testIsWedge() {
        let standard = CityBlock(id: UUID(), nodeID: UUID(), name: "test", position: .zero, footprint: SIMD2<Int32>(5, 5), height: 10, materialID: 0, textureIndex: 0, shapeID: 0, isPinned: false, isGitRepo: false, isGitClean: false)
        let slantX = CityBlock(id: UUID(), nodeID: UUID(), name: "test", position: .zero, footprint: SIMD2<Int32>(5, 5), height: 10, materialID: 0, textureIndex: 0, shapeID: 3, isPinned: false, isGitRepo: false, isGitClean: false)
        let slantZ = CityBlock(id: UUID(), nodeID: UUID(), name: "test", position: .zero, footprint: SIMD2<Int32>(5, 5), height: 10, materialID: 0, textureIndex: 0, shapeID: 4, isPinned: false, isGitRepo: false, isGitClean: false)

        XCTAssertFalse(standard.isWedge)
        XCTAssertTrue(slantX.isWedge)
        XCTAssertTrue(slantZ.isWedge)
    }
}
