import Foundation

public struct SystemSettingsSearchTerm: Equatable, Sendable {
    public let id: String
    public let destination: String
    public let title: String
    public let keywords: [String]

    public init(id: String, destination: String, title: String, keywords: [String]) {
        self.id = id
        self.destination = destination
        self.title = title
        self.keywords = keywords
    }
}

public struct SystemSettingsPane: Equatable, Sendable {
    public let bundleIdentifier: String
    public let title: String
    public let route: String
    public let searchTerms: [SystemSettingsSearchTerm]

    public init(
        bundleIdentifier: String,
        title: String,
        route: String,
        searchTerms: [SystemSettingsSearchTerm] = []
    ) {
        self.bundleIdentifier = bundleIdentifier
        self.title = title
        self.route = route
        self.searchTerms = searchTerms
    }
}

public enum SettingsCatalog {
    public static func searchEntries(from panes: [SystemSettingsPane]) -> [SearchEntry] {
        var uniquePanes: [String: SystemSettingsPane] = [:]
        for pane in panes where uniquePanes[pane.bundleIdentifier] == nil {
            uniquePanes[pane.bundleIdentifier] = pane
        }
        return uniquePanes.values
            .sorted(by: paneOrder)
            .flatMap(entries)
    }

    private static func entries(for pane: SystemSettingsPane) -> [SearchEntry] {
        let iconKey = "setting:\(pane.bundleIdentifier)"
        let normalizedPaneTitle = SearchNormalizer.normalize(pane.title)
        let parentKeywords = pane.searchTerms
            .filter { SearchNormalizer.normalize($0.title) == normalizedPaneTitle }
            .flatMap(\.keywords)
        let parent = SearchEntry(
            id: iconKey,
            kind: .systemSetting,
            title: pane.title,
            subtitle: "System Settings → \(pane.title)",
            keywords: parentKeywords,
            iconKey: iconKey,
            target: .setting(route: pane.route)
        )
        var seen = Set<String>()
        let children = pane.searchTerms.compactMap { term -> SearchEntry? in
            let normalizedTitle = SearchNormalizer.normalize(term.title)
            guard !normalizedTitle.isEmpty,
                  normalizedTitle != normalizedPaneTitle,
                  seen.insert(term.id).inserted else { return nil }
            return SearchEntry(
                id: "\(iconKey):\(term.id)",
                kind: .systemSetting,
                title: term.title,
                subtitle: "System Settings → \(pane.title)",
                keywords: [pane.title] + term.keywords,
                iconKey: iconKey,
                target: .setting(route: nestedRoute(pane.route, destination: term.destination))
            )
        }
        return [parent] + children
    }

    private static func nestedRoute(_ route: String, destination: String) -> String {
        guard !destination.isEmpty,
              let encoded = destination.addingPercentEncoding(
                withAllowedCharacters: .alphanumerics.union(CharacterSet(charactersIn: "-._~"))
              ) else { return route }
        return "\(route)?\(encoded)"
    }

    private static func paneOrder(_ lhs: SystemSettingsPane, _ rhs: SystemSettingsPane) -> Bool {
        let titleOrder = lhs.title.localizedStandardCompare(rhs.title)
        if titleOrder != .orderedSame { return titleOrder == .orderedAscending }
        return lhs.bundleIdentifier < rhs.bundleIdentifier
    }
}
