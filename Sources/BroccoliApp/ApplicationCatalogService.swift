@preconcurrency import AppKit
import BroccoliCore
@preconcurrency import Foundation
import UniformTypeIdentifiers

@MainActor
final class ApplicationCatalogService: NSObject {
    private struct InspectedApplication: Sendable {
        let requestedPath: String
        let application: CachedApplication?
    }

    private let store: CatalogStore
    private let metadataQuery = NSMetadataQuery()
    private let metadataOperationQueue: OperationQueue = {
        let queue = OperationQueue()
        queue.name = "dev.gauravpandey.broccoli.metadata"
        queue.qualityOfService = .utility
        queue.maxConcurrentOperationCount = 1
        return queue
    }()

    private var applicationsByPath: [String: CachedApplication] = [:]
    private var standardPaths: Set<String> = []
    private var metadataPaths: Set<String> = []
    private var observers: [NSObjectProtocol] = []

    private var isStarted = false
    private var metadataObserversInstalled = false
    private var hasCompletedStandardScan = false
    private var hasConsumedInitialMetadataResults = false

    private var nextGeneration: UInt64 = 0
    private var standardScanGeneration: UInt64 = 0
    private var metadataRevisions: [String: UInt64] = [:]

    private var standardScanTask: Task<Void, Never>?
    private var pendingMetadataInspections: [String: UInt64] = [:]
    private var metadataInspectionTask: Task<Void, Never>?
    private var pendingPersistSnapshot: [CachedApplication]?
    private var persistenceTask: Task<Void, Never>?
    private var lastPublishedSnapshot: [CachedApplication] = []

    var onCatalogChanged: (([CachedApplication]) -> Void)?

    init(store: CatalogStore) {
        self.store = store
        super.init()
    }

    func start() {
        guard !isStarted else { return }
        isStarted = true

        Task { [weak self, store] in
            let cached = await store.load()
            guard !Task.isCancelled, let self else { return }
            // The cache is the cold-start path. Publish it before beginning filesystem or
            // Spotlight discovery so a returning installation is searchable immediately.
            self.applyCachedApplications(cached)
            self.scanStandardLocations()
            self.startMetadataQuery()
            self.observeVolumes()
        }
    }

    /// A manual refresh deliberately rescans the standard application folders. The live
    /// metadata query remains running; stopping it would cause a second full Spotlight gather.
    func refresh() {
        scanStandardLocations()
    }

    private func applyCachedApplications(_ applications: [CachedApplication]) {
        let applicable = applications.filter { application in
            if ApplicationDiscoveryPolicy.isUserFacingLocation(application.path) {
                return !hasCompletedStandardScan
                    || standardPaths.contains(application.path)
                    || metadataPaths.contains(application.path)
            }
            return !hasConsumedInitialMetadataResults
                || metadataPaths.contains(application.path)
        }
        _ = mergeApplications(applicable)
        publishIfChanged(persist: false)
    }

    private func scanStandardLocations() {
        standardScanTask?.cancel()
        let generation = makeGeneration()
        standardScanGeneration = generation
        let roots = Self.standardApplicationRoots

        standardScanTask = Task.detached(priority: .utility) { [weak self] in
            let applications = Self.scan(roots: roots)
            guard !Task.isCancelled else { return }
            await self?.applyStandardScan(applications, generation: generation)
        }
    }

    private func applyStandardScan(_ applications: [CachedApplication], generation: UInt64) {
        guard generation == standardScanGeneration else { return }
        standardScanTask = nil
        hasCompletedStandardScan = true

        let discoveredPaths = Set(applications.map(\.path))
        standardPaths = discoveredPaths

        for path in applicationsByPath.keys where
            ApplicationDiscoveryPolicy.isUserFacingLocation(path)
                && !discoveredPaths.contains(path)
                && !metadataPaths.contains(path) {
            applicationsByPath.removeValue(forKey: path)
        }
        _ = mergeApplications(applications)
        publishIfChanged(persist: true)
    }

