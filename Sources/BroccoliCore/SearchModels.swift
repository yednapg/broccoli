import Foundation

public enum SearchKind: String, Codable, CaseIterable, Sendable {
    case application
    case systemSetting
    case action
    case file
    case calculator
    case clipboard
    case status
}

public enum ExecutableTarget: Codable, Hashable, Sendable {
    case application(path: String, bundleIdentifier: String?)
    case setting(route: String?)
    case action(id: String)
    case file(path: String, isDirectory: Bool)
    case calculator(result: String)
    case clipboardCommand
    case clipboardItem(id: String)
    case none
}

public struct SearchEntry: Codable, Hashable, Identifiable, Sendable {
    public let id: String
    public let kind: SearchKind
    public let title: String
    public let subtitle: String
    public let normalizedTitle: String
    public let compactTitle: String
    public let tokens: [String]
    public let acronym: String
    public let keywords: [String]
    public let compactKeywords: [String]
    public let iconKey: String
    public let target: ExecutableTarget
    public var isRunning: Bool

    public init(
        id: String,
        kind: SearchKind,
        title: String,
        subtitle: String = "",
        keywords: [String] = [],
        iconKey: String = "",
        target: ExecutableTarget,
        isRunning: Bool = false
    ) {
        self.id = id
        self.kind = kind
        self.title = title
        self.subtitle = subtitle
        self.normalizedTitle = SearchNormalizer.normalize(title)
        self.compactTitle = SearchNormalizer.compact(title)
        self.tokens = SearchNormalizer.tokens(title)
        self.acronym = SearchNormalizer.acronym(title)
        self.keywords = keywords.map(SearchNormalizer.normalize)
        self.compactKeywords = keywords.map(SearchNormalizer.compact)
        self.iconKey = iconKey
        self.target = target
        self.isRunning = isRunning
    }
}

public struct SearchSnapshot: Sendable {
    public let entries: [SearchEntry]
    public let entriesByID: [String: SearchEntry]
    public let indexByID: [String: Int]
    public let highPrefixIndex: [String: [Int]]
    public let titleTrigramIndex: [String: [Int]]
    public let keywordPrefixIndex: [String: [Int]]
    public let keywordTrigramIndex: [String: [Int]]
    public let titleShortPrefixIndex: [String: [Int]]
    public let runningIndices: [Int]
    public let localizedSortRanks: [Int]

    public init(entries: [SearchEntry]) {
        self.entries = entries
        self.entriesByID = Dictionary(uniqueKeysWithValues: entries.map { ($0.id, $0) })
        self.indexByID = Dictionary(uniqueKeysWithValues: entries.enumerated().map { ($0.element.id, $0.offset) })
        var highPrefixes: [String: [Int]] = [:]
        var titleTrigrams: [String: [Int]] = [:]
        var keywordPrefixes: [String: [Int]] = [:]
        var keywordTrigrams: [String: [Int]] = [:]
        var titlePrefixes: [String: [Int]] = [:]
        var running: [Int] = []
        let localizedOrder = entries.indices.sorted { lhs, rhs in
            let order = entries[lhs].title.localizedStandardCompare(entries[rhs].title)
            if order != .orderedSame { return order == .orderedAscending }
            return entries[lhs].id < entries[rhs].id
        }
        var localizedSortRanks = Array(repeating: 0, count: entries.count)
        for (rank, index) in localizedOrder.enumerated() {
            localizedSortRanks[index] = rank
        }
        for (index, entry) in entries.enumerated() {
            if entry.isRunning { running.append(index) }
            let entryTitleTrigrams = Self.trigrams(in: entry.normalizedTitle)
                .union(Self.trigrams(in: entry.compactTitle))
            for trigram in entryTitleTrigrams { titleTrigrams[trigram, default: []].append(index) }

            var entryHighPrefixes: Set<String> = []
            for value in [entry.normalizedTitle, entry.compactTitle, entry.acronym] + entry.tokens {
                entryHighPrefixes.formUnion(Self.prefixes(of: value))
            }
            for prefix in entryHighPrefixes { highPrefixes[prefix, default: []].append(index) }

            var entryKeywordPrefixes: Set<String> = []
            var entryKeywordTrigrams: Set<String> = []
            for keyword in entry.keywords {
                entryKeywordPrefixes.formUnion(Self.prefixes(of: keyword))
                for token in SearchNormalizer.tokens(keyword) {
                    entryKeywordPrefixes.formUnion(Self.prefixes(of: token))
                }
                entryKeywordTrigrams.formUnion(Self.trigrams(in: keyword))
            }
            for keyword in entry.compactKeywords {
                entryKeywordPrefixes.formUnion(Self.prefixes(of: keyword))
                entryKeywordTrigrams.formUnion(Self.trigrams(in: keyword))
            }
            for prefix in entryKeywordPrefixes { keywordPrefixes[prefix, default: []].append(index) }
            for trigram in entryKeywordTrigrams { keywordTrigrams[trigram, default: []].append(index) }

            if let first = entry.normalizedTitle.first {
                titlePrefixes[String(first), default: []].append(index)
            }
            if entry.normalizedTitle.count >= 2 {
                titlePrefixes[String(entry.normalizedTitle.prefix(2)), default: []].append(index)
            }
        }
        for key in titlePrefixes.keys {
            titlePrefixes[key]?.sort { localizedSortRanks[$0] < localizedSortRanks[$1] }
        }
        Self.sortIndexLists(&keywordPrefixes, ranks: localizedSortRanks)
        Self.sortIndexLists(&keywordTrigrams, ranks: localizedSortRanks)
        self.highPrefixIndex = highPrefixes
        self.titleTrigramIndex = titleTrigrams
        self.keywordPrefixIndex = keywordPrefixes
        self.keywordTrigramIndex = keywordTrigrams
        self.titleShortPrefixIndex = titlePrefixes
        self.runningIndices = running
        self.localizedSortRanks = localizedSortRanks
    }

