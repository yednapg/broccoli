import Foundation

/// The result of applying an incremental set of application discoveries and removals.
///
/// Paths are compared in standardized form, so logically equivalent paths identify the
/// same application. Every result collection is sorted deterministically and can be
/// published or persisted directly.
public struct ApplicationCatalogDelta: Equatable, Sendable {
    public let snapshot: [CachedApplication]
    public let added: [CachedApplication]
    public let changed: [CachedApplication]
    public let removed: [CachedApplication]

    public var hasChanges: Bool {
        !added.isEmpty || !changed.isEmpty || !removed.isEmpty
    }

    /// Applies path removals followed by application upserts to an existing catalog.
    ///
    /// When the same standardized path occurs more than once, the last application wins.
    /// An upsert wins when its path is also present in `removingPaths`.
    public static func applying(
        upserts: [CachedApplication] = [],
        removingPaths: Set<String> = [],
        to current: [CachedApplication]
    ) -> ApplicationCatalogDelta {
        let previousByPath = applicationsByStandardizedPath(current)
        var nextByPath = previousByPath

        for path in removingPaths {
            nextByPath.removeValue(forKey: standardizedPath(path))
        }
        for application in upserts {
            nextByPath[standardizedPath(application.path)] = application
        }

        var added: [CachedApplication] = []
        var changed: [CachedApplication] = []
        for (path, application) in nextByPath {
            guard let previous = previousByPath[path] else {
                added.append(application)
                continue
            }
            if previous != application {
                changed.append(application)
            }
        }

        let removed = previousByPath.compactMap { path, application in
            nextByPath[path] == nil ? application : nil
        }

        return ApplicationCatalogDelta(
            snapshot: sorted(Array(nextByPath.values)),
            added: sorted(added),
            changed: sorted(changed),
            removed: sorted(removed)
        )
    }

    /// Returns the catalog paths that are located on a particular mounted volume.
    ///
    /// Containment is component-based rather than string-prefix-based. For example,
    /// `/Volumes/Work 2/App.app` is not treated as a child of `/Volumes/Work`.
    public static func paths(
        in applications: [CachedApplication],
        containedInVolumeAt volumeURL: URL
    ) -> Set<String> {
        Set(applications.lazy.map(\.path).filter {
            isPath($0, containedInVolumeAt: volumeURL)
        })
    }

    public static func isPath(_ path: String, containedInVolumeAt volumeURL: URL) -> Bool {
        guard path.hasPrefix("/"), volumeURL.isFileURL else { return false }

        let candidateComponents = URL(fileURLWithPath: path)
            .standardizedFileURL
            .pathComponents
        let volumeComponents = volumeURL.standardizedFileURL.pathComponents

        guard candidateComponents.count >= volumeComponents.count else { return false }
        return zip(volumeComponents, candidateComponents).allSatisfy { pair in
            pair.0 == pair.1
        }
    }

    private init(
        snapshot: [CachedApplication],
        added: [CachedApplication],
        changed: [CachedApplication],
        removed: [CachedApplication]
    ) {
        self.snapshot = snapshot
        self.added = added
        self.changed = changed
        self.removed = removed
    }

    private static func applicationsByStandardizedPath(
        _ applications: [CachedApplication]
    ) -> [String: CachedApplication] {
        var result: [String: CachedApplication] = [:]
        result.reserveCapacity(applications.count)
        for application in applications {
            result[standardizedPath(application.path)] = application
        }
        return result
    }

    private static func standardizedPath(_ path: String) -> String {
        URL(fileURLWithPath: path).standardizedFileURL.path
    }

    private static func sorted(_ applications: [CachedApplication]) -> [CachedApplication] {
        applications.sorted(by: isOrderedBefore)
    }

    private static func isOrderedBefore(
        _ lhs: CachedApplication,
        _ rhs: CachedApplication
    ) -> Bool {
        let nameOrder = lhs.displayName.compare(
            rhs.displayName,
            options: [.caseInsensitive, .diacriticInsensitive, .widthInsensitive, .numeric],
            range: nil,
            locale: Locale(identifier: "en_US_POSIX")
        )
        if nameOrder != .orderedSame {
            return nameOrder == .orderedAscending
        }
        if lhs.displayName != rhs.displayName {
            return lhs.displayName < rhs.displayName
        }
        return standardizedPath(lhs.path) < standardizedPath(rhs.path)
    }
}