    private func startMetadataQuery() {
        metadataQuery.searchScopes = [NSMetadataQueryLocalComputerScope]
        metadataQuery.predicate = NSPredicate(
            format: "%K == %@",
            NSMetadataItemContentTypeKey,
            UTType.applicationBundle.identifier
        )
        metadataQuery.operationQueue = metadataOperationQueue

        if !metadataObserversInstalled {
            installMetadataObservers()
            metadataObserversInstalled = true
        }
        metadataQuery.start()
    }

    private func installMetadataObservers() {
        let center = NotificationCenter.default
        observers.append(center.addObserver(
            forName: .NSMetadataQueryDidFinishGathering,
            object: metadataQuery,
            queue: metadataOperationQueue
        ) { [weak self] notification in
            guard let query = notification.object as? NSMetadataQuery else { return }
            query.disableUpdates()
            let paths = Self.metadataPaths(from: query.results)
            query.enableUpdates()
            Task { @MainActor [weak self] in
                self?.consumeInitialMetadataPaths(paths)
            }
        })

        observers.append(center.addObserver(
            forName: .NSMetadataQueryDidUpdate,
            object: metadataQuery,
            queue: metadataOperationQueue
        ) { [weak self] notification in
            let added = Self.metadataPaths(
                from: notification.userInfo?[NSMetadataQueryUpdateAddedItemsKey]
            )
            let changed = Self.metadataPaths(
                from: notification.userInfo?[NSMetadataQueryUpdateChangedItemsKey]
            )
            let removed = Self.metadataPaths(
                from: notification.userInfo?[NSMetadataQueryUpdateRemovedItemsKey]
            )
            guard !added.isEmpty || !changed.isEmpty || !removed.isEmpty else { return }
            Task { @MainActor [weak self] in
                self?.consumeMetadataDelta(added: added, changed: changed, removed: removed)
            }
        })
    }

    /// The initial gather is the one allowed full-result pass. All subsequent updates use
    /// the inserted/changed/removed arrays attached to the update notification.
    private func consumeInitialMetadataPaths(_ paths: [String]) {
        guard !hasConsumedInitialMetadataResults else { return }
        hasConsumedInitialMetadataResults = true

        let gatheredPaths = Set(paths)
        metadataPaths = gatheredPaths

        var revisions: [String: UInt64] = [:]
        for path in gatheredPaths {
            revisions[path] = bumpMetadataRevision(for: path)
        }

        for path in applicationsByPath.keys where
            !ApplicationDiscoveryPolicy.isUserFacingLocation(path)
                && !gatheredPaths.contains(path) {
            applicationsByPath.removeValue(forKey: path)
        }
        publishIfChanged(persist: true)
        queueMetadataInspections(revisions)
    }

    private func consumeMetadataDelta(added: [String], changed: [String], removed: [String]) {
        let upsertPaths = Set(added).union(changed)
        let removedPaths = Set(removed).subtracting(upsertPaths)
        let affectedPaths = upsertPaths.union(removedPaths)
        guard !affectedPaths.isEmpty else { return }

        var revisions: [String: UInt64] = [:]
        for path in affectedPaths {
            revisions[path] = bumpMetadataRevision(for: path)
        }

        metadataPaths.formUnion(upsertPaths)
        metadataPaths.subtract(removedPaths)
        for path in removedPaths {
            pendingMetadataInspections.removeValue(forKey: path)
        }

        for path in removedPaths where
            !standardPaths.contains(path) {
            applicationsByPath.removeValue(forKey: path)
        }
        let upsertRevisions = revisions.filter { upsertPaths.contains($0.key) }
        if upsertRevisions.isEmpty {
            publishIfChanged(persist: true)
        } else {
            queueMetadataInspections(upsertRevisions)
        }
    }

    /// Coalesce bursts of live metadata notifications before opening bundles. Each path keeps
    /// only its newest revision, and revisions are checked again when background work returns.
    private func queueMetadataInspections(_ revisions: [String: UInt64]) {
        guard !revisions.isEmpty else { return }
        pendingMetadataInspections.merge(revisions) { _, newest in newest }
        guard metadataInspectionTask == nil else { return }

        metadataInspectionTask = Task { [weak self] in
            do {
                try await Task.sleep(for: .milliseconds(150))
            } catch {
                return
            }
            guard let self else { return }
            let batch = self.pendingMetadataInspections
            self.pendingMetadataInspections.removeAll(keepingCapacity: true)

            let inspections = await Task.detached(priority: .utility) {
                batch.keys.map { path in
                    InspectedApplication(
                        requestedPath: path,
                        application: Self.application(atPath: path)
                    )
                }
            }.value

            self.applyMetadataInspections(inspections, revisions: batch)
            self.metadataInspectionTask = nil
            if !self.pendingMetadataInspections.isEmpty {
                self.queueMetadataInspections(self.pendingMetadataInspections)
            }
        }
    }

