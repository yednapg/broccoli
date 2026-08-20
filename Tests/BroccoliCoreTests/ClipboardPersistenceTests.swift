import Foundation
import Testing
@testable import BroccoliCore

struct ClipboardPersistenceTests {
    @Test func cipherRoundTripAndTamperRejection() throws {
        let cipher = try ClipboardCipher(keyData: Data(repeating: 7, count: 32))
        let original = Data("private clipboard text".utf8)
        let sealed = try cipher.seal(original)
        #expect(try cipher.open(sealed) == original)

        var tampered = sealed
        tampered[tampered.startIndex] ^= 0xff
        #expect(throws: ClipboardPersistenceError.self) { try cipher.open(tampered) }
    }

    @Test func encryptedStoreRoundTripDeduplicatesAndClears() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("BroccoliClipboardTests-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = try ClipboardStore(
            databaseURL: directory.appendingPathComponent("history.sqlite3"),
            keyData: Data(repeating: 11, count: 32)
        )
        let payload = ClipboardPayload(items: [
            ClipboardPayloadItem(representations: [
                ClipboardRepresentation(type: "public.utf8-plain-text", data: Data("hello".utf8)),
            ]),
        ])

        _ = try await store.save(
            payload: payload,
            kind: .text,
            preview: "hello",
            sourceBundleIdentifier: "example.source",
            retentionDays: 7,
            maximumItems: 100
        )
        let newest = try await store.save(
            payload: payload,
            kind: .text,
            preview: "hello",
            sourceBundleIdentifier: "example.source",
            retentionDays: 7,
            maximumItems: 100
        )

        let summaries = try await store.loadSummaries(maximumItems: 100)
        #expect(summaries.count == 1)
        #expect(summaries.first?.id == newest.id)
        #expect(try await store.payload(id: newest.id) == payload)
        let rawDatabase = try Data(contentsOf: directory.appendingPathComponent("history.sqlite3"))
        #expect(!String(decoding: rawDatabase, as: UTF8.self).contains("hello"))
        try await store.clear()
        #expect(try await store.loadSummaries(maximumItems: 100).isEmpty)
    }

    @Test func retentionRemovesExpiredItems() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("BroccoliClipboardExpiry-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = try ClipboardStore(
            databaseURL: directory.appendingPathComponent("history.sqlite3"),
            keyData: Data(repeating: 19, count: 32)
        )
        let payload = ClipboardPayload(items: [
            .init(representations: [.init(type: "public.text", data: Data("expired".utf8))]),
        ])
        _ = try await store.save(
            payload: payload,
            kind: .text,
            preview: "expired",
            sourceBundleIdentifier: nil,
            createdAt: Date().addingTimeInterval(-3 * 86_400),
            retentionDays: 1,
            maximumItems: 100
        )
        #expect(try await store.loadSummaries(maximumItems: 100).isEmpty)
    }

    @Test func maximumItemLimitAndOwnerOnlyPermissions() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("BroccoliClipboardLimit-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let databaseURL = directory.appendingPathComponent("history.sqlite3")
        let store = try ClipboardStore(databaseURL: databaseURL, keyData: Data(repeating: 21, count: 32))

        for index in 0..<3 {
            let text = "item-\(index)"
            let payload = ClipboardPayload(items: [
                .init(representations: [.init(type: "public.text", data: Data(text.utf8))]),
            ])
            _ = try await store.save(
                payload: payload,
                kind: .text,
                preview: text,
                sourceBundleIdentifier: nil,
                retentionDays: 7,
                maximumItems: 2
            )
        }
        #expect(try await store.loadSummaries(maximumItems: 2).count == 2)

        let fileManager = FileManager.default
        let directoryMode = try fileManager.attributesOfItem(atPath: directory.path)[.posixPermissions] as? NSNumber
        #expect(directoryMode?.intValue == 0o700)
        for path in [databaseURL.path, databaseURL.path + "-wal", databaseURL.path + "-shm"]
            where fileManager.fileExists(atPath: path) {
            let mode = try fileManager.attributesOfItem(atPath: path)[.posixPermissions] as? NSNumber
            #expect(mode?.intValue == 0o600)
        }
    }

    @Test func keyLossDiscardsUnreadableRecordsWithoutCrashing() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("BroccoliClipboardKeyLoss-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let databaseURL = directory.appendingPathComponent("history.sqlite3")
        var original: ClipboardStore? = try ClipboardStore(
            databaseURL: databaseURL,
            keyData: Data(repeating: 31, count: 32)
        )
        let payload = ClipboardPayload(items: [
            .init(representations: [.init(type: "public.text", data: Data("private".utf8))]),
        ])
        _ = try await original?.save(
            payload: payload,
            kind: .text,
            preview: "private",
            sourceBundleIdentifier: nil,
            retentionDays: 7,
            maximumItems: 100
        )
        original = nil

        let replacement = try ClipboardStore(
            databaseURL: databaseURL,
            keyData: Data(repeating: 32, count: 32)
        )
        #expect(try await replacement.loadSummaries(maximumItems: 100).isEmpty)
    }

    @Test func corruptDatabaseFailsClosed() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("BroccoliClipboardCorrupt-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let databaseURL = directory.appendingPathComponent("history.sqlite3")
        try Data("not a sqlite database".utf8).write(to: databaseURL)

        #expect(throws: ClipboardPersistenceError.self) {
            try ClipboardStore(databaseURL: databaseURL, keyData: Data(repeating: 41, count: 32))
        }
    }

    @Test func existingDatabaseSidecarsAreSecuredWithoutOpeningHistory() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("BroccoliClipboardMigration-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let databaseURL = directory.appendingPathComponent("history.sqlite3")
        for path in [databaseURL.path, databaseURL.path + "-wal", databaseURL.path + "-shm"] {
            FileManager.default.createFile(atPath: path, contents: Data())
            try FileManager.default.setAttributes([.posixPermissions: 0o644], ofItemAtPath: path)
        }

        ClipboardStore.secureExistingStorage(at: databaseURL)

        for path in [databaseURL.path, databaseURL.path + "-wal", databaseURL.path + "-shm"] {
            let mode = try FileManager.default.attributesOfItem(atPath: path)[.posixPermissions] as? NSNumber
            #expect(mode?.intValue == 0o600)
        }
    }

    @Test func corruptStorageCanBeDiscardedAndRecreated() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("BroccoliClipboardRecovery-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let databaseURL = directory.appendingPathComponent("history.sqlite3")
        try Data("corrupt sqlite".utf8).write(to: databaseURL)

        ClipboardStore.discardStorage(at: databaseURL)
        _ = try ClipboardStore(
            databaseURL: databaseURL,
            keyData: Data(repeating: 51, count: 32)
        )
        #expect(FileManager.default.fileExists(atPath: databaseURL.path))
    }
}
