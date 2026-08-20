@preconcurrency import AppKit
@preconcurrency import Foundation
import BroccoliCore

struct FileSearchItem: Equatable, Sendable {
    let path: String
    let title: String
    let subtitle: String
    let isDirectory: Bool
    let modifiedAt: Date?

    var searchEntry: SearchEntry {
        SearchEntry(
            id: "file:\(path)",
            kind: .file,
            title: title,
            subtitle: subtitle,
            keywords: [],
            iconKey: path,
            target: .file(path: path, isDirectory: isDirectory)
        )
    }
}

enum FileSearchOutcome: Sendable {
    case results([FileSearchItem])
    case unavailable
}

enum FileSearchPolicy {
    static func isAllowed(
        path: String,
        homeDirectory: URL = FileManager.default.homeDirectoryForCurrentUser
    ) -> Bool {
        let url = URL(fileURLWithPath: path).standardizedFileURL
        let components = url.pathComponents
        guard !components.contains(where: {
            ($0.hasPrefix(".") && $0 != "." && $0 != "..")
                || $0.lowercased().hasSuffix(".app")
        }) else { return false }

        let home = homeDirectory.standardizedFileURL.path
        if url.path == home || url.path.hasPrefix(home + "/") {
            let library = homeDirectory.appendingPathComponent("Library").standardizedFileURL.path
            return url.path != library && !url.path.hasPrefix(library + "/")
        }

        guard url.path.hasPrefix("/Volumes/") else { return false }
        let relativeComponents = Array(components.dropFirst(3))
        let systemRoots: Set<String> = ["System", "Library", "private", "usr", "bin", "sbin"]
        return relativeComponents.first.map { !systemRoots.contains($0) } ?? false
    }
}

private final class MetadataQueryBox: @unchecked Sendable {
    let value: NSMetadataQuery
    init(_ value: NSMetadataQuery) { self.value = value }
}

@MainActor
final class FileSearchService {
    private let metadataQueue: OperationQueue = {
        let queue = OperationQueue()
        queue.name = "dev.gauravpandey.broccoli.file-metadata"
        queue.qualityOfService = .userInitiated
        queue.maxConcurrentOperationCount = 1
        return queue
    }()
    private var pendingTask: Task<Void, Never>?
    private var activeQuery: NSMetadataQuery?
    private var observers: [NSObjectProtocol] = []
    private var volumeObservers: [NSObjectProtocol] = []
    private var activeGeneration = 0
    private var lastDeliveredPaths: [String] = []
    private var searchScopeGeneration = 0
    private var searchScopeURLs = [FileManager.default.homeDirectoryForCurrentUser]

    init() {
        refreshSearchScopes()
        let center = NSWorkspace.shared.notificationCenter
        for name in [NSWorkspace.didMountNotification, NSWorkspace.didUnmountNotification] {
            volumeObservers.append(center.addObserver(
                forName: name,
                object: nil,
                queue: .main
            ) { [weak self] _ in
                MainActor.assumeIsolated { self?.refreshSearchScopes() }
            })
        }
    }

    isolated deinit {
        pendingTask?.cancel()
        observers.forEach(NotificationCenter.default.removeObserver)
        activeQuery?.stop()
        volumeObservers.forEach(NSWorkspace.shared.notificationCenter.removeObserver)
    }

    func search(
        query rawQuery: String,
        generation: Int,
        limit: Int,
        completion: @escaping @MainActor (Int, FileSearchOutcome) -> Void
    ) {
        cancel()
        activeGeneration = generation
        let query = rawQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else {
            completion(generation, .results([]))
            return
        }

        pendingTask = Task { [weak self] in
            do {
                try await Task.sleep(for: .milliseconds(25))
            } catch {
                return
            }
            guard let self, generation == self.activeGeneration else { return }
            self.startMetadataQuery(
                text: query,
                generation: generation,
                limit: limit,
                completion: completion
            )
        }
    }

    func cancel() {
        activeGeneration &+= 1
        pendingTask?.cancel()
        pendingTask = nil
        observers.forEach(NotificationCenter.default.removeObserver)
        observers.removeAll()
        activeQuery?.stop()
        activeQuery = nil
        lastDeliveredPaths = []
    }

    private func startMetadataQuery(
        text: String,
        generation: Int,
        limit: Int,
        completion: @escaping @MainActor (Int, FileSearchOutcome) -> Void
    ) {
        let query = NSMetadataQuery()
        query.operationQueue = metadataQueue
        query.notificationBatchingInterval = 0.05
        // Scope discovery can touch Disk Arbitration and volume resource properties. Keep a
        // prepared URL-only snapshot so the per-keystroke file-search path never does that
        // synchronous work on the main actor.
        query.searchScopes = searchScopeURLs
        query.predicate = NSCompoundPredicate(orPredicateWithSubpredicates: [
            NSPredicate(format: "%K CONTAINS[cd] %@", NSMetadataItemFSNameKey, text),
            NSPredicate(format: "%K CONTAINS[cd] %@", NSMetadataItemPathKey, text),
        ])
        activeQuery = query
        let queryBox = MetadataQueryBox(query)
        let queryIdentifier = ObjectIdentifier(query)

        let center = NotificationCenter.default
        observers.append(center.addObserver(
            forName: .NSMetadataQueryGatheringProgress,
            object: query,
            queue: metadataQueue
        ) { [weak self, queryBox] _ in
            let query = queryBox.value
            query.disableUpdates()
            let values = query.results
            query.enableUpdates()
            let items = Self.makeItems(from: values, searchText: text, limit: limit)
            guard !items.isEmpty else { return }
            Task { @MainActor [weak self] in
                guard let self,
                      generation == self.activeGeneration,
                      self.activeQuery.map(ObjectIdentifier.init) == queryIdentifier else { return }
                self.deliverIfChanged(items, generation: generation, completion: completion)
            }
        })

        observers.append(center.addObserver(
            forName: .NSMetadataQueryDidFinishGathering,
            object: query,
            queue: metadataQueue
        ) { [weak self, queryBox] _ in
            let query = queryBox.value
            query.disableUpdates()
            let values = query.results
            query.stop()
            let items = Self.makeItems(from: values, searchText: text, limit: limit)
            Task { @MainActor [weak self] in
                guard let self,
                      generation == self.activeGeneration,
                      self.activeQuery.map(ObjectIdentifier.init) == queryIdentifier else { return }
                self.observers.forEach(NotificationCenter.default.removeObserver)
                self.observers.removeAll()
                self.activeQuery = nil
                self.deliverIfChanged(items, generation: generation, completion: completion, force: true)
            }
        })

        guard query.start() else {
            cancel()
            activeGeneration = generation
            completion(generation, .unavailable)
            return
        }
    }

