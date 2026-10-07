import Foundation

public struct SearchEngine: Sendable {
    private struct Candidate {
        let result: RankedResult
        let localizedSortRank: Int
        /// False when only the entry's hidden keywords matched the query.
        var matchesTitle = true
    }

    private struct Match {
        let score: Int
        let matchesTitle: Bool
    }

    public init() {}

    public func search(
        query: String,
        snapshot: SearchSnapshot,
        usage: [String: UsageRecord],
        preferences: SearchPreferences = SearchPreferences(),
        now: Date = Date(),
        limit: Int = 8
    ) -> [RankedResult] {
        let normalizedQuery = SearchNormalizer.normalize(query)
        let compactQuery = SearchNormalizer.compact(query)
        let queryTokens = SearchNormalizer.tokens(query)
        var best: [Candidate] = []
        best.reserveCapacity(limit)

        if normalizedQuery.isEmpty {
            guard preferences.recentItemsEnabled else { return [] }
            for (index, entry) in snapshot.entries.enumerated()
                where preferences.includes(entry) {
                guard let record = usage[entry.id] else { continue }
                insert(
                    Candidate(
                        result: RankedResult(
                            entry: entry,
                            score: usageBoost(record, now: now, enabled: preferences.adaptiveRankingEnabled)
                        ),
                        localizedSortRank: snapshot.localizedSortRanks[index]
                    ),
                    into: &best,
                    limit: limit
                )
            }
            return Self.groupedByKind(best.map(\.result))
        }

        let candidateIndices: any Sequence<Int>
        if queryTokens.count > 1 {
            let perToken = queryTokens
                .map { candidates(for: $0, snapshot: snapshot) }
                .sorted { $0.count < $1.count }
            guard let first = perToken.first, !first.isEmpty else { return [] }
            var intersection = first
            for candidates in perToken.dropFirst() where !intersection.isEmpty {
                intersection.formIntersection(candidates)
            }
            candidateIndices = intersection
        } else if normalizedQuery.count >= 3 {
            var candidates: Set<Int> = []
            if let high = snapshot.highPrefixIndex[normalizedQuery] {
                candidates.formUnion(high)
            }
            candidates.formUnion(intersectedTrigramCandidates(
                query: normalizedQuery,
                index: snapshot.titleTrigramIndex
            ))
            addFocused(
                snapshot.keywordPrefixIndex[normalizedQuery] ?? [],
                snapshot: snapshot,
                usage: usage,
                to: &candidates,
                limit: limit
            )
            addFocused(
                intersectedTrigramCandidates(query: normalizedQuery, index: snapshot.keywordTrigramIndex),
                snapshot: snapshot,
                usage: usage,
                to: &candidates,
                limit: limit
            )
            candidateIndices = candidates
        } else if let titlePrefixes = snapshot.titleShortPrefixIndex[normalizedQuery],
                  titlePrefixes.count >= limit {
            var focused = Array(titlePrefixes.prefix(limit))
            var seen = Set(focused)
            // The alphabetical window can fill with panes. Applications are a launcher's
            // primary short-query targets, so up to `limit` more of them stay candidates;
            // used and running entries are added below regardless of this bound.
            var addedApplications = 0
            for index in titlePrefixes.dropFirst(limit) {
                guard addedApplications < limit else { break }
                guard snapshot.entries[index].kind == .application,
                      seen.insert(index).inserted else { continue }
                focused.append(index)
                addedApplications += 1
            }
            for id in usage.keys {
                guard let index = snapshot.indexByID[id],
                      Self.hasWordPrefix(snapshot.entries[index], normalizedQuery),
                      seen.insert(index).inserted else { continue }
                focused.append(index)
            }
            for index in snapshot.runningIndices
                where snapshot.entries[index].normalizedTitle.hasPrefix(normalizedQuery)
                    && seen.insert(index).inserted {
                focused.append(index)
            }
            candidateIndices = focused
        } else if let strongPrefixes = snapshot.highPrefixIndex[normalizedQuery],
                  strongPrefixes.count >= limit {
            candidateIndices = strongPrefixes
        } else {
            candidateIndices = snapshot.entries.indices
        }

        // One character says little about which word the user means, so what they actually
        // choose leads: every previously selected match ranks ahead of unselected ones,
        // ordered by how often and how recently it was chosen. Longer queries keep match
        // class ahead of usage.
        let selectionLeads = normalizedQuery.count == 1
        var settings: [Candidate] = []
        for index in candidateIndices {
            let entry = snapshot.entries[index]
            guard preferences.includes(entry) else { continue }
            guard let match = matchScore(
                query: normalizedQuery,
                compactQuery: compactQuery,
                queryTokens: queryTokens,
                entry: entry
            ) else { continue }
            let runningBonus = entry.isRunning ? 20 : 0
            let adaptive = usage[entry.id].map {
                usageBoost($0, now: now, enabled: preferences.adaptiveRankingEnabled)
            } ?? 0
            let selectionPriority = selectionLeads && adaptive > 0
                ? Self.singleCharacterSelectionPriority
                : 0
            let candidate = Candidate(
                result: RankedResult(
                    entry: entry,
                    score: match.score + runningBonus + adaptive + selectionPriority
                ),
                localizedSortRank: snapshot.localizedSortRanks[index],
                matchesTitle: match.matchesTitle
            )
            // Settings panes and their indexed topics match very broad queries. Keep a
            // couple of the best ones so the list stays about the app or action the
            // query names, and so a settings-only query does not become a long index.
            if entry.kind == .systemSetting {
                insert(candidate, into: &settings, limit: Self.maximumSettingsResults)
            } else {
                insert(candidate, into: &best, limit: limit)
            }
        }
        for setting in settings {
            insert(setting, into: &best, limit: limit)
        }
        // Keywords are a fallback for entries whose names do not match. Once an entry of a
        // kind matches by name, that kind's keyword-only matches are unrelated noise, such
        // as the Appearance topic indexed under “wallpaper tint” for the query “wallpaper”.
        let kindsMatchedByTitle = Set(best.lazy.filter(\.matchesTitle).map(\.result.entry.kind))
        let relevant = best.filter {
            $0.matchesTitle || !kindsMatchedByTitle.contains($0.result.entry.kind)
        }
        return Self.groupedByKind(relevant.map(\.result))
    }

