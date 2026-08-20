import AppKit
import Carbon
import XCTest
@testable import BroccoliApp
import BroccoliCore

@MainActor
final class LauncherModeTests: XCTestCase {
    func testFilePrefixesRequireTrailingWhitespace() {
        XCTAssertNil(LauncherModeController.fileQuery(from: "f"))
        XCTAssertNil(LauncherModeController.fileQuery(from: "find"))
        XCTAssertEqual(LauncherModeController.fileQuery(from: "f report"), "report")
        XCTAssertEqual(LauncherModeController.fileQuery(from: "F REPORT"), "REPORT")
        XCTAssertEqual(LauncherModeController.fileQuery(from: "find invoice"), "invoice")
    }

    func testEscapeLeavesSubmodeBeforeDismissing() {
        let controller = LauncherModeController()
        _ = controller.update(query: "f notes", fileSearchEnabled: true)
        XCTAssertEqual(controller.mode, .fileSearch(query: "notes"))
        XCTAssertTrue(controller.exitSubmode())
        XCTAssertEqual(controller.mode, .main)
        XCTAssertFalse(controller.exitSubmode())

        controller.enterClipboard()
        _ = controller.update(query: "private", fileSearchEnabled: true)
        XCTAssertEqual(controller.mode, .clipboard(query: "private"))
        XCTAssertTrue(controller.exitSubmode())
    }

    func testKeyboardSelectionStopsAtBoundariesAndSkipsStatusRows() {
        let results = [
            result(id: "status", kind: .status),
            result(id: "one", kind: .application),
            result(id: "two", kind: .action),
        ]
        XCTAssertEqual(LauncherSelection.nextRow(currentRow: -1, movingUp: false, results: results), 1)
        XCTAssertNil(LauncherSelection.nextRow(currentRow: 1, movingUp: true, results: results))
        XCTAssertEqual(LauncherSelection.nextRow(currentRow: 1, movingUp: false, results: results), 2)
        XCTAssertNil(LauncherSelection.nextRow(currentRow: 2, movingUp: false, results: results))
    }

    func testStreamingFileResultsPreserveSelectedStableEntry() {
        let reordered = [
            result(id: "new", kind: .file),
            result(id: "first", kind: .file),
            result(id: "selected", kind: .file),
        ]
        XCTAssertEqual(
            LauncherSelection.preferredRow(preservingEntryID: "selected", in: reordered),
            2
        )
        XCTAssertEqual(
            LauncherSelection.preferredRow(preservingEntryID: "removed", in: reordered),
            0
        )
        XCTAssertNil(LauncherSelection.preferredRow(
            preservingEntryID: "status",
            in: [result(id: "status", kind: .status)]
        ))
    }

    func testNumericShortcutsCoverTenVisibleResults() {
        XCTAssertNil(LauncherNumericShortcut.row(for: "1"))
        XCTAssertEqual(LauncherNumericShortcut.row(for: "2"), 1)
        XCTAssertEqual(LauncherNumericShortcut.row(for: "9"), 8)
        XCTAssertEqual(LauncherNumericShortcut.row(for: "0"), 9)
        XCTAssertNil(LauncherNumericShortcut.row(for: "x"))
        XCTAssertEqual(LauncherNumericShortcut.label(forRow: 0), "↩")
        XCTAssertEqual(LauncherNumericShortcut.label(forRow: 8), "⌘9")
        XCTAssertEqual(LauncherNumericShortcut.label(forRow: 9), "⌘0")
    }

    func testClassicPreviewRejectsStaleThumbnailAndMetadataUpdates() {
        XCTAssertTrue(LauncherPreviewUpdateGuard.shouldApply(
            deliveredGeneration: 8,
            currentGeneration: 8,
            expectedRow: 2,
            selectedRow: 2,
            expectedEntryID: "file:/tmp/current",
            visibleEntryID: "file:/tmp/current"
        ))
        XCTAssertFalse(LauncherPreviewUpdateGuard.shouldApply(
            deliveredGeneration: 7,
            currentGeneration: 8,
            expectedRow: 2,
            selectedRow: 2,
            expectedEntryID: "file:/tmp/current",
            visibleEntryID: "file:/tmp/current"
        ))
        XCTAssertFalse(LauncherPreviewUpdateGuard.shouldApply(
            deliveredGeneration: 8,
            currentGeneration: 8,
            expectedRow: 2,
            selectedRow: 3,
            expectedEntryID: "file:/tmp/current",
            visibleEntryID: "file:/tmp/current"
        ))
        XCTAssertFalse(LauncherPreviewUpdateGuard.shouldApply(
            deliveredGeneration: 8,
            currentGeneration: 8,
            expectedRow: 2,
            selectedRow: 2,
            expectedEntryID: "file:/tmp/current",
            visibleEntryID: "file:/tmp/replacement"
        ))
    }

