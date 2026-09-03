import Foundation

public struct CalculatorResult: Equatable, Sendable {
    public let displayText: String
    public let copyText: String

    public init(displayText: String, copyText: String) {
        self.displayText = displayText
        self.copyText = copyText
    }
}

public enum CalculatorEvaluation: Equatable, Sendable {
    case value(CalculatorResult)
    case incomplete
    case invalid
    case notExpression
}

public struct CalculatorEngine: Sendable {
    private struct UnitDefinition: Sendable {
        let dimension: String
        let symbol: String
        let scale: Double
        let offset: Double
    }

    private enum Token: Equatable {
        case number(Double)
        case identifier(String)
        case plus, minus, multiply, divide, power, percent
        case leftParen, rightParen
        case end
    }

    private struct Parser {
        var tokens: [Token]
        var index = 0

        mutating func parse() throws -> Double {
            let value = try additive()
            guard current == .end, value.isFinite else { throw ParseError.invalid }
            return value
        }

        private var current: Token { tokens[min(index, tokens.count - 1)] }

        private mutating func advance() { index += 1 }

        private mutating func additive() throws -> Double {
            var value = try multiplicative()
            while true {
                switch current {
                case .plus:
                    advance()
                    value += try multiplicative()
                case .minus:
                    advance()
                    value -= try multiplicative()
                default:
                    return value
                }
            }
        }

        private mutating func multiplicative() throws -> Double {
            var value = try unary()
            while true {
                switch current {
                case .multiply:
                    advance()
                    value *= try unary()
                case .divide:
                    advance()
                    let divisor = try unary()
                    guard divisor != 0 else { throw ParseError.invalid }
                    value /= divisor
                default:
                    return value
                }
            }
        }

        private mutating func unary() throws -> Double {
            switch current {
            case .plus:
                advance()
                return try unary()
            case .minus:
                advance()
                return -(try unary())
            default:
                return try exponent()
            }
        }

        private mutating func exponent() throws -> Double {
            var value = try postfix()
            if current == .power {
                advance()
                value = Foundation.pow(value, try unary())
            }
            return value
        }

        private mutating func postfix() throws -> Double {
            var value = try primary()
            while current == .percent {
                advance()
                value /= 100
            }
            return value
        }

        private mutating func primary() throws -> Double {
            switch current {
            case .number(let value):
                advance()
                return value
            case .identifier(let identifier):
                advance()
                if identifier == "pi" { return .pi }
                if identifier == "e" { return M_E }
                guard current == .leftParen else { throw ParseError.invalid }
                advance()
                let value = try additive()
                guard current == .rightParen else { throw ParseError.invalid }
                advance()
                return try apply(function: identifier, to: value)
            case .leftParen:
                advance()
                let value = try additive()
                guard current == .rightParen else { throw ParseError.invalid }
                advance()
                return value
            default:
                throw ParseError.invalid
            }
        }

        private func apply(function: String, to value: Double) throws -> Double {
            let result: Double
            switch function {
            case "sqrt": result = Foundation.sqrt(value)
            case "sin": result = Foundation.sin(value)
            case "cos": result = Foundation.cos(value)
            case "tan": result = Foundation.tan(value)
            case "asin": result = Foundation.asin(value)
            case "acos": result = Foundation.acos(value)
            case "atan": result = Foundation.atan(value)
            case "log": result = Foundation.log10(value)
            case "ln": result = Foundation.log(value)
            case "abs": result = Swift.abs(value)
            case "floor": result = Foundation.floor(value)
            case "ceil": result = Foundation.ceil(value)
            case "round": result = Foundation.round(value)
            default: throw ParseError.invalid
            }
            guard result.isFinite else { throw ParseError.invalid }
            return result
        }
    }

    private enum ParseError: Error { case invalid }

    public init() {}

    public func looksLikeIncompleteExpression(_ rawQuery: String) -> Bool {
        classify(rawQuery) == .incomplete
    }