    /// Keeps each kind together, in the order of its best result, so the list does not
    /// alternate between actions and settings. Each group keeps its ranked order.
    static func groupedByKind(_ results: [RankedResult]) -> [RankedResult] {
        var kinds: [SearchKind] = []
        var groups: [SearchKind: [RankedResult]] = [:]
        for result in results {
            let kind = result.entry.kind
            if groups[kind] == nil { kinds.append(kind) }
            groups[kind, default: []].append(result)
        }
        return kinds.flatMap { groups[$0] ?? [] }
    }

    private func matchScore(
        query: String,
        compactQuery: String,
        queryTokens: [String],
        entry: SearchEntry
    ) -> Match? {
        func titleMatch(_ score: Int) -> Match { Match(score: score, matchesTitle: true) }
        func keywordMatch(_ score: Int) -> Match { Match(score: score, matchesTitle: false) }
        if entry.normalizedTitle == query { return titleMatch(1_000) }
        if !compactQuery.isEmpty, entry.compactTitle == compactQuery { return titleMatch(1_000) }
        if entry.normalizedTitle.hasPrefix(query) { return titleMatch(800) }
        if !compactQuery.isEmpty, entry.compactTitle.hasPrefix(compactQuery) { return titleMatch(800) }
        // A bare number is much more likely to be the beginning of a calculation than a
        // request for every catalog item containing that digit. Keep genuinely numeric app
        // names (for example, 1Password) searchable through the direct-prefix checks above,
        // but do not surface incidental matches such as the System Settings term “802.1X”.
        if query.allSatisfy(\.isNumber) { return nil }
        if queryTokens.count > 1 {
            let keywordTokens = entry.keywords.flatMap(SearchNormalizer.tokens)
            var score = 400
            var everyTokenInTitle = true
            for token in queryTokens {
                if entry.tokens.contains(token) {
                    score += 150
                } else if entry.tokens.contains(where: { $0.hasPrefix(token) }) {
                    score += 130
                } else if entry.kind != .systemSetting, entry.normalizedTitle.contains(token) {
                    score += 105
                } else if keywordTokens.contains(token) {
                    score += 90
                    everyTokenInTitle = false
                } else if keywordTokens.contains(where: { $0.hasPrefix(token) }) {
                    score += 75
                    everyTokenInTitle = false
                } else if entry.keywords.contains(where: {
                    SearchNormalizer.matchesFromWordStart(token, in: $0)
                }) {
                    score += 60
                    everyTokenInTitle = false
                } else {
                    return nil
                }
            }
            return Match(score: score, matchesTitle: everyTokenInTitle)
        }
        // Applications are a launcher's primary targets and are launched by partial name
        // words constantly, so one of their title tokens beginning with the query counts
        // as strongly as a direct title-prefix match; panes keep the token-prefix score.
        for token in entry.tokens where token.hasPrefix(query) {
            return titleMatch(entry.kind == .application ? 800 : 650)
        }
        if entry.acronym.hasPrefix(query) { return titleMatch(600) }
        // A single character is the start of a word, as in Spotlight. Letters buried inside
        // words (“emoji” for j) and metadata keywords would otherwise flood the list.
        if query.count == 1 { return nil }
        // Application names match inside the word, as Spotlight does for Xcode and “code”.
        // A Settings title does not: the query has to start one of its words.
        if entry.kind != .systemSetting, entry.normalizedTitle.contains(query) { return titleMatch(450) }
        if SearchNormalizer.matchesFromWordStart(compactQuery, in: entry.title) { return titleMatch(450) }
        for keyword in entry.keywords where keyword.hasPrefix(query) { return keywordMatch(350) }
        if !compactQuery.isEmpty,
           entry.compactKeywords.contains(where: { $0.hasPrefix(compactQuery) }) { return keywordMatch(350) }
        if entry.keywords.contains(where: {
            SearchNormalizer.tokens($0).contains { $0.hasPrefix(query) }
        }) { return keywordMatch(250) }
        if entry.keywords.contains(where: { SearchNormalizer.matchesFromWordStart(compactQuery, in: $0) }) {
            return keywordMatch(250)
        }
        return nil
    }