    func testMomentumScrollWorkIsBoundedAndResetAtEnd() {
        var accumulator = LauncherScrollAccumulator()
        XCTAssertEqual(
            accumulator.consume(deltaY: -1_000, precise: true, began: true, ended: false),
            [false, false, false]
        )
        XCTAssertLessThanOrEqual(abs(accumulator.accumulatedDeltaY), 24)
        _ = accumulator.consume(deltaY: 0, precise: true, began: false, ended: true)
        XCTAssertEqual(accumulator.accumulatedDeltaY, 0)
    }

    func testDisruptiveActionRequiresSecondReturnWithinFiveSeconds() {
        let start = Date(timeIntervalSince1970: 1_000)
        var confirmation = DisruptiveActionConfirmation()
        XCTAssertTrue(confirmation.needsConfirmation(for: "power.restart", now: start))
        XCTAssertTrue(confirmation.isPending(for: "power.restart", now: start.addingTimeInterval(4.9)))
        XCTAssertFalse(confirmation.needsConfirmation(for: "power.restart", now: start.addingTimeInterval(4.9)))
        XCTAssertNil(confirmation.id)

        XCTAssertTrue(confirmation.needsConfirmation(for: "power.shutdown", now: start))
        XCTAssertTrue(confirmation.needsConfirmation(for: "power.shutdown", now: start.addingTimeInterval(5)))
        confirmation.cancel()
        XCTAssertFalse(confirmation.isPending(for: "power.shutdown", now: start))
    }

    func testRecoveryActionsRemainSearchableWhenMasterActionsPreferenceIsOff() {
        let suiteName = "LauncherModeTests.recovery.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let preferences = AppPreferences(defaults: defaults)
        preferences.actionsEnabled = false

        let entries = ActionRegistry.searchEntries(
            actionsEnabled: preferences.actionsEnabled,
            enabledActionIDs: preferences.enabledActionIDs
        )
        XCTAssertEqual(Set(entries.map(\.id)), ActionRegistry.recoveryEntryIDs)

        let engine = SearchEngine()
        let snapshot = SearchSnapshot(entries: entries)
        XCTAssertEqual(
            engine.search(
                query: "settings",
                snapshot: snapshot,
                usage: [:],
                preferences: preferences.searchPreferences
            ).map(\.entry.id),
            ["action:broccoli.preferences"]
        )
        XCTAssertEqual(
            engine.search(
                query: "quit",
                snapshot: snapshot,
                usage: [:],
                preferences: preferences.searchPreferences
            ).map(\.entry.id),
            ["action:broccoli.quit"]
        )
    }

    func testPerActionDisableRemovesOnlyThatConfigurableAction() {
        let suiteName = "LauncherModeTests.perAction.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let preferences = AppPreferences(defaults: defaults)
        var enabledActionIDs = preferences.enabledActionIDs
        enabledActionIDs.remove("audio.volumeUp")
        preferences.enabledActionIDs = enabledActionIDs

        let entries = ActionRegistry.searchEntries(
            actionsEnabled: preferences.actionsEnabled,
            enabledActionIDs: preferences.enabledActionIDs
        )
        let entryIDs = Set(entries.map(\.id))

        XCTAssertFalse(entryIDs.contains("action:audio.volumeUp"))
        XCTAssertTrue(entryIDs.contains("action:audio.volumeDown"))
        XCTAssertTrue(ActionRegistry.recoveryEntryIDs.isSubset(of: entryIDs))
    }

    func testActionRegistryRepeatedVolumeBehavior() {
        XCTAssertEqual(ActionRegistry.definition(id: "audio.volumeUp")?.keepsPanelOpen, true)
        XCTAssertEqual(ActionRegistry.definition(id: "audio.volumeDown")?.keepsPanelOpen, true)
        XCTAssertEqual(ActionRegistry.definition(id: "audio.toggleMute")?.keepsPanelOpen, false)
    }

