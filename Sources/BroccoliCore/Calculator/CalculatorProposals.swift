import Foundation

public enum CalculatorProposalValidator {
    /// Builds a query the local calculator can evaluate. Returns nil when the proposal
    /// invents a number or leaves out a unit the calculator knows how to check.
    public static func canonicalQuery(
        kind: String,
        numbers: [Double],
        source: String,
        target: String,
        operation: String,
        originalQuery: String
    ) -> String? {
        guard numbers.allSatisfy({ numberAppears($0, in: originalQuery) }) else { return nil }
        switch kind {
        case "unit":
            guard let amount = numbers.first,
                  CalculatorLexicon.unit(named: source) != nil,
                  CalculatorLexicon.unit(named: target) != nil else { return nil }
            return "\(plain(amount)) \(source) in \(target)"
        case "percentage":
            guard numbers.count >= 2 else { return nil }
            switch operation {
            case "of": return "\(plain(numbers[0]))% of \(plain(numbers[1]))"
            case "add": return "\(plain(numbers[1])) + \(plain(numbers[0]))%"
            case "off": return "\(plain(numbers[0]))% off \(plain(numbers[1]))"
            default: return nil
            }
        case "currency":
            guard let amount = numbers.first,
                  let sourceCode = CalculatorCurrencies.code(for: source),
                  let targetCode = CalculatorCurrencies.code(for: target) else { return nil }
            return "\(plain(amount)) \(sourceCode) in \(targetCode)"
        case "timeZone":
            guard let hour = numbers.first, (0...24).contains(hour) else { return nil }
            let marker = operation == "am" || operation == "pm" ? operation : ""
            let phrase = "\(plain(hour)) \(marker) \(source) to \(target)"
                .replacingOccurrences(of: "  ", with: " ")
            return phrase.trimmingCharacters(in: .whitespaces)
        default:
            return nil
        }
    }

    private static func numberAppears(_ number: Double, in query: String) -> Bool {
        let digits = query.filter(\.isNumber)
        let rendered = plain(number).filter(\.isNumber)
        return !rendered.isEmpty && digits.contains(rendered)
    }

    private static func plain(_ number: Double) -> String {
        if number.rounded() == number, abs(number) < 1_000_000_000_000 {
            return String(Int(number))
        }
        return String(number)
    }
}
