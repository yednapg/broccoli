import Foundation
import XCTest
@testable import BroccoliCore

final class PersistenceTests: XCTestCase {
    func testDiscoveryPolicyRejectsObservedBackgroundAgents() {
        XCTAssertFalse(ApplicationDiscoveryPolicy.isCandidatePath(
            "/System/Library/CoreServices/WallpaperAgent.app"
        ))
        XCTAssertFalse(ApplicationDiscoveryPolicy.isCandidatePath(
            "/System/Library/CoreServices/PreviewShell.app"
        ))
        XCTAssertFalse(ApplicationDiscoveryPolicy.isCandidatePath(
            "/System/Library/PrivateFrameworks/CoreChineseEngine.framework/SharedSupport/CIMFindInputCodeTool.app"
        ))
        XCTAssertFalse(ApplicationDiscoveryPolicy.isCandidatePath(
            "/Applications/Example.app/Contents/Frameworks/Helper.app"
        ))
    }

    func testDiscoveryPolicyAllowsFinderWithoutOpeningSystemLibrary() {
        XCTAssertTrue(ApplicationDiscoveryPolicy.isCandidatePath(
            "/System/Library/CoreServices/Finder.app"
        ))
        XCTAssertTrue(ApplicationDiscoveryPolicy.isCandidatePath(
            "/System/Library/CoreServices/../CoreServices/Finder.app"
        ))
        XCTAssertFalse(ApplicationDiscoveryPolicy.isCandidatePath(
            "/System/Library/CoreServices/WallpaperAgent.app"
        ))
        XCTAssertTrue(ApplicationDiscoveryPolicy.isSupportedApplicationBundle(
            path: "/System/Library/CoreServices/Finder.app",
            packageType: "FNDR",
            bundleIdentifier: "com.apple.finder"
        ))
        XCTAssertFalse(ApplicationDiscoveryPolicy.isSupportedApplicationBundle(
            path: "/System/Library/CoreServices/Finder.app",
            packageType: "FNDR",
            bundleIdentifier: "com.example.finder"
        ))
        XCTAssertTrue(ApplicationDiscoveryPolicy.isSupportedApplicationBundle(
            path: "/Applications/Example.app",
            packageType: "APPL",
            bundleIdentifier: "com.example.app"
        ))
    }

    func testDiscoveryPolicyKeepsUserFacingAndDeveloperApplications() {
        XCTAssertTrue(ApplicationDiscoveryPolicy.isCandidatePath(
            "/Applications/Visual Studio Code - Insiders.app"
        ))
        XCTAssertTrue(ApplicationDiscoveryPolicy.isCandidatePath(
            "/Applications/Xcode-beta.app/Contents/Applications/Instruments.app"
        ))
        XCTAssertTrue(ApplicationDiscoveryPolicy.isCandidatePath(
            "/Volumes/External/Applications/Example.app"
        ))
        let home = URL(fileURLWithPath: "/Users/tester", isDirectory: true)
        XCTAssertTrue(ApplicationDiscoveryPolicy.isUserFacingLocation(
            "/Users/tester/Applications/Test.app",
            homeDirectory: home
        ))
        XCTAssertFalse(ApplicationDiscoveryPolicy.isUserFacingLocation(
            "/Users/tester/ApplicationsOld/Test.app",
            homeDirectory: home
        ))
    }

    func testApplicationBundleIdentifierIsNotUsedAsFuzzyKeyword() {
        let application = CachedApplication(
            path: "/Applications/Things3.app",
            bundleIdentifier: "com.culturedcode.ThingsMac",
            displayName: "Things",
            modifiedAt: nil
        )

        XCTAssertTrue(application.searchEntry.keywords.isEmpty)
    }

    func testApplicationSearchEntryUsesProductNameWithoutBundleExtension() {
        let application = CachedApplication(
            path: "/System/Applications/Calculator.app",
            bundleIdentifier: "com.apple.calculator",
            displayName: "Calculator.app",
            modifiedAt: nil
        )

        XCTAssertEqual(application.searchEntry.title, "Calculator")
        XCTAssertEqual(application.searchEntry.subtitle, "/System/Applications")
    }

    func testCatalogRoundTrip() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("catalog.plist")
        let store = CatalogStore(fileURL: url)
        let value = CachedApplication(
            path: "/Applications/Test.app",
            bundleIdentifier: "com.example.test",
            displayName: "Test",
            modifiedAt: nil
        )
        try await store.save([value])
        let loaded = await store.load()
        XCTAssertEqual(loaded, [value])
        try Data("not a plist".utf8).write(to: url)
        let corrupt = await store.load()
        XCTAssertTrue(corrupt.isEmpty)
    }

    func testRawQueriesAreNotPersisted() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("usage.plist")
        let store = UsageStore(fileURL: url)
        _ = await store.load()
        let sensitiveQuery = "quarterly-acquisition-secret-9F3A"
        await store.recordSelection(id: "app:/Applications/Test.app")
        let persisted = try Data(contentsOf: url)
        XCTAssertFalse(String(decoding: persisted, as: UTF8.self).contains(sensitiveQuery))
        let decoded = try XCTUnwrap(
            PropertyListSerialization.propertyList(from: persisted, options: [], format: nil)
                as? [String: Any]
        )
        let records = try XCTUnwrap(decoded["records"] as? [String: Any])
        XCTAssertEqual(Set(records.keys), ["app:/Applications/Test.app"])
        let snapshot = await store.snapshot()
        XCTAssertEqual(snapshot["app:/Applications/Test.app"]?.selectionCount, 1)
    }

    func testDiagnosticsAreBufferedUntilFlushed() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("diagnostics.json")
        let store = DiagnosticsStore(fileURL: url)

        await store.append(DiagnosticSample(metric: .queryToResults, durationMilliseconds: 1.5))
        XCTAssertFalse(FileManager.default.fileExists(atPath: url.path))

        await store.flush()
        XCTAssertTrue(FileManager.default.fileExists(atPath: url.path))
        let persisted = try Data(contentsOf: url)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let decoded = try decoder.decode([DiagnosticSample].self, from: persisted)
        XCTAssertEqual(decoded.count, 1)
        XCTAssertEqual(decoded.first?.metric, .queryToResults)
    }

    func testDiagnosticsAreBoundedByAgeAndCount() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("diagnostics.json")
        let output = directory.appendingPathComponent("export.json")
        let now = Date()
        let input = [
            DiagnosticSample(metric: .queryToResults, durationMilliseconds: 100, recordedAt: now.addingTimeInterval(-100)),
            DiagnosticSample(metric: .queryToResults, durationMilliseconds: 1, recordedAt: now),
            DiagnosticSample(metric: .returnToDispatch, durationMilliseconds: 2, recordedAt: now),
        ]
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        try encoder.encode(input).write(to: url)

        let store = DiagnosticsStore(fileURL: url, maximumSamples: 1, maximumAge: 10)
        await store.load()
        try await store.export(to: output)

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let exported = try decoder.decode([DiagnosticSample].self, from: Data(contentsOf: output))
        XCTAssertEqual(exported.count, 1)
        XCTAssertEqual(exported.first?.metric, .returnToDispatch)
    }
}
