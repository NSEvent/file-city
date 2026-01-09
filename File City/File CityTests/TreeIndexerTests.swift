import XCTest
@testable import File_City

final class TreeIndexerTests: XCTestCase {

    // MARK: - Helper to create FileNodes

    func createFileNode(name: String, type: FileNode.NodeType, children: [FileNode] = []) -> FileNode {
        return FileNode(
            id: UUID(),
            url: URL(fileURLWithPath: "/test/\(name)"),
            name: name,
            type: type,
            sizeBytes: 1000,
            modifiedAt: Date(),
            children: children,
            isHidden: false,
            isGitRepo: false,
            isGitClean: false
        )
    }

    // MARK: - countNodes Tests

    func testCountNodesSingleNode() {
        let node = createFileNode(name: "single", type: .file)
        XCTAssertEqual(TreeIndexer.countNodes(node), 1)
    }

    func testCountNodesWithChildren() {
        let child1 = createFileNode(name: "child1", type: .file)
        let child2 = createFileNode(name: "child2", type: .file)
        let parent = createFileNode(name: "parent", type: .folder, children: [child1, child2])

        XCTAssertEqual(TreeIndexer.countNodes(parent), 3)
    }

    func testCountNodesDeepNesting() {
        let leaf = createFileNode(name: "leaf", type: .file)
        let level2 = createFileNode(name: "level2", type: .folder, children: [leaf])
        let level1 = createFileNode(name: "level1", type: .folder, children: [level2])
        let root = createFileNode(name: "root", type: .folder, children: [level1])

        XCTAssertEqual(TreeIndexer.countNodes(root), 4)
    }

    // MARK: - buildNodeByID Tests

    func testBuildNodeByIDSingleNode() {
        let node = createFileNode(name: "single", type: .file)
        let map = TreeIndexer.buildNodeByID(root: node)

        XCTAssertEqual(map.count, 1)
        XCTAssertEqual(map[node.id]?.name, "single")
    }

    func testBuildNodeByIDWithChildren() {
        let child1 = createFileNode(name: "child1", type: .file)
        let child2 = createFileNode(name: "child2", type: .file)
        let parent = createFileNode(name: "parent", type: .folder, children: [child1, child2])

        let map = TreeIndexer.buildNodeByID(root: parent)

        XCTAssertEqual(map.count, 3)
        XCTAssertNotNil(map[parent.id])
        XCTAssertNotNil(map[child1.id])
        XCTAssertNotNil(map[child2.id])
    }

    // MARK: - buildNodeByURL Tests

    func testBuildNodeByURLSingleNode() {
        let node = createFileNode(name: "single", type: .file)
        let map = TreeIndexer.buildNodeByURL(root: node)

        XCTAssertEqual(map.count, 1)
        XCTAssertNotNil(map[node.url])
    }

    func testBuildNodeByURLWithChildren() {
        let child1 = createFileNode(name: "child1", type: .file)
        let child2 = createFileNode(name: "child2", type: .file)
        let parent = createFileNode(name: "parent", type: .folder, children: [child1, child2])

        let map = TreeIndexer.buildNodeByURL(root: parent)

        XCTAssertEqual(map.count, 3)
        XCTAssertEqual(map[parent.url]?.name, "parent")
        XCTAssertEqual(map[child1.url]?.name, "child1")
        XCTAssertEqual(map[child2.url]?.name, "child2")
    }

    // MARK: - buildFocusMap Tests

    func testBuildFocusMapEmpty() {
        let root = createFileNode(name: "root", type: .folder, children: [])
        let map = TreeIndexer.buildFocusMap(root: root)

        // Root itself is not included in focus map (only children are)
        XCTAssertEqual(map.count, 0)
    }

    func testBuildFocusMapSingleChild() {
        let child = createFileNode(name: "child", type: .file)
        let root = createFileNode(name: "root", type: .folder, children: [child])

        let map = TreeIndexer.buildFocusMap(root: root)

        XCTAssertEqual(map.count, 1)
        XCTAssertEqual(map[child.url], child.id)
    }