    private static func prefixes(of value: String) -> Set<String> {
        guard !value.isEmpty else { return [] }
        var result: Set<String> = []
        var prefix = ""
        prefix.reserveCapacity(value.utf8.count)
        for character in value {
            prefix.append(character)
            result.insert(prefix)
        }
        return result
    }

    private static func trigrams(in value: String) -> Set<String> {
        let characters = Array(value)
        guard characters.count >= 3 else { return [] }
        var result: Set<String> = []
        for offset in 0...(characters.count - 3) {
            result.insert(String(characters[offset...offset + 2]))
        }
        return result
    }

    private static func sortIndexLists(_ lists: inout [String: [Int]], ranks: [Int]) {
        for key in lists.keys {
            lists[key]?.sort { ranks[$0] < ranks[$1] }
        }
    }

    public static let empty = SearchSnapshot(entries: [])
}

public struct RankedResult: Sendable, Equatable {
    public let entry: SearchEntry
    public let score: Int

    public init(entry: SearchEntry, score: Int) {
        self.entry = entry
        self.score = score
    }
}

public struct UsageRecord: Codable, Equatable, Sendable {
    public var selectionCount: Int
    public var lastUsed: Date

    public init(selectionCount: Int = 1, lastUsed: Date = Date()) {
        self.selectionCount = selectionCount
        self.lastUsed = lastUsed
    }
}

public struct SearchPreferences: Sendable {
    public var applicationsEnabled: Bool
    public var settingsEnabled: Bool
    public var actionsEnabled: Bool
    public var recentItemsEnabled: Bool
    public var adaptiveRankingEnabled: Bool
    public var alwaysIncludedEntryIDs: Set<String>

    public init(
        applicationsEnabled: Bool = true,
        settingsEnabled: Bool = true,
        actionsEnabled: Bool = true,
        recentItemsEnabled: Bool = false,
        adaptiveRankingEnabled: Bool = true,
        alwaysIncludedEntryIDs: Set<String> = []
    ) {
        self.applicationsEnabled = applicationsEnabled
        self.settingsEnabled = settingsEnabled
        self.actionsEnabled = actionsEnabled
        self.recentItemsEnabled = recentItemsEnabled
        self.adaptiveRankingEnabled = adaptiveRankingEnabled
        self.alwaysIncludedEntryIDs = alwaysIncludedEntryIDs
    }

    public func includes(_ entry: SearchEntry) -> Bool {
        alwaysIncludedEntryIDs.contains(entry.id) || includes(entry.kind)
    }

    public func includes(_ kind: SearchKind) -> Bool {
        switch kind {
        case .application: applicationsEnabled
        case .systemSetting: settingsEnabled
        case .action: actionsEnabled
        case .file, .calculator, .clipboard, .status: true
        }
    }
}
