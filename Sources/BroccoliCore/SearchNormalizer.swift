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

    public static func acronym(_ value: String) -> String {
        tokens(value).compactMap(\.first).map(String.init).joined()
    }
}
