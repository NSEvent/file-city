import Foundation

final class MetadataCache {
    struct Entry: Codable {
        let pathHash: String
        let sizeBytes: Int64
        let modifiedAt: Date
        let layoutSeed: UInt64
    }

    func load(from url: URL) throws -> [String: Entry] {
        let data = try Data(contentsOf: url)
        return try JSONDecoder().decode([String: Entry].self, from: data)
    }

    func save(_ entries: [String: Entry], to url: URL) throws {
        let data = try JSONEncoder().encode(entries)
        try data.write(to: url, options: [.atomic])
    }
}
