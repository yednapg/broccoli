import Foundation

public struct CachedApplication: Codable, Hashable, Sendable {
    public let path: String
    public let bundleIdentifier: String?
    public let displayName: String
    public let modifiedAt: Date?

    public init(path: String, bundleIdentifier: String?, displayName: String, modifiedAt: Date?) {
        self.path = path
        self.bundleIdentifier = bundleIdentifier
        self.displayName = displayName
        self.modifiedAt = modifiedAt
    }

    public var searchEntry: SearchEntry {
        let title = displayName.lowercased().hasSuffix(".app")
            ? String(displayName.dropLast(4))
            : displayName
        let parentPath = URL(fileURLWithPath: path).deletingLastPathComponent().path
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        let subtitle = parentPath == home ? "~" : parentPath.replacingOccurrences(of: home, with: "~")
        return SearchEntry(
            id: "app:\(path)",
            kind: .application,
            title: title,
            subtitle: subtitle,
            keywords: [],
            iconKey: path,
            target: .application(path: path, bundleIdentifier: bundleIdentifier)
        )
    }
}

private struct VersionedCatalog: Codable {
    let version: Int
    let applications: [CachedApplication]
}

private struct VersionedUsage: Codable {
    let version: Int
    let records: [String: UsageRecord]
}

public enum PersistencePaths {
    public static func applicationSupportDirectory(
        fileManager: FileManager = .default,
        bundleIdentifier: String = "dev.gauravpandey.broccoli"
    ) throws -> URL {
        let base = try fileManager.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )
        let directory = base.appendingPathComponent(bundleIdentifier, isDirectory: true)
        try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }
}

public actor CatalogStore {
    public static let schemaVersion = 2
    private let fileURL: URL

    public init(fileURL: URL) {
        self.fileURL = fileURL
    }

    public func load() -> [CachedApplication] {
        guard let data = try? Data(contentsOf: fileURL) else { return [] }
        let decoder = PropertyListDecoder()
        guard let stored = try? decoder.decode(VersionedCatalog.self, from: data),
              stored.version == Self.schemaVersion else { return [] }
        return stored.applications
    }

    public func save(_ applications: [CachedApplication]) throws {
        let encoder = PropertyListEncoder()
        encoder.outputFormat = .binary
        let data = try encoder.encode(
            VersionedCatalog(version: Self.schemaVersion, applications: applications)
        )
        try data.write(to: fileURL, options: .atomic)
    }
}

public actor UsageStore {
    public static let schemaVersion = 1
    private let fileURL: URL
    private var records: [String: UsageRecord] = [:]

    public init(fileURL: URL) {
        self.fileURL = fileURL
    }

    @discardableResult
    public func load() -> [String: UsageRecord] {
        guard let data = try? Data(contentsOf: fileURL),
              let stored = try? PropertyListDecoder().decode(VersionedUsage.self, from: data),
              stored.version == Self.schemaVersion else {
            records = [:]
            return records
        }
        records = stored.records
        return records
    }

    public func recordSelection(id: String, at date: Date = Date()) async {
        var record = records[id] ?? UsageRecord(selectionCount: 0, lastUsed: date)
        record.selectionCount += 1
        record.lastUsed = date
        records[id] = record
        try? save()
    }

    public func snapshot() -> [String: UsageRecord] {
        records
    }

    public func clear() async {
        records = [:]
        try? save()
    }

    private func save() throws {
        let encoder = PropertyListEncoder()
        encoder.outputFormat = .binary
        let data = try encoder.encode(VersionedUsage(version: Self.schemaVersion, records: records))
        try data.write(to: fileURL, options: .atomic)
    }
}