    public func evaluate(
        _ rawQuery: String,
        locale: Locale = .current,
        maximumSignificantDigits: Int = 12,
        usesGroupingSeparator: Bool = false
    ) -> CalculatorResult? {
        guard case .value(let result) = classify(
            rawQuery,
            locale: locale,
            maximumSignificantDigits: maximumSignificantDigits,
            usesGroupingSeparator: usesGroupingSeparator
        ) else { return nil }
        return result
    }

    public func classify(
        _ rawQuery: String,
        locale: Locale = .current,
        maximumSignificantDigits: Int = 12,
        usesGroupingSeparator: Bool = false
    ) -> CalculatorEvaluation {
        let raw = rawQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !raw.isEmpty else { return .notExpression }
        guard let normalized = normalizeEquals(in: raw) else { return .invalid }
        let query = normalized.expression
        guard !query.isEmpty else {
            return normalized.explicitlyRequested ? .incomplete : .notExpression
        }

        if let conversion = conversionParts(in: query),
           let source = Self.units[normalizeUnit(conversion.sourceUnit)],
           let target = Self.units[normalizeUnit(conversion.targetUnit)],
           source.dimension == target.dimension,
           let amount = evaluateExpression(conversion.expression),
           let converted = convert(amount, from: source, to: target) {
            let amountText = format(
                amount,
                locale: locale,
                maximumSignificantDigits: maximumSignificantDigits,
                usesGroupingSeparator: usesGroupingSeparator
            )
            let convertedText = format(
                converted,
                locale: locale,
                maximumSignificantDigits: maximumSignificantDigits,
                usesGroupingSeparator: usesGroupingSeparator
            )
            return .value(CalculatorResult(
                displayText: "\(amountText) \(source.symbol) = \(convertedText) \(target.symbol)",
                copyText: convertedText
            ))
        }

        let isExpression = normalized.explicitlyRequested || isConfidentExpression(query)
        guard isExpression else { return .notExpression }
        guard let value = evaluateExpression(query) else {
            return isIncompleteExpression(query) ? .incomplete : .invalid
        }
        let formatted = format(
            value,
            locale: locale,
            maximumSignificantDigits: maximumSignificantDigits,
            usesGroupingSeparator: usesGroupingSeparator
        )
        return .value(CalculatorResult(displayText: formatted, copyText: formatted))
    }

    private func normalizeEquals(
        in rawQuery: String
    ) -> (expression: String, explicitlyRequested: Bool)? {
        let equalsIndices = rawQuery.indices.filter { rawQuery[$0] == "=" }
        guard equalsIndices.count <= 1 else { return nil }
        guard let equalsIndex = equalsIndices.first else {
            return (rawQuery, false)
        }

        let before = rawQuery[..<equalsIndex]
        let after = rawQuery[rawQuery.index(after: equalsIndex)...]
        let beforeTrimmed = before.trimmingCharacters(in: .whitespacesAndNewlines)
        let afterTrimmed = after.trimmingCharacters(in: .whitespacesAndNewlines)
        let isBoundary = beforeTrimmed.isEmpty || afterTrimmed.isEmpty
        let operators = CharacterSet(charactersIn: "+-−*/×÷^%")
        let isBesideOperator = beforeTrimmed.unicodeScalars.last.map(operators.contains) == true
            || afterTrimmed.unicodeScalars.first.map(operators.contains) == true
        guard isBoundary || isBesideOperator else { return nil }

        let expression = String(before + after)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return (expression, true)
    }

    private func isIncompleteExpression(_ query: String) -> Bool {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return true }
        if let last = trimmed.unicodeScalars.last,
           CharacterSet(charactersIn: "+-−*/×÷^").contains(last) {
            return true
        }

        var balance = 0
        for character in trimmed {
            if character == "(" { balance += 1 }
            if character == ")" {
                balance -= 1
                if balance < 0 { return false }
            }
        }
        if balance > 0 { return true }

