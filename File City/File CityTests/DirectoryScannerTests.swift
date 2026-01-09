import XCTest
@testable import File_City

final class DirectoryScannerTests: XCTestCase {

    var scanner: DirectoryScanner!
    var tempDir: URL!

    override func setUp() async throws {
        scanner = DirectoryScanner()
        tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
    }

    override func tearDown() async throws {
        try? FileManager.default.removeItem(at: tempDir)
    }

    // MARK: - Helpers

    func createFile(name: String, content: String = "test") throws -> URL {
        let fileURL = tempDir.appendingPathComponent(name)
        try content.write(to: fileURL, atomically: true, encoding: .utf8)
        return fileURL
    }

    func createFolder(name: String) throws -> URL {
        let folderURL = tempDir.appendingPathComponent(name)
        try FileManager.default.createDirectory(at: folderURL, withIntermediateDirectories: true)
        return folderURL
    }

    // MARK: - Basic Scanning Tests

    func testScanEmptyDirectory() async throws {
        let result = try await scanner.scan(url: tempDir, maxDepth: 2, maxNodes: 100)

        XCTAssertEqual(result.root.type, .folder)
        XCTAssertEqual(result.root.children.count, 0)
        XCTAssertEqual(result.nodeCount, 1) // Just the root
    }

    func testScanSingleFile() async throws {
        _ = try createFile(name: "test.txt", content: "hello world")

        let result = try await scanner.scan(url: tempDir, maxDepth: 2, maxNodes: 100)

        XCTAssertEqual(result.root.children.count, 1)
        XCTAssertEqual(result.root.children[0].name, "test.txt")
        XCTAssertEqual(result.root.children[0].type, .file)
        XCTAssertEqual(result.nodeCount, 2)
    }

    func testScanMultipleFiles() async throws {
        for i in 0..<5 {
            _ = try createFile(name: "file\(i).txt")
        }

        let result = try await scanner.scan(url: tempDir, maxDepth: 2, maxNodes: 100)

        XCTAssertEqual(result.root.children.count, 5)
        XCTAssertEqual(result.nodeCount, 6)
    }

    func testScanNestedFolder() async throws {
        let subFolder = try createFolder(name: "subfolder")
        let subFile = subFolder.appendingPathComponent("nested.txt")
        try "nested content".write(to: subFile, atomically: true, encoding: .utf8)

        let result = try await scanner.scan(url: tempDir, maxDepth: 3, maxNodes: 100)

        XCTAssertEqual(result.root.children.count, 1)
        let folder = result.root.children[0]
        XCTAssertEqual(folder.name, "subfolder")
        XCTAssertEqual(folder.type, .folder)
        XCTAssertEqual(folder.children.count, 1)
        XCTAssertEqual(folder.children[0].name, "nested.txt")
    }

    // MARK: - Depth Limiting Tests

    func testMaxDepthLimitsScanning() async throws {
        let level1 = try createFolder(name: "level1")
        let level2 = level1.appendingPathComponent("level2")
        try FileManager.default.createDirectory(at: level2, withIntermediateDirectories: true)
        let level3File = level2.appendingPathComponent("deep.txt")
        try "deep".write(to: level3File, atomically: true, encoding: .utf8)

        // maxDepth = 1 means only scan root's direct children
        let result = try await scanner.scan(url: tempDir, maxDepth: 1, maxNodes: 100)

        let folder = result.root.children.first { $0.name == "level1" }
        XCTAssertNotNil(folder)
        XCTAssertEqual(folder?.children.count, 0) // Not deep enough to see level2
    }

    func testDeepMaxDepthAllowsFullScan() async throws {
        let level1 = try createFolder(name: "level1")
        let level2 = level1.appendingPathComponent("level2")
        try FileManager.default.createDirectory(at: level2, withIntermediateDirectories: true)
        let level3File = level2.appendingPathComponent("deep.txt")
        try "deep".write(to: level3File, atomically: true, encoding: .utf8)

        let result = try await scanner.scan(url: tempDir, maxDepth: 5, maxNodes: 100)

        let level1Folder = result.root.children.first { $0.name == "level1" }
        XCTAssertNotNil(level1Folder)
        XCTAssertEqual(level1Folder?.children.count, 1)
        XCTAssertEqual(level1Folder?.children[0].name, "level2")
        XCTAssertEqual(level1Folder?.children[0].children.count, 1)
        XCTAssertEqual(level1Folder?.children[0].children[0].name, "deep.txt")
    }

