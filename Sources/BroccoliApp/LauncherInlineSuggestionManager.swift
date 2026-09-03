import BroccoliCore

/// Selects information that belongs beside the editable query instead of in the result list.
/// The policy is intentionally pure and allocation-light because it runs for every published
/// search generation.
enum LauncherInlineSuggestionManager {
    static func suggestion(from results: [RankedResult]) -> RankedResult? {
        results.first { $0.entry.kind == .calculator }
    }

    static func displayText(for result: RankedResult, query: String) -> String {
        guard result.entry.kind == .calculator else { return result.entry.title }
        let answer: String
        if let separator = result.entry.title.range(of: " = ", options: .backwards) {
            // Conversion results carry a complete descriptive title for accessibility and
            // execution. Inline, only the converted value belongs after the user's query.
            answer = String(result.entry.title[separator.upperBound...])
        } else {
            answer = result.entry.title
        }
        return query.trimmingCharacters(in: .whitespacesAndNewlines).hasSuffix("=")
            ? answer
            : "= \(answer)"
    }

    static func accessibilityLabel(for result: RankedResult, query: String) -> String {
        result.entry.kind == .calculator
            ? "Calculator result \(displayText(for: result, query: query))"
            : result.entry.title
    }
}
