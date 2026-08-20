@preconcurrency import AppKit
import BroccoliCore
import Foundation

@MainActor
final class ClipboardMonitor {
    private let store: ClipboardStore
    private var preferences: ClipboardPreferences
    private var timer: DispatchSourceTimer?
    private var activationObserver: NSObjectProtocol?
    private var lastChangeCount: Int
    private var suppressedChangeCount: Int?
    private var activeBundleIdentifier: String?
    private(set) var summaries: [ClipboardItemSummary] = []
    private var normalizedSummaries: [(summary: ClipboardItemSummary, preview: String)] = []

    var onChange: (([ClipboardItemSummary]) -> Void)?

    init(store: ClipboardStore, preferences: ClipboardPreferences) {
        self.store = store
        self.preferences = preferences
        lastChangeCount = NSPasteboard.general.changeCount
        activeBundleIdentifier = NSWorkspace.shared.frontmostApplication?.bundleIdentifier
    }

    func start() {
        reloadSummaries()
        guard preferences.enabled, timer == nil else { return }
        // Enabling history begins at the current pasteboard generation. Content copied while
        // monitoring was disabled must never be captured retroactively.
        lastChangeCount = NSPasteboard.general.changeCount
        activeBundleIdentifier = NSWorkspace.shared.frontmostApplication?.bundleIdentifier
        installActivationObserver()
        let source = DispatchSource.makeTimerSource(queue: .global(qos: .utility))
        source.schedule(deadline: .now() + 1, repeating: 1, leeway: .milliseconds(350))
        source.setEventHandler { [weak self] in
            Task { @MainActor [weak self] in self?.poll() }
        }
        timer = source
        source.resume()
    }

    func update(preferences: ClipboardPreferences) {
        self.preferences = preferences
        if preferences.enabled {
            start()
        } else {
            stop()
            summaries = []
            normalizedSummaries = []
            onChange?([])
        }
    }

    func stop() {
        timer?.setEventHandler {}
        timer?.cancel()
        timer = nil
        if let activationObserver {
            NSWorkspace.shared.notificationCenter.removeObserver(activationObserver)
            self.activationObserver = nil
        }
    }

    func filteredSummaries(query: String) -> [ClipboardItemSummary] {
        let normalized = SearchNormalizer.normalize(query)
        guard !normalized.isEmpty else { return summaries }
        return normalizedSummaries.lazy
            .filter { $0.preview.contains(normalized) }
            .map(\.summary)
    }

    func restore(id: String, completion: @escaping (Bool) -> Void) {
        Task {
            do {
                guard let payload = try await store.payload(id: id) else {
                    completion(false)
                    return
                }
                let pasteboard = NSPasteboard.general
                let succeeded = ClipboardPasteboardWriter.write(payload, to: pasteboard)
                if succeeded {
                    suppressedChangeCount = pasteboard.changeCount
                    lastChangeCount = pasteboard.changeCount
                }
                completion(succeeded)
            } catch {
                try? await store.delete(id: id)
                reloadSummaries()
                completion(false)
            }
        }
    }

    func clear() {
        Task {
            try? await store.clear()
            reloadSummaries()
        }
    }

    private func installActivationObserver() {
        guard activationObserver == nil else { return }
        activationObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            let bundleIdentifier = (notification.userInfo?[NSWorkspace.applicationUserInfoKey]
                as? NSRunningApplication)?.bundleIdentifier
            Task { @MainActor [weak self, bundleIdentifier] in
                guard let self else { return }
                // A copy commonly happens immediately before the source app loses focus. Poll
                // once using that previous app so password-manager exclusions stay accurate.
                self.poll(sourceBundleIdentifier: self.activeBundleIdentifier)
                self.activeBundleIdentifier = bundleIdentifier
            }
        }
    }

    private func poll(
        sourceBundleIdentifier: String? = NSWorkspace.shared.frontmostApplication?.bundleIdentifier
    ) {
        guard preferences.enabled else { return }
        let pasteboard = NSPasteboard.general
        let changeCount = pasteboard.changeCount
        guard changeCount != lastChangeCount else { return }
        lastChangeCount = changeCount
        if suppressedChangeCount == changeCount {
            suppressedChangeCount = nil
            return
        }

        if ClipboardCaptureBuilder.shouldIgnoreSource(
            sourceBundleIdentifier,
            preferences: preferences,
            broccoliBundleIdentifier: Bundle.main.bundleIdentifier
        ) {
            return
        }
        guard !ClipboardCaptureBuilder.containsSensitiveMarker(pasteboard),
              let captured = ClipboardCaptureBuilder.capture(
                pasteboard,
                preferences: preferences
              ) else { return }

        Task {
            do {
                _ = try await store.save(
                    payload: captured.payload,
                    kind: captured.kind,
                    preview: captured.preview,
                    sourceBundleIdentifier: sourceBundleIdentifier,
                    retentionDays: preferences.retentionDays,
                    maximumItems: preferences.maximumItems
                )
                reloadSummaries()
            } catch {
                // Clipboard contents never enter diagnostics. A failed item is simply skipped.
            }
        }
    }

    private func reloadSummaries() {
        let limit = preferences.maximumItems
        Task {
            let loaded = (try? await store.loadSummaries(maximumItems: limit)) ?? []
            summaries = loaded
            normalizedSummaries = loaded.map { ($0, SearchNormalizer.normalize($0.preview)) }
            onChange?(loaded)
        }
    }

}