    // MARK: - Node Count Limiting Tests

    func testMaxNodesLimitsScanning() async throws {
        for i in 0..<20 {
            _ = try createFile(name: "file\(i).txt")
        }

        let result = try await scanner.scan(url: tempDir, maxDepth: 2, maxNodes: 10)

        XCTAssertLessThanOrEqual(result.nodeCount, 10)
    }

    // MARK: - Git Detection Tests

    func testDetectsGitRepository() async throws {
        let gitDir = tempDir.appendingPathComponent(".git")
        try FileManager.default.createDirectory(at: gitDir, withIntermediateDirectories: true)

        let result = try await scanner.scan(url: tempDir, maxDepth: 2, maxNodes: 100)

        XCTAssertTrue(result.root.isGitRepo)
    }

    func testNonGitFolderNotMarked() async throws {
        let result = try await scanner.scan(url: tempDir, maxDepth: 2, maxNodes: 100)

        XCTAssertFalse(result.root.isGitRepo)
    }

    // MARK: - File Size Tests

    func testFileHasCorrectSize() async throws {
        let content = String(repeating: "a", count: 1000)
        _ = try createFile(name: "sized.txt", content: content)

        let result = try await scanner.scan(url: tempDir, maxDepth: 2, maxNodes: 100)

        let file = result.root.children.first { $0.name == "sized.txt" }
        XCTAssertNotNil(file)
        XCTAssertEqual(file!.sizeBytes, 1000)
    }

    func testFolderSizeAggregatesChildren() async throws {
        let folder = try createFolder(name: "folder")
        let file1 = folder.appendingPathComponent("file1.txt")
        let file2 = folder.appendingPathComponent("file2.txt")
        try String(repeating: "a", count: 500).write(to: file1, atomically: true, encoding: .utf8)
        try String(repeating: "b", count: 500).write(to: file2, atomically: true, encoding: .utf8)

        let result = try await scanner.scan(url: tempDir, maxDepth: 3, maxNodes: 100)

        let folderNode = result.root.children.first { $0.name == "folder" }
        XCTAssertNotNil(folderNode)
        XCTAssertEqual(folderNode!.sizeBytes, 1000)
    }

    // MARK: - Node Type Tests

    func testFileTypeCorrect() async throws {
        _ = try createFile(name: "test.txt")

        let result = try await scanner.scan(url: tempDir, maxDepth: 2, maxNodes: 100)

        let file = result.root.children.first { $0.name == "test.txt" }
        XCTAssertNotNil(file)
        XCTAssertEqual(file!.type, .file)
    }

    func testFolderTypeCorrect() async throws {
        _ = try createFolder(name: "folder")

        let result = try await scanner.scan(url: tempDir, maxDepth: 2, maxNodes: 100)

        let folder = result.root.children.first { $0.name == "folder" }
        XCTAssertNotNil(folder)
        XCTAssertEqual(folder!.type, .folder)
    }

    // MARK: - URL Tests

    func testNodesHaveCorrectURLs() async throws {
        _ = try createFile(name: "test.txt")

        let result = try await scanner.scan(url: tempDir, maxDepth: 2, maxNodes: 100)

        let file = result.root.children.first { $0.name == "test.txt" }
        XCTAssertNotNil(file)
        XCTAssertEqual(file!.url.lastPathComponent, "test.txt")
        XCTAssertTrue(file!.url.path.contains(tempDir.path))
    }

    // MARK: - Edge Cases

    func testScanNonExistentDirectoryThrows() async throws {
        let nonExistent = tempDir.appendingPathComponent("does-not-exist")

        do {
            _ = try await scanner.scan(url: nonExistent, maxDepth: 2, maxNodes: 100)
            XCTFail("Expected error for non-existent directory")
        } catch {
            // Expected
        }
    }
}