    func testAutomationPermissionStatusMapping() {
        XCTAssertEqual(
            AutomationPermissionState.from(status: noErr, targetIsInstalled: true),
            .allowed
        )
        XCTAssertEqual(
            AutomationPermissionState.from(
                status: OSStatus(errAEEventWouldRequireUserConsent),
                targetIsInstalled: true
            ),
            .notRequested
        )
        XCTAssertEqual(
            AutomationPermissionState.from(
                status: OSStatus(errAEEventNotPermitted),
                targetIsInstalled: true
            ),
            .denied
        )
        XCTAssertEqual(
            AutomationPermissionState.from(
                status: OSStatus(procNotFound),
                targetIsInstalled: true
            ),
            .notRequested,
            "An installed launch-on-demand System Events target must reach first-use consent"
        )
        XCTAssertEqual(
            AutomationPermissionState.from(
                status: OSStatus(procNotFound),
                targetIsInstalled: false
            ),
            .targetUnavailable,
            "procNotFound is a true unavailable state only when the target is not installed"
        )
    }

    func testAutomationPreflightDecisionRoutesEveryPermissionState() {
        XCTAssertEqual(AutomationPreflightDecision.resolve(.allowed), .proceed)
        XCTAssertEqual(AutomationPreflightDecision.resolve(.notRequested), .explainFirstUse)
        XCTAssertEqual(AutomationPreflightDecision.resolve(.denied), .recoverDenied)
        XCTAssertEqual(AutomationPreflightDecision.resolve(.targetUnavailable), .unavailable)
        XCTAssertEqual(AutomationPreflightDecision.resolve(.checking), .proceed)
        XCTAssertEqual(AutomationPreflightDecision.resolve(.unknown(-1)), .proceed)
    }

    func testShortcutRecorderKeepsKnownConfigurationWhenRegistrationRejectsChange() throws {
        let recorder = ShortcutRecorderControl()
        recorder.configuration = .commandSpace
        var attempted: HotKeyConfiguration?
        recorder.onChange = { value in
            attempted = value
            return false
        }

        recorder.keyDown(with: try XCTUnwrap(shortcutEvent(modifiers: [.control])))

        XCTAssertEqual(attempted, .controlSpace)
        XCTAssertEqual(recorder.configuration, .commandSpace)

        recorder.onChange = { _ in true }
        recorder.keyDown(with: try XCTUnwrap(shortcutEvent(modifiers: [.control])))
        XCTAssertEqual(recorder.configuration, .controlSpace)
    }

    func testFileSearchPolicyExcludesPrivateAndBundleContent() {
        let home = URL(fileURLWithPath: "/Users/tester", isDirectory: true)
        XCTAssertTrue(FileSearchPolicy.isAllowed(path: "/Users/tester/Documents/report.pdf", homeDirectory: home))
        XCTAssertTrue(FileSearchPolicy.isAllowed(path: "/Volumes/Work/Projects/report.pdf", homeDirectory: home))
        XCTAssertFalse(FileSearchPolicy.isAllowed(path: "/Users/tester/.secret/report.pdf", homeDirectory: home))
        XCTAssertFalse(FileSearchPolicy.isAllowed(path: "/Users/tester/Library/report.pdf", homeDirectory: home))
        XCTAssertFalse(FileSearchPolicy.isAllowed(path: "/Users/tester/Applications/Test.app/Contents/Info.plist", homeDirectory: home))
        XCTAssertFalse(FileSearchPolicy.isAllowed(path: "/Volumes/Backup/System/report.pdf", homeDirectory: home))
        XCTAssertFalse(FileSearchPolicy.isAllowed(path: "/etc/report.pdf", homeDirectory: home))
    }

