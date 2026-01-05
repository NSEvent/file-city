import Foundation
import AppKit

final class FileActions {
    func open(_ url: URL) {
        NSWorkspace.shared.open(url)
    }

    func revealInFinder(_ url: URL) {
        NSWorkspace.shared.activateFileViewerSelecting([url])
    }

    func moveToTrash(_ url: URL) throws {
        try FileManager.default.trashItem(at: url, resultingItemURL: nil)
    }

    func createFolder(at url: URL) throws {
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    }

    func createEmptyFile(at url: URL) throws {
        FileManager.default.createFile(atPath: url.path, contents: nil)
    }

    func moveItem(from src: URL, to dst: URL) throws {
        try FileManager.default.moveItem(at: src, to: dst)
    }

    func renameItem(from src: URL, to dst: URL) throws {
        try FileManager.default.moveItem(at: src, to: dst)
    }
}