        let lower = trimmed.lowercased()
        return lower.hasSuffix(" in") || lower.hasSuffix(" to")
    }

    private func evaluateExpression(_ expression: String) -> Double? {
        guard let tokens = tokenize(expression) else { return nil }
        var parser = Parser(tokens: tokens + [.end])
        return try? parser.parse()
    }

    private func tokenize(_ expression: String) -> [Token]? {
        let characters = Array(expression.lowercased())
        var tokens: [Token] = []
        var index = 0
        while index < characters.count {
            let character = characters[index]
            if character.isWhitespace {
                index += 1
                continue
            }
            if character.isNumber || character == "." {
                let start = index
                var hasDecimal = false
                while index < characters.count {
                    let next = characters[index]
                    if next == "." {
                        guard !hasDecimal else { return nil }
                        hasDecimal = true
                    } else if !next.isNumber {
                        break
                    }
                    index += 1
                }
                guard let value = Double(String(characters[start..<index])) else { return nil }
                tokens.append(.number(value))
                continue
            }
            if character.isLetter {
                let start = index
                while index < characters.count, characters[index].isLetter { index += 1 }
                tokens.append(.identifier(String(characters[start..<index])))
                continue
            }
            let token: Token
            switch character {
            case "+": token = .plus
            case "-", "−": token = .minus
            case "*", "×": token = .multiply
            case "/", "÷": token = .divide
            case "^": token = .power
            case "%": token = .percent
            case "(": token = .leftParen
            case ")": token = .rightParen
            default: return nil
            }
            tokens.append(token)
            index += 1
        }
        return tokens
    }

    private func isConfidentExpression(_ query: String) -> Bool {
        if query.range(of: #"[+*/×÷^%]"#, options: .regularExpression) != nil,
           query.rangeOfCharacter(from: .decimalDigits) != nil {
            return true
        }
        if query.range(of: #"[0-9)]\s*[+\-−*/×÷^%]\s*[0-9(]"#, options: .regularExpression) != nil {
            return true
        }
        let lower = query.lowercased()
        return ["sqrt(", "sin(", "cos(", "tan(", "asin(", "acos(", "atan(", "log(", "ln(", "abs(", "floor(", "ceil(", "round("].contains {
            lower.contains($0)
        }
    }

    private func conversionParts(in query: String) -> (expression: String, sourceUnit: String, targetUnit: String)? {
        let lower = query.lowercased()
        let separator: Range<String.Index>?
        if let range = lower.range(of: " in ", options: .backwards) { separator = range }
        else { separator = lower.range(of: " to ", options: .backwards) }
        guard let separator else { return nil }
        let left = String(query[..<separator.lowerBound]).trimmingCharacters(in: .whitespaces)
        let target = String(query[separator.upperBound...]).trimmingCharacters(in: .whitespaces)
        guard !left.isEmpty, !target.isEmpty else { return nil }

        let aliases = Self.units.keys.sorted { $0.count > $1.count }
        for alias in aliases {
            guard left.lowercased().hasSuffix(alias) else { continue }
            let boundary = left.index(left.endIndex, offsetBy: -alias.count)
            guard boundary > left.startIndex,
                  left[left.index(before: boundary)].isWhitespace else { continue }
            let expression = String(left[..<boundary]).trimmingCharacters(in: .whitespaces)
            if !expression.isEmpty {
                return (expression, alias, target)
            }
        }
        return nil
    }

    private func convert(_ value: Double, from source: UnitDefinition, to target: UnitDefinition) -> Double? {
        let base = value * source.scale + source.offset
        let result = (base - target.offset) / target.scale
        return result.isFinite ? result : nil
    }

    private func normalizeUnit(_ unit: String) -> String {
        unit.lowercased()
            .replacingOccurrences(of: "²", with: "2")
            .replacingOccurrences(of: "³", with: "3")
            .replacingOccurrences(of: "^", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func format(
        _ value: Double,
        locale: Locale,
        maximumSignificantDigits: Int,
        usesGroupingSeparator: Bool
    ) -> String {
        let formatter = NumberFormatter()
        formatter.locale = locale
        formatter.numberStyle = .decimal
        formatter.usesGroupingSeparator = usesGroupingSeparator
        formatter.maximumSignificantDigits = min(12, max(1, maximumSignificantDigits))
        formatter.minimumSignificantDigits = 1
        return formatter.string(from: NSNumber(value: value)) ?? String(value)
    }

    private static let units: [String: UnitDefinition] = {
        var result: [String: UnitDefinition] = [:]
        func add(_ dimension: String, _ symbol: String, _ scale: Double, _ aliases: [String], offset: Double = 0) {
            let definition = UnitDefinition(dimension: dimension, symbol: symbol, scale: scale, offset: offset)
            for alias in aliases { result[alias] = definition }
        }

        add("length", "m", 1, ["m", "meter", "meters", "metre", "metres"])
        add("length", "km", 1_000, ["km", "kilometer", "kilometers", "kilometre", "kilometres"])
        add("length", "cm", 0.01, ["cm", "centimeter", "centimeters"])
        add("length", "mm", 0.001, ["mm", "millimeter", "millimeters"])
        add("length", "mi", 1_609.344, ["mi", "mile", "miles"])
        add("length", "yd", 0.9144, ["yd", "yard", "yards"])
        add("length", "ft", 0.3048, ["ft", "foot", "feet"])
        add("length", "in", 0.0254, ["inch", "inches"])

        add("area", "m²", 1, ["m2", "sqm"])
        add("area", "km²", 1_000_000, ["km2", "sqkm"])
        add("area", "cm²", 0.0001, ["cm2", "sqcm"])
        add("area", "ft²", 0.09290304, ["ft2", "sqft"])
        add("area", "in²", 0.00064516, ["in2", "sqin"])
        add("area", "acre", 4_046.8564224, ["acre", "acres"])
        add("area", "ha", 10_000, ["ha", "hectare", "hectares"])

        add("volume", "L", 1, ["l", "liter", "liters", "litre", "litres"])
        add("volume", "mL", 0.001, ["ml", "milliliter", "milliliters"])
        add("volume", "m³", 1_000, ["m3"])
        add("volume", "cm³", 0.001, ["cm3"])
        add("volume", "gal", 3.785411784, ["gal", "gallon", "gallons"])
        add("volume", "qt", 0.946352946, ["qt", "quart", "quarts"])
        add("volume", "pt", 0.473176473, ["pt", "pint", "pints"])
        add("volume", "cup", 0.2365882365, ["cup", "cups"])
        add("volume", "fl oz", 0.0295735295625, ["fl oz", "floz"])

        add("mass", "kg", 1, ["kg", "kilogram", "kilograms"])
        add("mass", "g", 0.001, ["g", "gram", "grams"])
        add("mass", "mg", 0.000001, ["mg", "milligram", "milligrams"])
        add("mass", "lb", 0.45359237, ["lb", "lbs", "pound", "pounds"])
        add("mass", "oz", 0.028349523125, ["oz", "ounce", "ounces"])
        add("mass", "t", 1_000, ["t", "tonne", "tonnes"])

        add("temperature", "°C", 1, ["c", "°c", "celsius"])
        add("temperature", "°F", 5.0 / 9.0, ["f", "°f", "fahrenheit"], offset: -32 * 5.0 / 9.0)
        add("temperature", "K", 1, ["k", "kelvin"], offset: -273.15)

        add("time", "s", 1, ["s", "sec", "second", "seconds"])
        add("time", "min", 60, ["min", "minute", "minutes"])
        add("time", "h", 3_600, ["h", "hr", "hour", "hours"])
        add("time", "day", 86_400, ["day", "days"])
        add("time", "week", 604_800, ["week", "weeks"])

        add("speed", "m/s", 1, ["m/s", "mps"])
        add("speed", "km/h", 1 / 3.6, ["km/h", "kph"])
        add("speed", "mph", 0.44704, ["mph"])
        add("speed", "kn", 0.514444, ["kn", "knot", "knots"])

        add("angle", "rad", 1, ["rad", "radian", "radians"])
        add("angle", "°", .pi / 180, ["deg", "degree", "degrees", "°"])

        add("data", "B", 1, ["b", "byte", "bytes"])
        add("data", "KB", 1_000, ["kb"])
        add("data", "MB", 1_000_000, ["mb"])
        add("data", "GB", 1_000_000_000, ["gb"])
        add("data", "TB", 1_000_000_000_000, ["tb"])
        add("data", "KiB", 1_024, ["kib"])
        add("data", "MiB", 1_048_576, ["mib"])
        add("data", "GiB", 1_073_741_824, ["gib"])
        return result
    }()
}