    func testLiveFileMetadataFirstUsefulResultWhenRequested() async throws {
        guard ProcessInfo.processInfo.environment["BROCCOLI_RUN_METADATA_TESTS"] == "1" else {
            throw XCTSkip("Live Spotlight integration is opt-in because CI workspaces may not be indexed.")
        }
        let service = FileSearchService()
        // Allow the utility task that prepares mounted-volume scopes to settle outside the
        // measured query. Production performs the same preparation when the coordinator is
        // created, before a user enters file mode.
        try await Task.sleep(for: .milliseconds(250))
        var latencies: [Double] = []
        for generation in 1...20 {
            let firstUsefulResult = expectation(
                description: "First useful metadata result \(generation)"
            )
            let start = ContinuousClock.now
            var delivered = false
            service.search(query: "README", generation: generation, limit: 7) { _, outcome in
                guard case .results(let items) = outcome, !items.isEmpty, !delivered else {
                    return
                }
                delivered = true
                latencies.append(Self.milliseconds(from: start.duration(to: .now)))
                firstUsefulResult.fulfill()
            }
            await fulfillment(of: [firstUsefulResult], timeout: 5)
        }

        let sorted = latencies.sorted()
        let p95 = sorted[min(sorted.count - 1, Int(Double(sorted.count) * 0.95))]
        print(String(format: "Live file metadata first useful result p95: %.3f ms", p95))
        XCTAssertLessThanOrEqual(p95, 150)

        let replacementDelivered = expectation(description: "Replacement metadata query")
        var staleCallbackDelivered = false
        var replacementCallbackDelivered = false
        service.search(query: "Package", generation: 101, limit: 7) { _, _ in
            staleCallbackDelivered = true
        }
        service.search(query: "README", generation: 102, limit: 7) { generation, outcome in
            guard generation == 102,
                  case .results(let items) = outcome,
                  !items.isEmpty,
                  !replacementCallbackDelivered else {
                return
            }
            replacementCallbackDelivered = true
            replacementDelivered.fulfill()
        }
        await fulfillment(of: [replacementDelivered], timeout: 5)
        XCTAssertFalse(staleCallbackDelivered)
    }

    func testLiveColdCatalogBecomesSearchableWhenRequested() async throws {
        guard ProcessInfo.processInfo.environment["BROCCOLI_RUN_CATALOG_TESTS"] == "1" else {
            throw XCTSkip("Live application discovery is opt-in because installed apps vary by runner.")
        }
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("BroccoliCatalogProbe-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let service = ApplicationCatalogService(
            store: CatalogStore(fileURL: directory.appendingPathComponent("catalog.plist"))
        )
        let searchable = expectation(description: "Cold application catalog")
        let start = ContinuousClock.now
        var latencyMilliseconds: Double?
        service.onCatalogChanged = { applications in
            guard !applications.isEmpty, latencyMilliseconds == nil else { return }
            latencyMilliseconds = Self.milliseconds(from: start.duration(to: .now))
            searchable.fulfill()
        }

        service.start()
        await fulfillment(of: [searchable], timeout: 5)
        let latency = try XCTUnwrap(latencyMilliseconds)
        print(String(format: "Live cold application catalog: %.3f ms", latency))
        XCTAssertLessThanOrEqual(latency, 750)
    }

    func testClipboardCapturePreservesSupportedRepresentationsAndHonorsPreferences() throws {
        var preferences = ClipboardPreferences()

        let textPasteboard = pasteboard()
        let textItem = NSPasteboardItem()
        XCTAssertTrue(textItem.setString("hello\nworld", forType: .string))
        XCTAssertTrue(textItem.setData(Data("{\\rtf1 hello}".utf8), forType: .rtf))
        XCTAssertTrue(textPasteboard.writeObjects([textItem]))
        let text = try XCTUnwrap(ClipboardCaptureBuilder.capture(
            textPasteboard,
            preferences: preferences
        ))
        XCTAssertEqual(text.kind, .text)
        XCTAssertEqual(text.preview, "hello world")
        XCTAssertEqual(
            Set(text.payload.items[0].representations.map(\.type)),
            Set([NSPasteboard.PasteboardType.string.rawValue, NSPasteboard.PasteboardType.rtf.rawValue])
        )

        let urlPasteboard = pasteboard(type: .URL, string: "https://example.com/path")
        let url = try XCTUnwrap(ClipboardCaptureBuilder.capture(
            urlPasteboard,
            preferences: preferences
        ))
        XCTAssertEqual(url.kind, .url)
        XCTAssertEqual(url.preview, "https://example.com/path")

        let filePasteboard = pasteboard(type: .fileURL, string: "file:///tmp/Report.pdf")
        let file = try XCTUnwrap(ClipboardCaptureBuilder.capture(
            filePasteboard,
            preferences: preferences
        ))
        XCTAssertEqual(file.kind, .files)
        XCTAssertEqual(file.preview, "Report.pdf")

        for imageType in ClipboardCaptureBuilder.imageTypes {
            let imagePasteboard = pasteboard(type: imageType, data: Data([0, 1, 2, 3]))
            let image = try XCTUnwrap(ClipboardCaptureBuilder.capture(
                imagePasteboard,
                preferences: preferences
            ))
            XCTAssertEqual(image.kind, .image)
            XCTAssertEqual(image.preview, "Image")
            XCTAssertEqual(image.payload.items[0].representations[0].type, imageType.rawValue)
        }

        preferences.capturesImages = false
        XCTAssertNil(ClipboardCaptureBuilder.capture(
            pasteboard(type: .png, data: Data([0, 1])),
            preferences: preferences
        ))
    }

