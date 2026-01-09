import XCTest
@testable import File_City

final class GitServiceTests: XCTestCase {

    // MARK: - formatStatusLine Tests

    func testFormatUntrackedFile() {
        let line = "?? newfile.txt"
        let formatted = GitService.formatStatusLine(line)
        XCTAssertEqual(formatted, "Untracked:\tnewfile.txt")
    }

    func testFormatModifiedUnstaged() {
        let line = " M modified.txt"
        let formatted = GitService.formatStatusLine(line)
        XCTAssertEqual(formatted, "Modified:\tmodified.txt")
    }

    func testFormatModifiedStaged() {
        let line = "M  staged.txt"
        let formatted = GitService.formatStatusLine(line)
        XCTAssertEqual(formatted, "Staged:\tstaged.txt")
    }

    func testFormatAddedFile() {
        let line = "A  added.txt"
        let formatted = GitService.formatStatusLine(line)
        XCTAssertEqual(formatted, "Added:\tadded.txt")
    }

    func testFormatDeletedFile() {
        let line = " D deleted.txt"
        let formatted = GitService.formatStatusLine(line)
        XCTAssertEqual(formatted, "Deleted:\tdeleted.txt")
    }

    func testFormatRenamedFile() {
        let line = "R  old.txt -> new.txt"
        let formatted = GitService.formatStatusLine(line)
        XCTAssertEqual(formatted, "Renamed:\told.txt -> new.txt")
    }

    func testFormatUnknownStatus() {
        let line = "XX unknown.txt"
        let formatted = GitService.formatStatusLine(line)
        XCTAssertEqual(formatted, "XX unknown.txt")
    }

    func testFormatShortLine() {
        let line = "AB"
        let formatted = GitService.formatStatusLine(line)
        XCTAssertEqual(formatted, "AB")
    }

    func testFormatEmptyLine() {
        let line = ""
        let formatted = GitService.formatStatusLine(line)
        XCTAssertEqual(formatted, "")
    }

    // MARK: - isGitRepository Tests

    func testIsGitRepositoryNonExistent() {
        let url = URL(fileURLWithPath: "/nonexistent/path")
        let result = GitService.isGitRepository(at: url)
        XCTAssertFalse(result)
    }

    func testIsGitRepositoryTempDir() {
        // Create a temp directory without .git
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try? FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let result = GitService.isGitRepository(at: tempDir)
        XCTAssertFalse(result)
    }

    func testIsGitRepositoryWithGitDir() {
        // Create a temp directory with .git
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let gitDir = tempDir.appendingPathComponent(".git")
        try? FileManager.default.createDirectory(at: gitDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let result = GitService.isGitRepository(at: tempDir)
        XCTAssertTrue(result)
    }

    // MARK: - StatusResult Tests

    func testStatusResultSuccess() {
        let result = GitService.StatusResult(output: "## main", error: "")
        XCTAssertTrue(result.isSuccess)
    }

    func testStatusResultErrorEmpty() {
        let result = GitService.StatusResult(output: "", error: "")
        XCTAssertFalse(result.isSuccess)
    }

    func testStatusResultWithError() {
        let result = GitService.StatusResult(output: "", error: "fatal: not a git repository")
        XCTAssertFalse(result.isSuccess)
    }

    // MARK: - Edge Cases

    func testFormatStatusLineWithSpacesInPath() {
        let line = " M path with spaces/file.txt"
        let formatted = GitService.formatStatusLine(line)
        XCTAssertEqual(formatted, "Modified:\tpath with spaces/file.txt")
    }

    func testFormatStatusLineWithUnicode() {
        let line = " M 文件.txt"
        let formatted = GitService.formatStatusLine(line)
        XCTAssertEqual(formatted, "Modified:\t文件.txt")
    }
}