enum ClipboardPasteboardWriter {
    static func write(_ payload: ClipboardPayload, to pasteboard: NSPasteboard) -> Bool {
        let items: [NSPasteboardItem] = payload.items.compactMap { payloadItem in
            let item = NSPasteboardItem()
            var wroteRepresentation = false
            for representation in payloadItem.representations {
                let type = NSPasteboard.PasteboardType(representation.type)
                wroteRepresentation = item.setData(representation.data, forType: type)
                    || wroteRepresentation
            }
            return wroteRepresentation ? item : nil
        }
        guard !items.isEmpty else { return false }
        pasteboard.clearContents()
        return pasteboard.writeObjects(items)
    }
}

struct CapturedClipboardItem: Equatable, Sendable {
    let payload: ClipboardPayload
    let kind: ClipboardContentKind
    let preview: String
}

enum ClipboardCaptureBuilder {
    static let imageTypes: Set<NSPasteboard.PasteboardType> = [
        .png,
        .tiff,
        .init("public.jpeg"),
        .init("public.heic"),
    ]

    static func capture(
        _ pasteboard: NSPasteboard,
        preferences: ClipboardPreferences
    ) -> CapturedClipboardItem? {
        guard let pasteboardItems = pasteboard.pasteboardItems, !pasteboardItems.isEmpty else { return nil }
        let maximumBytes = preferences.maximumItemBytes
        var totalBytes = 0
        var items: [ClipboardPayloadItem] = []
        var detectedKind: ClipboardContentKind = .text
        var preview = ""

        for pasteboardItem in pasteboardItems {
            var representations: [ClipboardRepresentation] = []
            for type in pasteboardItem.types where isAllowed(type, preferences: preferences) {
                guard let data = pasteboardItem.data(forType: type) else { continue }
                totalBytes += data.count
                guard totalBytes <= maximumBytes else { return nil }
                representations.append(.init(type: type.rawValue, data: data))
                if imageTypes.contains(type) { detectedKind = .image }
                if type == .fileURL, detectedKind != .image { detectedKind = .files }
                if type == .URL, detectedKind == .text { detectedKind = .url }
            }
            if !representations.isEmpty { items.append(.init(representations: representations)) }
        }
        guard !items.isEmpty else { return nil }

        if let string = pasteboard.string(forType: .string), !string.isEmpty {
            preview = singleLine(string)
        } else if let value = pasteboard.string(forType: .URL) {
            preview = singleLine(value)
        } else if let value = pasteboard.string(forType: .fileURL),
                  let url = URL(string: value) {
            preview = url.lastPathComponent
        } else if detectedKind == .image {
            preview = "Image"
        } else {
            preview = "Clipboard item"
        }
        return CapturedClipboardItem(
            payload: ClipboardPayload(items: items),
            kind: detectedKind,
            preview: String(preview.prefix(500))
        )
    }

    static func isAllowed(
        _ type: NSPasteboard.PasteboardType,
        preferences: ClipboardPreferences
    ) -> Bool {
        if type == .string || type == .rtf || type == .rtfd { return preferences.capturesText }
        if type == .URL { return preferences.capturesURLs }
        if type == .fileURL { return preferences.capturesFiles }
        return imageTypes.contains(type) && preferences.capturesImages
    }

    static func containsSensitiveMarker(_ pasteboard: NSPasteboard) -> Bool {
        let blockedFragments = ["concealed", "transient", "autogenerated", "password"]
        return pasteboard.types?.contains { type in
            let lowered = type.rawValue.lowercased()
            return blockedFragments.contains { lowered.contains($0) }
        } ?? false
    }

    static func shouldIgnoreSource(
        _ bundleIdentifier: String?,
        preferences: ClipboardPreferences,
        broccoliBundleIdentifier: String? = "dev.gauravpandey.broccoli"
    ) -> Bool {
        guard let bundleIdentifier else { return false }
        return bundleIdentifier == broccoliBundleIdentifier
            || preferences.ignoredBundleIdentifiers.contains(bundleIdentifier)
            || ClipboardPreferences.defaultIgnoredBundleIdentifiers.contains(bundleIdentifier)
    }

    private static func singleLine(_ value: String) -> String {
        value.components(separatedBy: .whitespacesAndNewlines)
            .filter { !$0.isEmpty }
            .joined(separator: " ")
    }
}