    func testClipboardCaptureRejectsSensitiveMarkersOversizeItemsAndIgnoredSources() {
        let preferences = ClipboardPreferences()
        let concealed = pasteboard(
            type: .init("org.nspasteboard.ConcealedType"),
            data: Data("secret".utf8)
        )
        XCTAssertTrue(ClipboardCaptureBuilder.containsSensitiveMarker(concealed))

        var tinyLimit = preferences
        tinyLimit.maximumItemBytes = 1
        XCTAssertNil(ClipboardCaptureBuilder.capture(
            pasteboard(type: .string, data: Data("too large".utf8)),
            preferences: tinyLimit
        ))

        XCTAssertTrue(ClipboardCaptureBuilder.shouldIgnoreSource(
            "com.1password.1password",
            preferences: preferences
        ))
        XCTAssertTrue(ClipboardCaptureBuilder.shouldIgnoreSource(
            "dev.gauravpandey.broccoli",
            preferences: preferences
        ))
        XCTAssertFalse(ClipboardCaptureBuilder.shouldIgnoreSource(
            "com.apple.TextEdit",
            preferences: preferences
        ))
    }

    func testClipboardRestorePreservesItemsAndRepresentations() throws {
        let text = Data("restored text".utf8)
        let richText = Data("{\\rtf1 restored}".utf8)
        let image = Data([4, 3, 2, 1])
        let payload = ClipboardPayload(items: [
            .init(representations: [
                .init(type: NSPasteboard.PasteboardType.string.rawValue, data: text),
                .init(type: NSPasteboard.PasteboardType.rtf.rawValue, data: richText),
            ]),
            .init(representations: [
                .init(type: NSPasteboard.PasteboardType.png.rawValue, data: image),
            ]),
        ])
        let destination = pasteboard()

        XCTAssertTrue(ClipboardPasteboardWriter.write(payload, to: destination))
        let restored = try XCTUnwrap(destination.pasteboardItems)
        XCTAssertEqual(restored.count, 2)
        XCTAssertEqual(restored[0].data(forType: .string), text)
        XCTAssertEqual(restored[0].data(forType: .rtf), richText)
        XCTAssertEqual(restored[1].data(forType: .png), image)
        XCTAssertFalse(ClipboardPasteboardWriter.write(.init(items: []), to: destination))
        XCTAssertEqual(destination.pasteboardItems?.count, 2)
    }

    private func result(id: String, kind: SearchKind) -> RankedResult {
        RankedResult(
            entry: SearchEntry(id: id, kind: kind, title: id, target: .none),
            score: 0
        )
    }

    private func shortcutEvent(modifiers: NSEvent.ModifierFlags) -> NSEvent? {
        NSEvent.keyEvent(
            with: .keyDown,
            location: .zero,
            modifierFlags: modifiers,
            timestamp: 0,
            windowNumber: 0,
            context: nil,
            characters: " ",
            charactersIgnoringModifiers: " ",
            isARepeat: false,
            keyCode: UInt16(kVK_Space)
        )
    }

    private func pasteboard() -> NSPasteboard {
        let pasteboard = NSPasteboard(name: .init("BroccoliTests.\(UUID().uuidString)"))
        pasteboard.clearContents()
        return pasteboard
    }

    private func pasteboard(
        type: NSPasteboard.PasteboardType,
        string: String
    ) -> NSPasteboard {
        let pasteboard = pasteboard()
        let item = NSPasteboardItem()
        item.setString(string, forType: type)
        pasteboard.writeObjects([item])
        return pasteboard
    }

    private func pasteboard(
        type: NSPasteboard.PasteboardType,
        data: Data
    ) -> NSPasteboard {
        let pasteboard = pasteboard()
        let item = NSPasteboardItem()
        item.setData(data, forType: type)
        pasteboard.writeObjects([item])
        return pasteboard
    }

    private static func milliseconds(from duration: Duration) -> Double {
        let components = duration.components
        return Double(components.seconds) * 1_000
            + Double(components.attoseconds) / 1_000_000_000_000_000
    }
}