    private func candidates(for term: String, snapshot: SearchSnapshot) -> Set<Int> {
        var result = Set(snapshot.highPrefixIndex[term] ?? [])
        result.formUnion(snapshot.keywordPrefixIndex[term] ?? [])
        if term.count >= 3 {
            result.formUnion(intersectedTrigramCandidates(
                query: term,
                index: snapshot.titleTrigramIndex
            ))
            result.formUnion(intersectedTrigramCandidates(
                query: term,
                index: snapshot.keywordTrigramIndex
            ))
        }
        return result
    }

    private func insert(_ result: Candidate, into best: inout [Candidate], limit: Int) {
        guard limit > 0 else { return }
        if best.count == limit, let last = best.last, !resultOrder(result, last) { return }
        let index = best.firstIndex { resultOrder(result, $0) } ?? best.endIndex
        best.insert(result, at: index)
        if best.count > limit { best.removeLast() }
    }

    private func intersectedTrigramCandidates(
        query: String,
        index: [String: [Int]]
    ) -> [Int] {
        let characters = Array(query)
        guard characters.count >= 3 else { return [] }
        var keys: Set<String> = []
        for offset in 0...(characters.count - 3) {
            keys.insert(String(characters[offset...offset + 2]))
        }
        let lists = keys.compactMap { index[$0] }.sorted { $0.count < $1.count }
        guard lists.count == keys.count, let first = lists.first else { return [] }
        if lists.count == 1 { return first }
        var intersection = Set(first)
        for list in lists.dropFirst() where !intersection.isEmpty {
            intersection.formIntersection(list)
        }
        return Array(intersection)
    }

    private func addFocused(
        _ indices: [Int],
        snapshot: SearchSnapshot,
        usage: [String: UsageRecord],
        to candidates: inout Set<Int>,
        limit: Int
    ) {
        candidates.formUnion(indices.prefix(limit))
        for id in usage.keys {
            if let index = snapshot.indexByID[id] { candidates.insert(index) }
        }
        candidates.formUnion(snapshot.runningIndices)
    }

    /// Larger than the spread between any two match classes, so selection history orders
    /// single-character results without letting an unmatched entry in.
    private static let singleCharacterSelectionPriority = 1_000
    /// Enough to offer the pane the query names, without filling the launcher with
    /// every other System Settings topic that shares a word.
    private static let maximumSettingsResults = 3

    private static func hasWordPrefix(_ entry: SearchEntry, _ query: String) -> Bool {
        entry.normalizedTitle.hasPrefix(query) || entry.tokens.contains { $0.hasPrefix(query) }
    }

    private func usageBoost(_ record: UsageRecord, now: Date, enabled: Bool) -> Int {
        guard enabled else { return 0 }
        let frequency = min(80, Int(log2(Double(record.selectionCount + 1)) * 20))
        let age = now.timeIntervalSince(record.lastUsed)
        let recency: Int
        switch age {
        case ..<86_400: recency = 40
        case ..<(7 * 86_400): recency = 20
        case ..<(30 * 86_400): recency = 10
        default: recency = 0
        }
        return min(120, frequency + recency)
    }

    private func resultOrder(_ lhs: Candidate, _ rhs: Candidate) -> Bool {
        if lhs.result.score != rhs.result.score { return lhs.result.score > rhs.result.score }
        let lhsPriority = kindTieBreakPriority(lhs.result.entry.kind)
        let rhsPriority = kindTieBreakPriority(rhs.result.entry.kind)
        if lhsPriority != rhsPriority { return lhsPriority < rhsPriority }
        return lhs.localizedSortRank < rhs.localizedSortRank
    }

    /// Equal-relevance matches break ties toward launchable targets: the application named
    /// “System Settings” outranks every pane whose title merely contains the matched word.
    private func kindTieBreakPriority(_ kind: SearchKind) -> Int {
        switch kind {
        case .application: 0
        case .systemSetting: 1
        case .action: 2
        case .file, .calculator, .clipboard, .webSearch, .status: 3
        }
    }
}
