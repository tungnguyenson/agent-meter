import Foundation

protocol SnapshotCacheStoring {
    func save(_ snapshot: UsageSnapshot) throws
    func load(providerID: ProviderID, maxAge: TimeInterval?) -> UsageSnapshot?
    func clear(providerID: ProviderID) throws
}

final class SnapshotCacheManager: SnapshotCacheStoring {
    static let shared = SnapshotCacheManager()

    private let fileManager: FileManager
    private let directory: URL
    private let defaultMaxAge: TimeInterval

    init(
        fileManager: FileManager = .default,
        directory: URL? = nil,
        defaultMaxAge: TimeInterval = 24 * 3600
    ) {
        self.fileManager = fileManager
        self.defaultMaxAge = defaultMaxAge
        let caches = fileManager.urls(for: .cachesDirectory, in: .userDomainMask).first
            ?? fileManager.temporaryDirectory
        self.directory = directory
            ?? caches.appendingPathComponent("AgentMeter/Providers", isDirectory: true)
        try? fileManager.createDirectory(
            at: self.directory,
            withIntermediateDirectories: true
        )
    }

    func save(_ snapshot: UsageSnapshot) throws {
        let entry = SnapshotCacheEntry(
            schemaVersion: 2,
            savedAt: Date(),
            snapshot: snapshot
        )
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(entry)
        try data.write(to: fileURL(for: snapshot.providerID), options: .atomic)
    }

    func load(providerID: ProviderID, maxAge: TimeInterval? = nil) -> UsageSnapshot? {
        let url = fileURL(for: providerID)
        guard let data = try? Data(contentsOf: url) else { return nil }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        guard let entry = try? decoder.decode(SnapshotCacheEntry.self, from: data),
              entry.schemaVersion == 2 else {
            return nil
        }
        let effectiveMaxAge = maxAge ?? defaultMaxAge
        guard Date().timeIntervalSince(entry.savedAt) <= effectiveMaxAge else {
            try? fileManager.removeItem(at: url)
            return nil
        }
        return entry.snapshot
    }

    func clear(providerID: ProviderID) throws {
        let url = fileURL(for: providerID)
        guard fileManager.fileExists(atPath: url.path) else { return }
        try fileManager.removeItem(at: url)
    }

    private func fileURL(for providerID: ProviderID) -> URL {
        directory.appendingPathComponent("\(providerID.rawValue).json")
    }
}

private struct SnapshotCacheEntry: Codable {
    let schemaVersion: Int
    let savedAt: Date
    let snapshot: UsageSnapshot
}