    private func deliverIfChanged(
        _ items: [FileSearchItem],
        generation: Int,
        completion: @escaping @MainActor (Int, FileSearchOutcome) -> Void,
        force: Bool = false
    ) {
        let paths = items.map(\.path)
        guard force || paths != lastDeliveredPaths else { return }
        lastDeliveredPaths = paths
        completion(generation, .results(items))
    }

    private func refreshSearchScopes() {
        searchScopeGeneration &+= 1
        let generation = searchScopeGeneration
        let home = FileManager.default.homeDirectoryForCurrentUser
        Task { [weak self] in
            let scopes = await Task.detached(priority: .utility) {
                Self.discoverSearchScopes(home: home)
            }.value
            guard let self, generation == self.searchScopeGeneration else { return }
            self.searchScopeURLs = scopes
        }
    }

    nonisolated private static func discoverSearchScopes(home: URL) -> [URL] {
        var scopes = [home]
        let keys: [URLResourceKey] = [.volumeIsBrowsableKey, .volumeIsRemovableKey]
        let volumes = FileManager.default.mountedVolumeURLs(
            includingResourceValuesForKeys: keys,
            options: [.skipHiddenVolumes]
        ) ?? []
        for volume in volumes {
            guard volume.path.hasPrefix("/Volumes/") else { continue }
            let values = try? volume.resourceValues(forKeys: Set(keys))
            guard values?.volumeIsBrowsable != false else { continue }
            scopes.append(volume)
        }
        return scopes
    }

    nonisolated private static func makeItems(
        from values: [Any],
        searchText: String,
        limit: Int
    ) -> [FileSearchItem] {
        var seen: Set<String> = []
        var ranked: [(item: FileSearchItem, score: Int)] = []
        ranked.reserveCapacity(min(values.count, 200))

        for value in values {
            guard let metadata = value as? NSMetadataItem,
                  let rawPath = metadata.value(forAttribute: NSMetadataItemPathKey) as? String else {
                continue
            }
            let path = URL(fileURLWithPath: rawPath).standardizedFileURL.path
            guard seen.insert(path).inserted, FileSearchPolicy.isAllowed(path: path) else { continue }
            let url = URL(fileURLWithPath: path)
            let resourceValues = try? url.resourceValues(forKeys: [.isDirectoryKey, .isReadableKey])
            guard resourceValues?.isReadable != false else { continue }
            let title = (metadata.value(forAttribute: NSMetadataItemDisplayNameKey) as? String)
                ?? url.lastPathComponent
            guard !title.isEmpty else { continue }
            let modifiedAt = metadata.value(forAttribute: NSMetadataItemFSContentChangeDateKey) as? Date
            let item = FileSearchItem(
                path: path,
                title: title,
                subtitle: url.deletingLastPathComponent().path,
                isDirectory: resourceValues?.isDirectory == true,
                modifiedAt: modifiedAt
            )
            ranked.append((item, score(item: item, query: searchText)))
        }

        ranked.sort { lhs, rhs in
            if lhs.score != rhs.score { return lhs.score > rhs.score }
            if lhs.item.modifiedAt != rhs.item.modifiedAt {
                return (lhs.item.modifiedAt ?? .distantPast) > (rhs.item.modifiedAt ?? .distantPast)
            }
            let order = lhs.item.title.localizedStandardCompare(rhs.item.title)
            if order != .orderedSame { return order == .orderedAscending }
            return lhs.item.path < rhs.item.path
        }
        return Array(ranked.prefix(max(1, limit)).map(\.item))
    }

    nonisolated private static func score(item: FileSearchItem, query: String) -> Int {
        let normalizedQuery = SearchNormalizer.normalize(query)
        let normalizedTitle = SearchNormalizer.normalize(item.title)
        let normalizedPath = SearchNormalizer.normalize(item.path)
        if normalizedTitle == normalizedQuery { return 1_000 }
        if normalizedTitle.hasPrefix(normalizedQuery) { return 800 }
        if SearchNormalizer.tokens(item.title).contains(where: { $0.hasPrefix(normalizedQuery) }) {
            return 650
        }
        if SearchNormalizer.acronym(item.title).hasPrefix(normalizedQuery) { return 600 }
        if normalizedTitle.contains(normalizedQuery) { return 450 }
        if normalizedPath.contains(normalizedQuery) { return 250 }
        return 0
    }
}