    private func applyMetadataInspections(
        _ inspections: [InspectedApplication],
        revisions: [String: UInt64]
    ) {
        for inspection in inspections {
            let path = inspection.requestedPath
            guard metadataRevisions[path] == revisions[path] else { continue }

            if let application = inspection.application {
                applicationsByPath[path] = application
            } else if !standardPaths.contains(path) {
                applicationsByPath.removeValue(forKey: path)
            }
        }
        publishIfChanged(persist: true)
    }

    private func observeVolumes() {
        let center = NSWorkspace.shared.notificationCenter
        observers.append(center.addObserver(
            forName: NSWorkspace.didMountNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                // NSMetadataQueryLocalComputerScope observes newly mounted local volumes
                // live. This explicit mount observer ensures discovery is running if metadata
                // was temporarily unavailable when the app started.
                guard let self, !self.metadataQuery.isStarted else { return }
                self.startMetadataQuery()
            }
        })
        observers.append(center.addObserver(
            forName: NSWorkspace.didUnmountNotification,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            guard let volumeURL = notification.userInfo?[NSWorkspace.volumeURLUserInfoKey] as? URL
            else { return }
            MainActor.assumeIsolated {
                self?.removeUnmountedVolume(volumeURL)
            }
        })
    }

    private func removeUnmountedVolume(_ volumeURL: URL) {
        let rootPath = volumeURL.standardizedFileURL.path
        guard rootPath != "/" else { return }

        let affectedPaths = ApplicationCatalogDelta.paths(
            in: Array(applicationsByPath.values),
            containedInVolumeAt: volumeURL
        ).union(metadataPaths.filter {
            ApplicationCatalogDelta.isPath($0, containedInVolumeAt: volumeURL)
        })

        for path in affectedPaths {
            _ = bumpMetadataRevision(for: path)
            pendingMetadataInspections.removeValue(forKey: path)
            applicationsByPath.removeValue(forKey: path)
            metadataPaths.remove(path)
            standardPaths.remove(path)
        }
        publishIfChanged(persist: true)
    }

    @discardableResult
    private func mergeApplications(_ applications: [CachedApplication]) -> Bool {
        var changed = false
        for application in applications
            where ApplicationDiscoveryPolicy.isCandidatePath(application.path) {
            if applicationsByPath[application.path] != application {
                applicationsByPath[application.path] = application
                changed = true
            }
        }
        return changed
    }

    private func publishIfChanged(persist: Bool) {
        let currentPaths = Set(applicationsByPath.keys)
        let publishedPaths = Set(lastPublishedSnapshot.map(\.path))
        let delta = ApplicationCatalogDelta.applying(
            upserts: Array(applicationsByPath.values),
            removingPaths: publishedPaths.subtracting(currentPaths),
            to: lastPublishedSnapshot
        )
        guard delta.hasChanges else { return }

        lastPublishedSnapshot = delta.snapshot
        onCatalogChanged?(delta.snapshot)
        if persist {
            enqueuePersistence(delta.snapshot)
        }
    }

    /// Keep at most one store operation in flight. If discovery changes again while the actor
    /// is saving, the next loop persists only the newest pending snapshot.
    private func enqueuePersistence(_ snapshot: [CachedApplication]) {
        pendingPersistSnapshot = snapshot
        guard persistenceTask == nil else { return }

        persistenceTask = Task { [weak self] in
            guard let self else { return }
            try? await Task.sleep(for: .milliseconds(500))
            guard !Task.isCancelled else {
                self.persistenceTask = nil
                return
            }
            while let snapshot = self.pendingPersistSnapshot {
                self.pendingPersistSnapshot = nil
                try? await self.store.save(snapshot)
            }
            self.persistenceTask = nil
        }
    }

    private func makeGeneration() -> UInt64 {
        nextGeneration &+= 1
        return nextGeneration
    }

    private func bumpMetadataRevision(for path: String) -> UInt64 {
        let revision = makeGeneration()
        metadataRevisions[path] = revision
        return revision
    }

    nonisolated private static let standardApplicationRoots: [URL] = {
        let homeApplications = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Applications", isDirectory: true)
        return [
            URL(fileURLWithPath: "/System/Applications", isDirectory: true),
            URL(fileURLWithPath: "/Applications", isDirectory: true),
            homeApplications,
            URL(fileURLWithPath: "/System/Library/CoreServices/Finder.app", isDirectory: true),
        ]
    }()

    nonisolated private static func metadataPaths(from value: Any?) -> [String] {
        guard let values = value as? [Any] else { return [] }
        return metadataPaths(from: values)
    }

    nonisolated private static func metadataPaths(from values: [Any]) -> [String] {
        values.compactMap { value in
            let path: String?
            if let item = value as? NSMetadataItem {
                path = item.value(forAttribute: NSMetadataItemPathKey) as? String
            } else if let url = value as? URL {
                path = url.path
            } else {
                path = value as? String
            }
            guard let path else { return nil }
            let standardizedPath = URL(fileURLWithPath: path).standardizedFileURL.path
            guard ApplicationDiscoveryPolicy.isCandidatePath(standardizedPath) else {
                return nil
            }
            return standardizedPath
        }
    }

    nonisolated private static func scan(roots: [URL]) -> [CachedApplication] {
        let fileManager = FileManager.default
        let keys: [URLResourceKey] = [.isApplicationKey, .isDirectoryKey, .contentModificationDateKey]
        var applications: [CachedApplication] = []
        for root in roots where fileManager.fileExists(atPath: root.path) {
            if Task<Never, Never>.isCancelled { break }
            if root.pathExtension.lowercased() == "app" {
                if let application = application(atPath: root.path) {
                    applications.append(application)
                }
                continue
            }
            guard let enumerator = fileManager.enumerator(
                at: root,
                includingPropertiesForKeys: keys,
                options: [.skipsHiddenFiles, .skipsPackageDescendants]
            ) else { continue }
            for case let url as URL in enumerator {
                if Task<Never, Never>.isCancelled { return applications }
                guard url.pathExtension.lowercased() == "app" else { continue }
                if let application = application(atPath: url.path) {
                    applications.append(application)
                }
                enumerator.skipDescendants()
            }
        }
        return applications
    }

    nonisolated private static func application(atPath path: String) -> CachedApplication? {
        let url = URL(fileURLWithPath: path).standardizedFileURL
        let infoURL = url.appendingPathComponent("Contents/Info.plist", isDirectory: false)
        guard url.pathExtension.lowercased() == "app",
              ApplicationDiscoveryPolicy.isCandidatePath(url.path),
              let infoData = try? Data(contentsOf: infoURL, options: .uncached),
              let info = try? PropertyListSerialization.propertyList(
                from: infoData,
                options: [],
                format: nil
              ) as? [String: Any],
              ApplicationDiscoveryPolicy.isSupportedApplicationBundle(
                path: url.path,
                packageType: info["CFBundlePackageType"] as? String,
                bundleIdentifier: info["CFBundleIdentifier"] as? String
              ),
              let executableName = info["CFBundleExecutable"] as? String,
              !executableName.isEmpty,
              info["LSBackgroundOnly"] as? Bool != true
        else { return nil }
        if info["LSUIElement"] as? Bool == true,
           !ApplicationDiscoveryPolicy.isUserFacingLocation(url.path) {
            return nil
        }
        let name = (info["CFBundleDisplayName"] as? String)
            ?? (info["CFBundleName"] as? String)
            ?? url.deletingPathExtension().lastPathComponent
        guard !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }
        let modifiedAt = try? url.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate
        return CachedApplication(
            path: url.path,
            bundleIdentifier: info["CFBundleIdentifier"] as? String,
            displayName: name,
            modifiedAt: modifiedAt
        )
    }
}