    func testBuildFocusMapNestedChildrenMapToParent() {
        // Create: root -> folder1 -> file1
        // file1 should map to folder1's ID (its first-level ancestor)
        let file1 = createFileNode(name: "file1", type: .file)
        let folder1 = createFileNode(name: "folder1", type: .folder, children: [file1])
        let root = createFileNode(name: "root", type: .folder, children: [folder1])

        let map = TreeIndexer.buildFocusMap(root: root)

        // Both folder1 and file1 should map to folder1's ID
        XCTAssertEqual(map[folder1.url], folder1.id)
        XCTAssertEqual(map[file1.url], folder1.id)
    }

    func testBuildFocusMapMultipleBranches() {
        let file1 = createFileNode(name: "file1", type: .file)
        let file2 = createFileNode(name: "file2", type: .file)
        let folder1 = createFileNode(name: "folder1", type: .folder, children: [file1])
        let folder2 = createFileNode(name: "folder2", type: .folder, children: [file2])
        let root = createFileNode(name: "root", type: .folder, children: [folder1, folder2])

        let map = TreeIndexer.buildFocusMap(root: root)

        // file1 maps to folder1, file2 maps to folder2
        XCTAssertEqual(map[file1.url], folder1.id)
        XCTAssertEqual(map[file2.url], folder2.id)
        XCTAssertNotEqual(map[file1.url], map[file2.url])
    }

    // MARK: - buildNodeIDByURL Tests

    func testBuildNodeIDByURL() {
        let child = createFileNode(name: "child", type: .file)
        let parent = createFileNode(name: "parent", type: .folder, children: [child])

        let map = TreeIndexer.buildNodeIDByURL(root: parent)

        XCTAssertEqual(map.count, 2)
        XCTAssertEqual(map[parent.url], parent.id)
        XCTAssertEqual(map[child.url], child.id)
    }

    // MARK: - Generic buildMap Tests

    func testBuildMapCustomExtractors() {
        let node = createFileNode(name: "test", type: .file)

        // Build a map from name to type
        let map = TreeIndexer.buildMap(
            root: node,
            keyExtractor: \.name,
            valueExtractor: \.type
        )

        XCTAssertEqual(map.count, 1)
        XCTAssertEqual(map["test"], .file)
    }

    // MARK: - allURLs Tests

    func testAllURLsSingleNode() {
        let node = createFileNode(name: "single", type: .file)
        let urls = TreeIndexer.allURLs(root: node)

        XCTAssertEqual(urls.count, 1)
        XCTAssertTrue(urls.contains(node.url))
    }

    func testAllURLsWithChildren() {
        let child1 = createFileNode(name: "child1", type: .file)
        let child2 = createFileNode(name: "child2", type: .file)
        let parent = createFileNode(name: "parent", type: .folder, children: [child1, child2])

        let urls = TreeIndexer.allURLs(root: parent)

        XCTAssertEqual(urls.count, 3)
        XCTAssertTrue(urls.contains(parent.url))
        XCTAssertTrue(urls.contains(child1.url))
        XCTAssertTrue(urls.contains(child2.url))
    }

    // MARK: - findNode Tests

    func testFindNodeAtRoot() {
        let node = createFileNode(name: "root", type: .folder)
        let found = TreeIndexer.findNode(url: node.url, in: node)

        XCTAssertNotNil(found)
        XCTAssertEqual(found?.name, "root")
    }

    func testFindNodeInChildren() {
        let child = createFileNode(name: "child", type: .file)
        let root = createFileNode(name: "root", type: .folder, children: [child])

        let found = TreeIndexer.findNode(url: child.url, in: root)

        XCTAssertNotNil(found)
        XCTAssertEqual(found?.name, "child")
    }

    func testFindNodeDeepNesting() {
        let leaf = createFileNode(name: "leaf", type: .file)
        let level2 = createFileNode(name: "level2", type: .folder, children: [leaf])
        let level1 = createFileNode(name: "level1", type: .folder, children: [level2])
        let root = createFileNode(name: "root", type: .folder, children: [level1])

        let found = TreeIndexer.findNode(url: leaf.url, in: root)

        XCTAssertNotNil(found)
        XCTAssertEqual(found?.name, "leaf")
    }

    func testFindNodeNotFound() {
        let root = createFileNode(name: "root", type: .folder)
        let nonExistentURL = URL(fileURLWithPath: "/nonexistent")

        let found = TreeIndexer.findNode(url: nonExistentURL, in: root)

        XCTAssertNil(found)
    }
}
