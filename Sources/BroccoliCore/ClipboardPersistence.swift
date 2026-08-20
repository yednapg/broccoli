import CryptoKit
import Foundation
import SQLite3

public enum ClipboardContentKind: String, Codable, CaseIterable, Sendable {
    case text
    case url
    case files
    case image
}

public struct ClipboardRepresentation: Codable, Equatable, Sendable {
    public let type: String
    public let data: Data

    public init(type: String, data: Data) {
        self.type = type
        self.data = data
    }
}

public struct ClipboardPayloadItem: Codable, Equatable, Sendable {
    public let representations: [ClipboardRepresentation]

    public init(representations: [ClipboardRepresentation]) {
        self.representations = representations
    }
}

public struct ClipboardPayload: Codable, Equatable, Sendable {
    public let items: [ClipboardPayloadItem]

    public init(items: [ClipboardPayloadItem]) {
        self.items = items
    }
}

public struct ClipboardItemSummary: Codable, Equatable, Identifiable, Sendable {
    public let id: String
    public let kind: ClipboardContentKind
    public let preview: String
    public let sourceBundleIdentifier: String?
    public let createdAt: Date
    public let byteCount: Int

    public init(
        id: String,
        kind: ClipboardContentKind,
        preview: String,
        sourceBundleIdentifier: String?,
        createdAt: Date,
        byteCount: Int
    ) {
        self.id = id
        self.kind = kind
        self.preview = preview
        self.sourceBundleIdentifier = sourceBundleIdentifier
        self.createdAt = createdAt
        self.byteCount = byteCount
    }
}

public enum ClipboardPersistenceError: Error, LocalizedError {
    case invalidKey
    case encryption
    case database(String)

    public var errorDescription: String? {
        switch self {
        case .invalidKey: "The clipboard encryption key is invalid."
        case .encryption: "Clipboard history could not be encrypted or decrypted."
        case .database(let message): "Clipboard history database error: \(message)"
        }
    }
}

public struct ClipboardCipher: Sendable {
    private let key: SymmetricKey

    public init(keyData: Data) throws {
        guard keyData.count == 32 else { throw ClipboardPersistenceError.invalidKey }
        key = SymmetricKey(data: keyData)
    }

    public func seal(_ data: Data) throws -> Data {
        guard let combined = try AES.GCM.seal(data, using: key).combined else {
            throw ClipboardPersistenceError.encryption
        }
        return combined
    }

    public func open(_ data: Data) throws -> Data {
        do {
            return try AES.GCM.open(AES.GCM.SealedBox(combined: data), using: key)
        } catch {
            throw ClipboardPersistenceError.encryption
        }
    }

    public func digest(_ data: Data) -> Data {
        Data(HMAC<SHA256>.authenticationCode(for: data, using: key))
    }
}

