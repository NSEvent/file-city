import AppKit
import Foundation

/// Reads Finder sidebar favorites from the system shared file list
final class FinderFavoritesReader {
    struct Favorite: Identifiable {
        let id = UUID()
        let name: String
        let url: URL
        /// SF Symbol name for sidebar icon (matches Finder's modern style)
        let symbolName: String

        init(name: String, url: URL) {
            self.name = name
            self.url = url
            self.symbolName = Self.sidebarSymbol(for: url)
        }

        /// Maps folder URLs to their Finder sidebar SF Symbols (outline style)
        private static func sidebarSymbol(for url: URL) -> String {
            let path = url.path
            let home = FileManager.default.homeDirectoryForCurrentUser.path
            let name = url.lastPathComponent.lowercased()

            // Special system folders (matching Finder's exact icons)
            if path == "/Applications" { return "a.circle" }  // App Store style A
            if path == home { return "house" }
            if path == "\(home)/Desktop" { return "menubar.dock.rectangle" }
            if path == "\(home)/Documents" { return "doc" }
            if path == "\(home)/Downloads" { return "arrow.down.circle" }
            if path == "\(home)/Movies" { return "film" }  // Film strip with sprocket holes
            if path == "\(home)/Music" { return "music.note.list" }  // Two connected notes
            if path == "\(home)/Pictures" { return "photo" }
            if path == "\(home)/Library" { return "building.columns" }
            if path == "\(home)/Public" { return "folder.badge.person.crop" }

            // iCloud Drive
            if path.contains("Mobile Documents/com~apple~CloudDocs") { return "icloud" }

            // Dropbox detection - open box shape
            if name == "dropbox" || path.contains("/Dropbox") { return "archivebox" }

            // Default folder icon (outline)
            return "folder"
        }
    }

    /// Extract UID value from CFKeyedArchiverUID using string description parsing
    private static func getUID(from cfuid: Any) -> Int? {
        // CFKeyedArchiverUID can't be directly cast to a dictionary.
        // Parse the value from its string description: "<CFKeyedArchiverUID ...>{value = N}"
        let desc = String(describing: cfuid)
        if let match = desc.range(of: "value = ") {
            let valueStr = desc[match.upperBound...]
            if let endBrace = valueStr.firstIndex(of: "}") {
                return Int(String(valueStr[..<endBrace]))
            }
        }
        return nil
    }

    /// Reads Finder favorites from the .sfl2/.sfl3/.sfl4 file
    /// Note: Requires Full Disk Access permission to read ~/Library/Application Support/com.apple.sharedfilelist/
    static func readFavorites() -> [Favorite] {
        let homeDir = FileManager.default.homeDirectoryForCurrentUser
        let sharedFileListDir = homeDir.appendingPathComponent(
            "Library/Application Support/com.apple.sharedfilelist"
        )

        // Try different versions (newer macOS uses .sfl4, older uses .sfl2/.sfl3)
        let fileNames = [
            "com.apple.LSSharedFileList.FavoriteItems.sfl4",
            "com.apple.LSSharedFileList.FavoriteItems.sfl3",
            "com.apple.LSSharedFileList.FavoriteItems.sfl2"
        ]

        for fileName in fileNames {
            let fileURL = sharedFileListDir.appendingPathComponent(fileName)
            if let favorites = parseSFLFile(at: fileURL), !favorites.isEmpty {
                return favorites
            }
        }

        return []
    }

    private static func parseSFLFile(at url: URL) -> [Favorite]? {
        guard let data = try? Data(contentsOf: url) else {
            return nil
        }

        // The file is an NSKeyedArchiver plist
        guard let plist = try? PropertyListSerialization.propertyList(
            from: data,
            options: [],
            format: nil
        ) as? [String: Any] else {
            return nil
        }

        // NSKeyedArchiver format has $objects array with CFKeyedArchiverUID references
        guard let objects = plist["$objects"] as? [Any] else {
            return nil
        }

        var favorites: [Favorite] = []

        // Find all bookmark data in the objects array
        for obj in objects {
            guard let dict = obj as? [String: Any] else { continue }

            // Look for SFLListItem objects that have bookmark data
            if let bookmarkData = findBookmarkData(in: dict, objects: objects) {
                if let favorite = resolveFavorite(from: bookmarkData, dict: dict, objects: objects) {
                    favorites.append(favorite)
                }
            }
        }

        return favorites
    }

    private static func findBookmarkData(in dict: [String: Any], objects: [Any]) -> Data? {
        // NSKeyedArchiver dictionaries use NS.keys and NS.objects arrays
        // Keys are CFKeyedArchiverUID references to strings in the $objects array
        guard let nsKeys = dict["NS.keys"] as? [Any],
              let nsObjects = dict["NS.objects"] as? [Any] else {
            return nil
        }

        // Find the index where the key resolves to "Bookmark"
        for (index, keyRef) in nsKeys.enumerated() {
            guard let keyUID = getUID(from: keyRef),
                  keyUID < objects.count,
                  let keyName = objects[keyUID] as? String,
                  keyName == "Bookmark" else {
                continue
            }

            // Found the Bookmark key, get the corresponding object
            guard index < nsObjects.count,
                  let valueUID = getUID(from: nsObjects[index]),
                  valueUID < objects.count,
                  let bookmarkData = objects[valueUID] as? Data else {
                continue
            }

            return bookmarkData
        }

        return nil
    }

    private static func resolveFavorite(from bookmarkData: Data, dict: [String: Any], objects: [Any]) -> Favorite? {
        var isStale = false

        // Try to resolve the bookmark to a URL
        guard let url = try? URL(
            resolvingBookmarkData: bookmarkData,
            options: [.withoutUI, .withoutMounting],
            relativeTo: nil,
            bookmarkDataIsStale: &isStale
        ) else {
            return nil
        }

        // Only include directories
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory),
              isDirectory.boolValue else {
            return nil
        }

        // Get the name - try to extract from dict or use URL
        let name = extractName(from: dict, objects: objects) ?? url.lastPathComponent

        return Favorite(name: name, url: url)
    }

    private static func extractName(from dict: [String: Any], objects: [Any]) -> String? {
        // NSKeyedArchiver dictionaries use NS.keys and NS.objects arrays
        guard let nsKeys = dict["NS.keys"] as? [Any],
              let nsObjects = dict["NS.objects"] as? [Any] else {
            return nil
        }

        // Find the index where the key resolves to "Name"
        for (index, keyRef) in nsKeys.enumerated() {
            guard let keyUID = getUID(from: keyRef),
                  keyUID < objects.count,
                  let keyName = objects[keyUID] as? String,
                  keyName == "Name" else {
                continue
            }

            // Found the Name key, get the corresponding object
            guard index < nsObjects.count,
                  let valueUID = getUID(from: nsObjects[index]),
                  valueUID < objects.count,
                  let name = objects[valueUID] as? String else {
                continue
            }

            return name
        }

        return nil
    }
}
