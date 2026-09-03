import Foundation

public struct SearchEngine: Sendable {
    private struct Candidate {
        let result: RankedResult
        let localizedSortRank: Int
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
            return best.map(\.result)
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
            for id in usage.keys {
                guard let index = snapshot.indexByID[id],
                      snapshot.entries[index].normalizedTitle.hasPrefix(normalizedQuery),
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

        for index in candidateIndices {
            let entry = snapshot.entries[index]
            guard preferences.includes(entry) else { continue }
            guard let baseScore = matchScore(
                query: normalizedQuery,
                compactQuery: compactQuery,
                queryTokens: queryTokens,
                entry: entry
            ) else { continue }
            let runningBonus = entry.isRunning ? 20 : 0
            let adaptive = usage[entry.id].map {
                usageBoost($0, now: now, enabled: preferences.adaptiveRankingEnabled)
            } ?? 0
            insert(
                Candidate(
                    result: RankedResult(
                        entry: entry,
                        score: baseScore + runningBonus + adaptive
                    ),
                    localizedSortRank: snapshot.localizedSortRanks[index]
                ),
                into: &best,
                limit: limit
            )
        }
        return best.map(\.result)
    }

    private func matchScore(
        query: String,
        compactQuery: String,
        queryTokens: [String],
        entry: SearchEntry
    ) -> Int? {
        if entry.normalizedTitle == query { return 1_000 }
        if !compactQuery.isEmpty, entry.compactTitle == compactQuery { return 1_000 }
        if entry.normalizedTitle.hasPrefix(query) { return 800 }
        if !compactQuery.isEmpty, entry.compactTitle.hasPrefix(compactQuery) { return 800 }
        // A bare number is much more likely to be the beginning of a calculation than a
        // request for every catalog item containing that digit. Keep genuinely numeric app
        // names (for example, 1Password) searchable through the direct-prefix checks above,
        // but do not surface incidental matches such as the System Settings term “802.1X”.
        if query.allSatisfy(\.isNumber) { return nil }
        if queryTokens.count > 1 {
            let keywordTokens = entry.keywords.flatMap(SearchNormalizer.tokens)
            var score = 400
            for token in queryTokens {
                if entry.tokens.contains(token) {
                    score += 150
                } else if entry.tokens.contains(where: { $0.hasPrefix(token) }) {
                    score += 130
                } else if entry.normalizedTitle.contains(token) {
                    score += 105
                } else if keywordTokens.contains(token) {
                    score += 90
                } else if keywordTokens.contains(where: { $0.hasPrefix(token) }) {
                    score += 75
                } else if entry.keywords.contains(where: { $0.contains(token) }) {
                    score += 60
                } else {
                    return nil
                }
            }
            return score
        }
        for token in entry.tokens where token.hasPrefix(query) { return 650 }
        if entry.acronym.hasPrefix(query) { return 600 }
        if entry.normalizedTitle.contains(query) { return 450 }
        if !compactQuery.isEmpty, entry.compactTitle.contains(compactQuery) { return 450 }
        for keyword in entry.keywords where keyword.hasPrefix(query) { return 350 }
        if !compactQuery.isEmpty,
           entry.compactKeywords.contains(where: { $0.hasPrefix(compactQuery) }) { return 350 }
        for keyword in entry.keywords where keyword.contains(query) { return 250 }
        if !compactQuery.isEmpty,
           entry.compactKeywords.contains(where: { $0.contains(compactQuery) }) { return 250 }
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
        return lhs.localizedSortRank < rhs.localizedSortRank
    }
}
