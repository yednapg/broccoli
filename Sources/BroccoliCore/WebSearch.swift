import Foundation

/// Which web search, if any, is offered when a query cannot be answered on this Mac.
public enum WebSearchEngine: String, Codable, CaseIterable, Identifiable, Sendable {
    case off
    case google
    case duckDuckGo

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .off: "Off"
        case .google: "Google"
        case .duckDuckGo: "DuckDuckGo"
        }
    }
}

/// Builds the explicit web-search fallback offered when nothing on this Mac matches.
/// The query leaves the Mac only if the user chooses this result; the entry identifier is
/// fixed so the query never reaches learned usage or recent selections.
public enum WebSearch {
    public static let googleEntryID = "web:google"
    public static let googleIconKey = "web:google"
    public static let duckDuckGoEntryID = "web:duckduckgo"
    public static let duckDuckGoIconKey = "web:duckduckgo"

    /// A bare number is the start of a calculation. Offering a web search before the next
    /// character arrives gets in the way of typing `3+1`.
    public static func isCalculationInProgress(_ query: String) -> Bool {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return false }
        return trimmed.range(
            of: #"^[0-9]+([.,][0-9]*)?$|^[.,][0-9]+$"#,
            options: .regularExpression
        ) != nil
    }

    public static func entry(for query: String, engine: WebSearchEngine) -> SearchEntry? {
        guard let service = Service(engine: engine), let url = url(for: query, service: service) else {
            return nil
        }
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        return SearchEntry(
            id: service.entryID,
            kind: .webSearch,
            title: "Search \(service.name) for “\(trimmed)”",
            subtitle: "Open in your web browser",
            iconKey: service.iconKey,
            target: .webSearch(url: url)
        )
    }

    public static func googleEntry(for query: String) -> SearchEntry? {
        entry(for: query, engine: .google)
    }

    public static func googleURL(for query: String) -> URL? {
        url(for: query, service: .google)
    }

    private struct Service {
        let name: String
        let host: String
        let path: String
        let entryID: String
        let iconKey: String

        static let google = Service(
            name: "Google", host: "www.google.com", path: "/search",
            entryID: WebSearch.googleEntryID, iconKey: WebSearch.googleIconKey
        )
        static let duckDuckGo = Service(
            name: "DuckDuckGo", host: "duckduckgo.com", path: "/",
            entryID: WebSearch.duckDuckGoEntryID, iconKey: WebSearch.duckDuckGoIconKey
        )

        private init(name: String, host: String, path: String, entryID: String, iconKey: String) {
            self.name = name
            self.host = host
            self.path = path
            self.entryID = entryID
            self.iconKey = iconKey
        }

        init?(engine: WebSearchEngine) {
            switch engine {
            case .off: return nil
            case .google: self = .google
            case .duckDuckGo: self = .duckDuckGo
            }
        }
    }

    private static func url(for query: String, service: Service) -> URL? {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        // Form decoding treats a literal `+` as a space, so `c++` must arrive as `c%2B%2B`.
        var allowed = CharacterSet.urlQueryAllowed
        allowed.remove(charactersIn: "+&=")
        guard !trimmed.isEmpty,
              let encoded = trimmed.addingPercentEncoding(withAllowedCharacters: allowed)
        else { return nil }
        var components = URLComponents()
        components.scheme = "https"
        components.host = service.host
        components.path = service.path
        components.percentEncodedQueryItems = [URLQueryItem(name: "q", value: encoded)]
        return components.url
    }
}
