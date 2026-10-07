import Foundation

public enum SearchNormalizer {
    public static func normalize(_ value: String) -> String {
        value
            .folding(options: [.caseInsensitive, .diacriticInsensitive, .widthInsensitive], locale: .current)
            .split(whereSeparator: { $0.isWhitespace })
            .joined(separator: " ")
    }

    public static func tokens(_ value: String) -> [String] {
        normalize(value)
            .split(whereSeparator: { !$0.isLetter && !$0.isNumber })
            .map(String.init)
    }

    public static func compact(_ value: String) -> String {
        normalize(value).filter { $0.isLetter || $0.isNumber }
    }

    /// Whether `compactQuery` begins on a word inside `value`. Several words may be typed
    /// run together, so "chromecanary" matches "Google Chrome Canary". A hit that begins
    /// inside a word does not, so "chr" does not match the join in "speech recognition".
    public static func matchesFromWordStart(_ compactQuery: String, in value: String) -> Bool {
        guard !compactQuery.isEmpty else { return false }
        let words = tokens(value)
        let compactValue = words.joined()
        guard compactValue.count >= compactQuery.count else { return false }
        var start = compactValue.startIndex
        for word in words {
            if compactValue[start...].hasPrefix(compactQuery) { return true }
            guard let next = compactValue.index(
                start,
                offsetBy: word.count,
                limitedBy: compactValue.endIndex
            ) else { return false }
            start = next
        }
        return false
    }

    public static func acronym(_ value: String) -> String {
        tokens(value).compactMap(\.first).map(String.init).joined()
    }
}