public actor ClipboardStore {
    private struct EncryptedMetadata: Codable {
        let preview: String
        let sourceBundleIdentifier: String?
    }

    private let cipher: ClipboardCipher
    private let databaseURL: URL
    nonisolated(unsafe) private var database: OpaquePointer?
    private static let transientDestructor = unsafeBitCast(-1, to: sqlite3_destructor_type.self)

    public init(databaseURL: URL, keyData: Data) throws {
        cipher = try ClipboardCipher(keyData: keyData)
        self.databaseURL = databaseURL
        try FileManager.default.createDirectory(
            at: databaseURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try? FileManager.default.setAttributes(
            [.posixPermissions: 0o700],
            ofItemAtPath: databaseURL.deletingLastPathComponent().path
        )
        var handle: OpaquePointer?
        let status = sqlite3_open_v2(
            databaseURL.path,
            &handle,
            SQLITE_OPEN_CREATE | SQLITE_OPEN_READWRITE | SQLITE_OPEN_FULLMUTEX,
            nil
        )
        guard status == SQLITE_OK, let handle else {
            throw ClipboardPersistenceError.database("Unable to open local storage.")
        }
        database = handle
        try Self.execute(
            handle,
            sql: """
            PRAGMA journal_mode=WAL;
            PRAGMA synchronous=NORMAL;
            CREATE TABLE IF NOT EXISTS clipboard_items (
                id TEXT PRIMARY KEY,
                created_at REAL NOT NULL,
                expires_at REAL NOT NULL,
                kind TEXT NOT NULL,
                digest BLOB NOT NULL UNIQUE,
                metadata BLOB NOT NULL,
                payload BLOB NOT NULL,
                byte_count INTEGER NOT NULL
            );
            CREATE INDEX IF NOT EXISTS clipboard_created_at
            ON clipboard_items(created_at DESC);
            """
        )
        Self.secureExistingStorage(at: databaseURL)
    }

    deinit {
        if let database { sqlite3_close(database) }
    }

    @discardableResult
    public func save(
        payload: ClipboardPayload,
        kind: ClipboardContentKind,
        preview: String,
        sourceBundleIdentifier: String?,
        createdAt: Date = Date(),
        retentionDays: Int,
        maximumItems: Int
    ) throws -> ClipboardItemSummary {
        guard let database else { throw ClipboardPersistenceError.database("Storage is closed.") }
        let id = UUID().uuidString
        let encoder = PropertyListEncoder()
        encoder.outputFormat = .binary
        let payloadData = try encoder.encode(payload)
        let metadataData = try encoder.encode(
            EncryptedMetadata(preview: preview, sourceBundleIdentifier: sourceBundleIdentifier)
        )
        let encryptedPayload = try cipher.seal(payloadData)
        let encryptedMetadata = try cipher.seal(metadataData)
        let digest = cipher.digest(payloadData)
        let byteCount = payload.items.reduce(0) { total, item in
            total + item.representations.reduce(0) { $0 + $1.data.count }
        }
        let expiresAt = createdAt.addingTimeInterval(Double(retentionDays) * 86_400)

        try Self.execute(database, sql: "BEGIN IMMEDIATE;")
        do {
            try Self.execute(database, sql: "DELETE FROM clipboard_items WHERE digest = ?;") { statement in
                Self.bind(digest, to: statement, index: 1)
            }
            try Self.execute(
                database,
                sql: """
                INSERT INTO clipboard_items
                (id, created_at, expires_at, kind, digest, metadata, payload, byte_count)
                VALUES (?, ?, ?, ?, ?, ?, ?, ?);
                """
            ) { statement in
                Self.bind(id, to: statement, index: 1)
                sqlite3_bind_double(statement, 2, createdAt.timeIntervalSince1970)
                sqlite3_bind_double(statement, 3, expiresAt.timeIntervalSince1970)
                Self.bind(kind.rawValue, to: statement, index: 4)
                Self.bind(digest, to: statement, index: 5)
                Self.bind(encryptedMetadata, to: statement, index: 6)
                Self.bind(encryptedPayload, to: statement, index: 7)
                sqlite3_bind_int64(statement, 8, Int64(byteCount))
            }
            try prune(database: database, maximumItems: maximumItems, now: createdAt)
            try Self.execute(database, sql: "COMMIT;")
            Self.secureExistingStorage(at: databaseURL)
        } catch {
            try? Self.execute(database, sql: "ROLLBACK;")
            throw error
        }

        return ClipboardItemSummary(
            id: id,
            kind: kind,
            preview: preview,
            sourceBundleIdentifier: sourceBundleIdentifier,
            createdAt: createdAt,
            byteCount: byteCount
        )
    }

    public func loadSummaries(maximumItems: Int, now: Date = Date()) throws -> [ClipboardItemSummary] {
        guard let database else { throw ClipboardPersistenceError.database("Storage is closed.") }
        try prune(database: database, maximumItems: maximumItems, now: now)
        Self.secureExistingStorage(at: databaseURL)
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(
            database,
            "SELECT id, created_at, kind, metadata, byte_count FROM clipboard_items ORDER BY created_at DESC LIMIT ?;",
            -1,
            &statement,
            nil
        ) == SQLITE_OK, let statement else { throw Self.error(database) }
        defer { sqlite3_finalize(statement) }
        sqlite3_bind_int(statement, 1, Int32(maximumItems))

        var summaries: [ClipboardItemSummary] = []
        var corruptIDs: [String] = []
        let decoder = PropertyListDecoder()
        while sqlite3_step(statement) == SQLITE_ROW {
            guard let id = Self.text(statement, column: 0),
                  let kindValue = Self.text(statement, column: 2),
                  let kind = ClipboardContentKind(rawValue: kindValue),
                  let metadataCiphertext = Self.data(statement, column: 3) else { continue }
            do {
                let metadataData = try cipher.open(metadataCiphertext)
                let metadata = try decoder.decode(EncryptedMetadata.self, from: metadataData)
                summaries.append(
                    ClipboardItemSummary(
                        id: id,
                        kind: kind,
                        preview: metadata.preview,
                        sourceBundleIdentifier: metadata.sourceBundleIdentifier,
                        createdAt: Date(timeIntervalSince1970: sqlite3_column_double(statement, 1)),
                        byteCount: Int(sqlite3_column_int64(statement, 4))
                    )
                )
            } catch {
                corruptIDs.append(id)
            }
        }
        for id in corruptIDs { try? delete(id: id) }
        return summaries
    }

    public func payload(id: String) throws -> ClipboardPayload? {
        guard let database else { throw ClipboardPersistenceError.database("Storage is closed.") }
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(
            database,
            "SELECT payload FROM clipboard_items WHERE id = ? LIMIT 1;",
            -1,
            &statement,
            nil
        ) == SQLITE_OK, let statement else { throw Self.error(database) }
        defer { sqlite3_finalize(statement) }
        Self.bind(id, to: statement, index: 1)
        guard sqlite3_step(statement) == SQLITE_ROW,
              let encrypted = Self.data(statement, column: 0) else { return nil }
        let decrypted = try cipher.open(encrypted)
        return try PropertyListDecoder().decode(ClipboardPayload.self, from: decrypted)
    }

    public func delete(id: String) throws {
        guard let database else { return }
        try Self.execute(database, sql: "DELETE FROM clipboard_items WHERE id = ?;") { statement in
            Self.bind(id, to: statement, index: 1)
        }
        Self.secureExistingStorage(at: databaseURL)
    }

    public func clear() throws {
        guard let database else { return }
        try Self.execute(database, sql: "DELETE FROM clipboard_items;")
        Self.secureExistingStorage(at: databaseURL)
    }

    private func prune(database: OpaquePointer, maximumItems: Int, now: Date) throws {
        try Self.execute(database, sql: "DELETE FROM clipboard_items WHERE expires_at <= ?;") { statement in
            sqlite3_bind_double(statement, 1, now.timeIntervalSince1970)
        }
        try Self.execute(
            database,
            sql: """
            DELETE FROM clipboard_items WHERE id NOT IN (
                SELECT id FROM clipboard_items ORDER BY created_at DESC LIMIT ?
            );
            """
        ) { statement in
            sqlite3_bind_int(statement, 1, Int32(maximumItems))
        }
    }

    private static func execute(
        _ database: OpaquePointer,
        sql: String,
        bind: ((OpaquePointer) -> Void)? = nil
    ) throws {
        if bind == nil, sql.contains(";") {
            var message: UnsafeMutablePointer<CChar>?
            guard sqlite3_exec(database, sql, nil, nil, &message) == SQLITE_OK else {
                let value = message.map { String(cString: $0) } ?? "Unknown SQLite error"
                sqlite3_free(message)
                throw ClipboardPersistenceError.database(value)
            }
            return
        }
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(database, sql, -1, &statement, nil) == SQLITE_OK,
              let statement else { throw error(database) }
        defer { sqlite3_finalize(statement) }
        bind?(statement)
        guard sqlite3_step(statement) == SQLITE_DONE else { throw error(database) }
    }

    private static func bind(_ value: String, to statement: OpaquePointer, index: Int32) {
        sqlite3_bind_text(statement, index, value, -1, transientDestructor)
    }

    private static func bind(_ value: Data, to statement: OpaquePointer, index: Int32) {
        _ = value.withUnsafeBytes { buffer in
            sqlite3_bind_blob(statement, index, buffer.baseAddress, Int32(buffer.count), transientDestructor)
        }
    }

    private static func text(_ statement: OpaquePointer, column: Int32) -> String? {
        guard let value = sqlite3_column_text(statement, column) else { return nil }
        return String(cString: value)
    }

    private static func data(_ statement: OpaquePointer, column: Int32) -> Data? {
        let count = Int(sqlite3_column_bytes(statement, column))
        guard count > 0, let bytes = sqlite3_column_blob(statement, column) else { return nil }
        return Data(bytes: bytes, count: count)
    }

    private static func error(_ database: OpaquePointer) -> ClipboardPersistenceError {
        ClipboardPersistenceError.database(String(cString: sqlite3_errmsg(database)))
    }

    public static func secureExistingStorage(at databaseURL: URL) {
        let fileManager = FileManager.default
        try? fileManager.setAttributes(
            [.posixPermissions: 0o700],
            ofItemAtPath: databaseURL.deletingLastPathComponent().path
        )
        for path in [databaseURL.path, databaseURL.path + "-wal", databaseURL.path + "-shm"]
            where fileManager.fileExists(atPath: path) {
            try? fileManager.setAttributes([.posixPermissions: 0o600], ofItemAtPath: path)
        }
    }

    public static func discardStorage(at databaseURL: URL) {
        let fileManager = FileManager.default
        for path in [databaseURL.path, databaseURL.path + "-wal", databaseURL.path + "-shm"]
            where fileManager.fileExists(atPath: path) {
            try? fileManager.removeItem(atPath: path)
        }
    }
}
