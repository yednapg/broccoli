import Foundation

public enum CalculatorGallonChoice: String, Sendable, Equatable {
    case automatic
    case us
    case imperial
}

public struct CalculatorContext: Sendable, Equatable {
    public var now: Date
    public var timeZone: TimeZone
    public var locale: Locale
    public var regionCode: String?
    public var maximumSignificantDigits: Int
    public var usesGroupingSeparator: Bool
    public var homeCurrencyCode: String?
    public var secondaryCurrencyCode: String?
    public var taxPercent: Double
    public var rates: CurrencyRateSnapshot?
    public var choiceMemory: [String: String]
    public var lastAnswer: Double?
    public var gallonChoice: CalculatorGallonChoice
    public var pixelsPerInch: Double
    public var baseFontPixels: Double

    public init(
        now: Date = Date(),
        timeZone: TimeZone = .current,
        locale: Locale = .current,
        regionCode: String? = nil,
        maximumSignificantDigits: Int = 12,
        usesGroupingSeparator: Bool = false,
        homeCurrencyCode: String? = nil,
        secondaryCurrencyCode: String? = nil,
        taxPercent: Double = 0,
        rates: CurrencyRateSnapshot? = nil,
        choiceMemory: [String: String] = [:],
        lastAnswer: Double? = nil,
        gallonChoice: CalculatorGallonChoice = .automatic,
        pixelsPerInch: Double = 72,
        baseFontPixels: Double = 16
    ) {
        self.now = now
        self.timeZone = timeZone
        self.locale = locale
        self.regionCode = regionCode ?? locale.region?.identifier
        self.maximumSignificantDigits = maximumSignificantDigits
        self.usesGroupingSeparator = usesGroupingSeparator
        self.homeCurrencyCode = homeCurrencyCode
        self.secondaryCurrencyCode = secondaryCurrencyCode
        self.taxPercent = taxPercent
        self.rates = rates
        self.choiceMemory = choiceMemory
        self.lastAnswer = lastAnswer
        self.gallonChoice = gallonChoice
        self.pixelsPerInch = pixelsPerInch
        self.baseFontPixels = baseFontPixels
    }
}

public struct CalculatorResult: Equatable, Sendable {
    public let displayText: String
    public let copyText: String
    public let context: String?
    public let patternKey: String?
    public let presentsInline: Bool

    public init(
        displayText: String,
        copyText: String,
        context: String? = nil,
        patternKey: String? = nil,
        presentsInline: Bool = true
    ) {
        self.displayText = displayText
        self.copyText = copyText
        self.context = context
        self.patternKey = patternKey
        self.presentsInline = presentsInline
    }
}

public enum CalculatorEvaluation: Equatable, Sendable {
    case value(CalculatorResult)
    case choices([CalculatorResult])
    case hint(String)
    case unavailable(String)
    case incomplete
    case invalid
    case notExpression
}

public struct CalculatorEngine: Sendable {
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
        classify(
            rawQuery,
            context: CalculatorContext(
                locale: locale,
                maximumSignificantDigits: maximumSignificantDigits,
                usesGroupingSeparator: usesGroupingSeparator
            )
        )
    }

    public func classify(_ rawQuery: String, context: CalculatorContext) -> CalculatorEvaluation {
        let raw = rawQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !raw.isEmpty else { return .notExpression }
        guard mightCalculate(raw) else { return .notExpression }
        guard let normalized = normalizeEquals(in: raw) else { return .invalid }
        let query = normalized.expression
        guard !query.isEmpty else {
            return normalized.explicitlyRequested ? .incomplete : .notExpression
        }
        var tokens = lex(query, locale: context.locale)
        tokens = stripFiller(tokens)
        guard !tokens.isEmpty else {
            return normalized.explicitlyRequested ? .incomplete : .notExpression
        }

        if let result = timeQuery(tokens, context: context) { return result }
        if let result = dateQuery(tokens, raw: query, context: context) { return result }
        if let result = financeQuery(tokens, context: context) { return result }
        if let result = currencyQuery(tokens, context: context) { return result }
        if let result = percentQuery(tokens, context: context) { return result }
        if let result = designQuery(tokens, context: context) { return result }
        if let result = baseQuery(tokens, context: context) { return result }
        if let result = unitQuery(tokens, context: context) { return result }
        if isBaseLiteral(query), tokens.count == 1, case .num(let value) = tokens[0] {
            let formatted = format(value, context: context)
            return .value(CalculatorResult(displayText: formatted, copyText: formatted, context: "decimal"))
        }

        let claimed = normalized.explicitlyRequested || isConfident(query, tokens: tokens)
        guard claimed else { return .notExpression }
        guard let value = evaluate(tokens, context: context) else {
            return isIncomplete(query, tokens: tokens) ? .incomplete : .invalid
        }
        let formatted = format(value, context: context)
        return .value(CalculatorResult(displayText: formatted, copyText: formatted, context: trigContext(for: query)))
    }

    // MARK: - Recognition

    private func timeQuery(_ tokens: [Tok], context: CalculatorContext) -> CalculatorEvaluation? {
        if word(tokens, 0) == "time" {
            if word(tokens, 1) == "diff" || word(tokens, 1) == "difference" {
                guard let place = takePlace(tokens, from: 2, context: context) else { return .incomplete }
                return timeDifference(place, context: context)
            }
            if word(tokens, 1) == "in", case .num(let amount) = token(tokens, 2), let unitWord = word(tokens, 3) {
                let seconds = durationSeconds(amount, unitWord: unitWord)
                guard let seconds else { return nil }
                let target = takePlace(tokens, from: 5, context: context)
                let when = context.now.addingTimeInterval(seconds)
                let zone = target.flatMap { TimeZone(identifier: $0.place.timeZoneIdentifier) } ?? context.timeZone
                let label = target?.place.label ?? "local time"
                return .value(clockResult(when, zone: zone, context: context, contextLine: "Time in \(Int(amount)) \(unitWord) · \(label)"))
            }
            if word(tokens, 1) == "in", let place = takePlace(tokens, from: 2, context: context) {
                return renderPlaceTime(place, at: context.now, context: context, prefix: "Time in")
            }
            return .hint("Try “time in Tokyo” or “5 pm Germany to IST”.")
        }

        guard let clock = takeClock(tokens, from: 0) else { return nil }
        if let shifted = shiftClock(clock, tokens: tokens, context: context) { return shifted }
        guard let source = takePlace(tokens, from: clock.next, context: context) else { return nil }
        let connector = word(tokens, source.next)
        guard connector == "to" || connector == "in" || connector == "into" else { return nil }
        guard let target = takePlace(tokens, from: source.next + 1, context: context) else {
            return .incomplete
        }
        return convertClock(clock, from: source, to: target, context: context)
    }

    private func dateQuery(_ tokens: [Tok], raw: String, context: CalculatorContext) -> CalculatorEvaluation? {
        if tokens.count == 1, case .num(let value) = tokens[0],
           raw.allSatisfy(\.isNumber), raw.count == 10,
           value >= 1_000_000_000, value < 10_000_000_000 {
            let date = Date(timeIntervalSince1970: value)
            let text = formatDate(date, context: context)
            return .value(CalculatorResult(
                displayText: text,
                copyText: text,
                context: "Unix time \(raw)",
                presentsInline: true
            ))
        }
        if let word = word(tokens, 0), word.hasPrefix("iso:"), let instant = parseISO(String(word.dropFirst(4)), context: context) {
            let text = word.contains("T") ? formatTime(instant, zone: context.timeZone, context: context) : formatDate(instant, context: context)
            let shown = word.contains("T") ? "\(formatDate(instant, context: context)), \(text)" : text
            return .value(CalculatorResult(displayText: shown, copyText: shown, context: String(word.dropFirst(4))))
        }
        if let weekdayName = (tokens.count == 1 ? word(tokens, 0) : (word(tokens, 0) == "this" ? word(tokens, 1) : nil)),
           let weekdayIndex = weekdays[weekdayName] {
            let date = upcomingWeekday(weekdayIndex, from: context.now, calendar: context.calendar, includingToday: true)
            let text = formatDate(date, context: context)
            return .value(CalculatorResult(displayText: text, copyText: text, context: weekdayName.capitalized))
        }
        if let boundary = calendarBoundary(tokens, context: context) { return boundary }
        if case .num(let count) = token(tokens, 0),
           let unit = word(tokens, 1), unit == "workday" || unit == "workdays",
           word(tokens, 2) == "from", word(tokens, 3) == "today" {
            let date = addingWorkdays(Int(count), to: context.now, calendar: context.calendar)
            let text = formatDate(date, context: context)
            return .value(CalculatorResult(displayText: text, copyText: text, context: "\(Int(count)) workdays from today · weekends skipped"))
        }
        if tokens.count == 1, let word = word(tokens, 0), let offset = dayWord(word) {
            let date = context.calendar.date(byAdding: .day, value: offset, to: context.now) ?? context.now
            let text = formatDate(date, context: context)
            return .value(CalculatorResult(displayText: text, copyText: text, context: word.capitalized))
        }
        if word(tokens, 0) == "next", let weekday = word(tokens, 1), let weekdayIndex = weekdays[weekday] {
            let date = nextWeekday(weekdayIndex, after: context.now, calendar: context.calendar, weeks: 1)
            let text = formatDate(date, context: context)
            return .value(CalculatorResult(displayText: text, copyText: text, context: "Next \(weekday.capitalized)"))
        }
        if let weekday = word(tokens, 0), let weekdayIndex = weekdays[weekday],
           word(tokens, 1) == "in", case .num(let count) = token(tokens, 2),
           let unit = word(tokens, 3), unit == "week" || unit == "weeks" {
            let date = nextWeekday(weekdayIndex, after: context.now, calendar: context.calendar, weeks: Int(count))
            let text = formatDate(date, context: context)
            return .value(CalculatorResult(
                displayText: text,
                copyText: text,
                context: "\(weekday.capitalized) in \(Int(count)) weeks"
            ))
        }
        if word(tokens, 0) == "days", word(tokens, 1) == "until", let date = takeDate(tokens, from: 2, context: context) {
            let days = context.calendar.dateComponents([.day], from: context.calendar.startOfDay(for: context.now), to: context.calendar.startOfDay(for: date)).day ?? 0
            let text = "\(days)"
            return .value(CalculatorResult(displayText: text, copyText: text, context: "Days until \(formatDate(date, context: context))"))
        }
        if word(tokens, 0) == "days", word(tokens, 1) == "between",
           let start = takeDate(tokens, from: 2, context: context) {
            let andIndex = tokens.firstIndex { if case .word(let word) = $0 { return word == "and" }; return false }
            guard let andIndex, let end = takeDate(tokens, from: andIndex + 1, context: context) else { return .incomplete }
            let days = context.calendar.dateComponents([.day], from: context.calendar.startOfDay(for: start), to: context.calendar.startOfDay(for: end)).day ?? 0
            let text = "\(abs(days))"
            return .value(CalculatorResult(displayText: text, copyText: text, context: "Days between \(formatDate(start, context: context)) and \(formatDate(end, context: context))"))
        }
        if case .num(let count) = token(tokens, 0),
           let unit = word(tokens, 1), word(tokens, 2) == "from", word(tokens, 3) == "today",
           let component = dateComponent(unit) {
            guard let date = context.calendar.date(byAdding: component, value: Int(count), to: context.now) else { return .invalid }
            let text = formatDate(date, context: context)
            return .value(CalculatorResult(displayText: text, copyText: text, context: "\(Int(count)) \(unit) from today"))
        }
        if let start = takeDate(tokens, from: 0, context: context),
           token(tokens, dateTokenCount(tokens, from: 0)) == .plus,
           case .num(let count) = token(tokens, dateTokenCount(tokens, from: 0) + 1) {
            let unitIndex = dateTokenCount(tokens, from: 0) + 2
            let unit = word(tokens, unitIndex) ?? "days"
            guard let component = dateComponent(unit) ?? (unit == "day" || unit == "days" ? .day : nil),
                  let date = context.calendar.date(byAdding: component, value: Int(count), to: start) else { return nil }
            let text = formatDate(date, context: context)
            return .value(CalculatorResult(displayText: text, copyText: text, context: "\(formatDate(start, context: context)) + \(Int(count)) \(unit)"))
        }
        return nil
    }

    private func currencyQuery(_ tokens: [Tok], context: CalculatorContext) -> CalculatorEvaluation? {
        let parsed = parseCurrency(tokens, context: context)
        guard let parsed else { return nil }
        guard let rates = context.rates else {
            return .unavailable("Currency rates aren't available offline yet.")
        }
        let home = context.homeCurrencyCode?.uppercased()
        let secondary = context.secondaryCurrencyCode?.uppercased()
        let target = parsed.target ?? (home != parsed.source ? home : secondary)
        guard let target, target != parsed.source else {
            return .hint("Convert \(parsed.source) to which currency?")
        }
        guard let converted = rates.convert(Decimal(parsed.amount), from: parsed.source, to: target) else {
            return .unavailable("No rate for \(parsed.source) to \(target).")
        }
        let number = NSDecimalNumber(decimal: converted).doubleValue
        guard number.isFinite else { return .invalid }
        let shown = format(number, context: context, maximumFractionDigits: abs(number) >= 1 ? 2 : nil)
        let plain = format(number, context: context.withoutGrouping, maximumFractionDigits: abs(number) >= 1 ? 2 : nil)
        let freshness = rates.freshness(now: context.now)
        let dateLabel = shortRateDate(rates.providerDate, context: context)
        let line = freshness == .current
            ? "\(rates.sourceName) rate · \(dateLabel)"
            : "Rate from \(dateLabel) · couldn't update."
        return .value(CalculatorResult(
            displayText: "\(shown) \(target)",
            copyText: plain,
            context: "\(format(parsed.amount, context: context.withoutGrouping)) \(parsed.source) → \(target). \(line)",
            presentsInline: freshness == .current
        ))
    }

    private func percentQuery(_ tokens: [Tok], context: CalculatorContext) -> CalculatorEvaluation? {
        if case .num(let percent) = token(tokens, 0), token(tokens, 1) == .percent, word(tokens, 2) == "of",
           case .num(let base) = token(tokens, 3), tokens.count == 4 {
            return percentValue(percent / 100 * base, context: context, line: "\(plain(percent))% of \(format(base, context: context))")
        }
        if case .num(let base) = token(tokens, 0), token(tokens, 1) == .plus,
           case .num(let percent) = token(tokens, 2), token(tokens, 3) == .percent, tokens.count == 4 {
            return percentValue(base * (1 + percent / 100), context: context, line: "\(format(base, context: context)) + \(plain(percent))%")
        }
        if case .num(let base) = token(tokens, 0), token(tokens, 1) == .minus,
           case .num(let percent) = token(tokens, 2), token(tokens, 3) == .percent, tokens.count == 4 {
            return percentValue(base * (1 - percent / 100), context: context, line: "\(format(base, context: context)) − \(plain(percent))%")
        }
        if word(tokens, 0) == "add", case .num(let percent) = token(tokens, 1), token(tokens, 2) == .percent,
           word(tokens, 3) == "to", case .num(let base) = token(tokens, 4) {
            return percentValue(base * (1 + percent / 100), context: context, line: "Add \(plain(percent))% to \(format(base, context: context))")
        }
        if case .num(let percent) = token(tokens, 0), token(tokens, 1) == .percent, word(tokens, 2) == "off",
           case .num(let base) = token(tokens, 3) {
            return percentValue(base * (1 - percent / 100), context: context, line: "\(plain(percent))% off \(format(base, context: context))")
        }
        if case .num(let percent) = token(tokens, 0), token(tokens, 1) == .percent,
           (word(tokens, 2) == "tip" || word(tokens, 2) == "vat" || word(tokens, 2) == "gst"),
           word(tokens, 3) == "on", case .num(let base) = token(tokens, 4) {
            return percentValue(base * percent / 100, context: context, line: "\(plain(percent))% of \(format(base, context: context))")
        }
        if case .num(let part) = token(tokens, 0), word(tokens, 1) == "is", word(tokens, 2) == "what",
           token(tokens, 3) == .percent, word(tokens, 4) == "of", case .num(let whole) = token(tokens, 5), whole != 0 {
            return percentValue(part / whole * 100, context: context, line: "\(format(part, context: context)) is what % of \(format(whole, context: context))", suffix: "%")
        }
        if case .num(let base) = token(tokens, 0), token(tokens, 1) == .plus,
           let tax = taxWord(word(tokens, 2)), context.taxPercent > 0 {
            return percentValue(base * (1 + context.taxPercent / 100), context: context, line: "\(format(base, context: context)) + \(plain(context.taxPercent))% \(tax)")
        }
        if word(tokens, 0) == "add", token(tokens, 1) == .percent || (token(tokens, 2) == .percent) {
            return .hint("Add \(percentHint(tokens))% to what?")
        }
        if case .num(let percent) = token(tokens, 0), token(tokens, 1) == .percent,
           case .num(let base) = token(tokens, 2), tokens.count == 3 {
            let memory = context.choiceMemory["percent-pair"]
            if memory == "of" {
                return percentValue(percent / 100 * base, context: context, line: "\(plain(percent))% of \(format(base, context: context))")
            }
            if memory == "add" {
                return percentValue(base * (1 + percent / 100), context: context, line: "\(format(base, context: context)) + \(plain(percent))%")
            }
            let ofValue = format(percent / 100 * base, context: context)
            let addValue = format(base * (1 + percent / 100), context: context)
            return .choices([
                CalculatorResult(displayText: "\(plain(percent))% of \(plain(base)) = \(ofValue)", copyText: ofValue, patternKey: "percent-pair=of", presentsInline: false),
                CalculatorResult(displayText: "\(plain(base)) + \(plain(percent))% = \(addValue)", copyText: addValue, patternKey: "percent-pair=add", presentsInline: false)
            ])
        }
        return nil
    }

    private func unitQuery(_ tokens: [Tok], context: CalculatorContext) -> CalculatorEvaluation? {
        if let reversed = reversedUnit(tokens) {
            return convert(amount: reversed.amount, from: reversed.source, to: reversed.target, context: context, claimed: true)
        }
        if let split = splitConversion(tokens) {
            if split.right.isEmpty { return .incomplete }
            guard let target = resolveUnit(split.right, dimension: nil, allowPrefix: true) else {
                return split.right.count == 1 ? .incomplete : .invalid
            }
            if let quantity = quantity(split.left) {
                let source = quantity.unit.symbol == "in" && split.connectorWasInches ? quantity.unit : quantity.unit
                return convert(amount: quantity.value, from: source, to: target.unit, context: context, claimed: true, prefix: !target.exact)
            }
            if split.left.count == 1, case .num(let amount) = split.left[0], split.connectorWasInches {
                guard let inches = CalculatorLexicon.unit(named: "in") else { return .invalid }
                return convert(amount: amount, from: inches, to: target.unit, context: context, claimed: true)
            }
            return .invalid
        }
        if let quantity = quantity(tokens) {
            if quantity.unit.dimension == "time" {
                let text = timespan(quantity.value * quantity.unit.scale)
                return .value(CalculatorResult(displayText: text, copyText: text, context: "\(format(quantity.value, context: context)) \(quantity.unit.symbol)"))
            }
            guard let alternate = CalculatorLexicon.alternateSymbol[quantity.unit.symbol],
                  let target = CalculatorLexicon.unit(named: alternate) else { return nil }
            return convert(amount: quantity.value, from: quantity.unit, to: target, context: context, claimed: true)
        }
        return nil
    }

    private func shiftClock(_ clock: Clock, tokens: [Tok], context: CalculatorContext) -> CalculatorEvaluation? {
        let operation = token(tokens, clock.next)
        guard operation == .plus || operation == .minus,
              case .num(let amount) = token(tokens, clock.next + 1),
              let unit = word(tokens, clock.next + 2),
              let seconds = durationSeconds(amount, unitWord: unit),
              let instant = clockInstant(clock, context: context) else { return nil }
        let delta = operation == .minus ? -seconds : seconds
        return .value(clockResult(
            instant.addingTimeInterval(delta),
            zone: context.timeZone,
            context: context,
            contextLine: "\(formatTime(instant, zone: context.timeZone, context: context)) \(operation == .plus ? "+" : "−") \(plain(amount)) \(unit)"
        ))
    }

    private func clock(from word: String, next: Int) -> Clock? {
        var body = word
        var marker: String?
        if body.hasSuffix("am") || body.hasSuffix("pm") {
            marker = String(body.suffix(2))
            body.removeLast(2)
        }
        let parts = body.split(separator: ":")
        guard parts.count >= 2, let hourRaw = Int(parts[0]), let minute = Int(parts[1]) else { return nil }
        var hour = hourRaw
        if let marker {
            if hour == 12 { hour = marker == "am" ? 0 : 12 }
            else if marker == "pm", hour < 12 { hour += 12 }
        }
        guard (0...23).contains(hour), (0...59).contains(minute) else { return nil }
        return Clock(hour: hour, minute: minute, next: next)
    }

    private func clockInstant(_ clock: Clock, context: CalculatorContext) -> Date? {
        var parts = context.calendar.dateComponents([.year, .month, .day], from: context.now)
        parts.hour = clock.hour
        parts.minute = clock.minute
        return context.calendar.date(from: parts)
    }

    private func calendarBoundary(_ tokens: [Tok], context: CalculatorContext) -> CalculatorEvaluation? {
        let edge = word(tokens, 0)
        guard edge == "start" || edge == "end", word(tokens, 1) == "of" else { return nil }
        let calendar = context.calendar
        let now = context.now
        let year = calendar.component(.year, from: now)
        let date: Date?
        if word(tokens, 2) == "month" {
            let month = calendar.component(.month, from: now)
            if edge == "start" {
                date = calendar.date(from: DateComponents(year: year, month: month, day: 1))
            } else if let startOfNext = calendar.date(from: DateComponents(year: month == 12 ? year + 1 : year, month: month == 12 ? 1 : month + 1, day: 1)) {
                date = calendar.date(byAdding: .day, value: -1, to: startOfNext)
            } else {
                date = nil
            }
        } else if word(tokens, 2) == "year" {
            date = calendar.date(from: DateComponents(year: year, month: edge == "start" ? 1 : 12, day: edge == "start" ? 1 : 31))
        } else if case .num(let explicit) = token(tokens, 2), explicit >= 1900, explicit < 10_000 {
            date = calendar.date(from: DateComponents(year: Int(explicit), month: edge == "start" ? 1 : 12, day: edge == "start" ? 1 : 31))
        } else {
            return nil
        }
        guard let date else { return .invalid }
        let text = formatDate(date, context: context)
        return .value(CalculatorResult(displayText: text, copyText: text, context: "\(edge == "start" ? "Start" : "End") of \(word(tokens, 2) ?? "")".trimmingCharacters(in: .whitespaces)))
    }

    private func upcomingWeekday(_ weekday: Int, from date: Date, calendar: Calendar, includingToday: Bool) -> Date {
        var next = calendar.startOfDay(for: date)
        if !includingToday {
            next = calendar.date(byAdding: .day, value: 1, to: next) ?? next
        }
        while calendar.component(.weekday, from: next) != weekday {
            next = calendar.date(byAdding: .day, value: 1, to: next) ?? next
        }
        return next
    }

    private func addingWorkdays(_ count: Int, to date: Date, calendar: Calendar) -> Date {
        var cursor = calendar.startOfDay(for: date)
        var remaining = count
        let step = count >= 0 ? 1 : -1
        while remaining != 0 {
            cursor = calendar.date(byAdding: .day, value: step, to: cursor) ?? cursor
            let weekday = calendar.component(.weekday, from: cursor)
            if weekday != 1, weekday != 7 { remaining -= step }
        }
        return cursor
    }

    private func parseISO(_ text: String, context: CalculatorContext) -> Date? {
        if text.contains("T") {
            let formatter = ISO8601DateFormatter()
            formatter.formatOptions = [.withInternetDateTime]
            return formatter.date(from: text)
        }
        let parts = text.split(separator: "-")
        guard parts.count == 3, let year = Int(parts[0]), let month = Int(parts[1]), let day = Int(parts[2]) else { return nil }
        return context.calendar.date(from: DateComponents(year: year, month: month, day: day))
    }

    private func financeQuery(_ tokens: [Tok], context: CalculatorContext) -> CalculatorEvaluation? {
        let periods = compounding(in: tokens)
        if word(tokens, 0) == "mortgage" {
            guard case .num(let principal) = token(tokens, 1), word(tokens, 2) == "at",
                  case .num(let rate) = token(tokens, 3), token(tokens, 4) == .percent else { return nil }
            guard word(tokens, 5) == "for", case .num(let years) = token(tokens, 6) else {
                return .hint("For how many years?")
            }
            let payment = mortgagePayment(principal: principal, annualPercent: rate, years: years)
            let shown = format(payment, context: context, maximumFractionDigits: 2)
            return .value(CalculatorResult(
                displayText: shown,
                copyText: shown,
                context: "Monthly payment, \(plain(years)) years, \(plain(rate))% fixed"
            ))
        }
        if let invested = financeInvestment(tokens) {
            guard let years = invested.years else { return .hint("For how many years?") }
            let value = compound(
                principal: invested.principal,
                annualPercent: invested.rate,
                years: years,
                periods: periods
            )
            let shown = format(value, context: context, maximumFractionDigits: 2)
            let cadence = periods == 12 ? "monthly" : periods == 4 ? "quarterly" : "annual"
            return .value(CalculatorResult(
                displayText: shown,
                copyText: shown,
                context: "\(format(invested.principal, context: context)) at \(plain(invested.rate))% for \(plain(years)) years, \(cadence) compounding"
            ))
        }
        return nil
    }

    private func financeInvestment(_ tokens: [Tok]) -> (principal: Double, rate: Double, years: Double?)? {
        if case .num(let percent) = token(tokens, 0), token(tokens, 1) == .percent, word(tokens, 2) == "of",
           case .num(let base) = token(tokens, 3), word(tokens, 4) == "invested", word(tokens, 5) == "at",
           case .num(let rate) = token(tokens, 6), token(tokens, 7) == .percent {
            let years = word(tokens, 8) == "for" ? number(tokens, 9) : nil
            return (base * percent / 100, rate, years)
        }
        if case .num(let principal) = token(tokens, 0), word(tokens, 1) == "at",
           case .num(let rate) = token(tokens, 2), token(tokens, 3) == .percent {
            let years = word(tokens, 4) == "for" ? number(tokens, 5) : nil
            guard word(tokens, 4) == "for" || word(tokens, 4) == "invested" || tokens.count == 4 else { return nil }
            return (principal, rate, years)
        }
        return nil
    }

    private func compounding(in tokens: [Tok]) -> Double {
        guard let index = tokens.firstIndex(where: { if case .word(let word) = $0 { return word == "compounded" }; return false }) else {
            return 1
        }
        switch word(tokens, index + 1) {
        case "monthly", "month": return 12
        case "quarterly", "quarter": return 4
        case "daily", "day": return 365
        default: return 1
        }
    }

    private func compound(principal: Double, annualPercent: Double, years: Double, periods: Double) -> Double {
        let rate = annualPercent / 100 / periods
        return principal * Foundation.pow(1 + rate, periods * years)
    }

    private func mortgagePayment(principal: Double, annualPercent: Double, years: Double) -> Double {
        let payments = years * 12
        guard payments > 0 else { return principal }
        let monthly = annualPercent / 100 / 12
        if monthly == 0 { return principal / payments }
        let factor = Foundation.pow(1 + monthly, payments)
        return principal * monthly * factor / (factor - 1)
    }

    private func designQuery(_ tokens: [Tok], context: CalculatorContext) -> CalculatorEvaluation? {
        guard tokens.contains(where: isDesignToken) else { return nil }
        var tokens = tokens
        var ppi = context.pixelsPerInch
        var base = context.baseFontPixels
        if tokens.count >= 3, word(tokens, tokens.count - 3) == "at",
           case .num(let value) = token(tokens, tokens.count - 2) {
            if word(tokens, tokens.count - 1) == "ppi" { ppi = value; tokens.removeLast(3) }
            else if word(tokens, tokens.count - 1) == "px" { base = value; tokens.removeLast(3) }
        }
        guard let split = splitConversion(tokens), let target = designName(split.right),
              let inches = designInches(split.left, ppi: ppi, base: base, context: context),
              let result = designValue(inches, unit: target, ppi: ppi, base: base) else { return nil }
        let shown = format(result, context: context)
        let note = target == "em" || target == "rem" ? "\(plain(base))px base" : "\(plain(ppi)) ppi"
        return .value(CalculatorResult(displayText: "\(shown) \(target)", copyText: shown, context: note))
    }

    private func isDesignToken(_ token: Tok) -> Bool {
        guard case .word(let word) = token else { return false }
        return ["px", "pt", "em", "rem"].contains(word)
    }

    private func designName(_ tokens: [Tok]) -> String? {
        guard tokens.count == 1, case .word(let word) = tokens[0], ["px", "pt", "em", "rem"].contains(word) else { return nil }
        return word
    }

    private func designInches(_ tokens: [Tok], ppi: Double, base: Double, context: CalculatorContext) -> Double? {
        if let name = designName(Array(tokens.suffix(1))), case .num(let value) = tokens.first, tokens.count == 2 {
            return inches(from: value, unit: name, ppi: ppi, base: base)
        }
        guard let quantity = quantity(tokens), quantity.unit.dimension == "length" else { return nil }
        return quantity.value * quantity.unit.scale / 0.0254
    }

    private func inches(from value: Double, unit: String, ppi: Double, base: Double) -> Double? {
        switch unit {
        case "px": return ppi == 0 ? nil : value / ppi
        case "pt": return value / 72
        case "em", "rem": return ppi == 0 ? nil : value * base / ppi
        default: return nil
        }
    }

    private func designValue(_ inches: Double, unit: String, ppi: Double, base: Double) -> Double? {
        switch unit {
        case "px": return inches * ppi
        case "pt": return inches * 72
        case "em", "rem": return base == 0 ? nil : inches * ppi / base
        default: return nil
        }
    }

    private func baseQuery(_ tokens: [Tok], context: CalculatorContext) -> CalculatorEvaluation? {
        guard case .num(let value) = token(tokens, 0),
              word(tokens, 1) == "in" || word(tokens, 1) == "to",
              let name = word(tokens, 2), tokens.count == 3,
              let base = integerBase(name) else { return nil }
        guard let text = integerText(value, base: base) else { return .invalid }
        let label = base == 2 ? "binary" : base == 16 ? "hexadecimal" : "decimal"
        return .value(CalculatorResult(displayText: text, copyText: text, context: label))
    }

    private func integerBase(_ name: String) -> Int? {
        switch name {
        case "bin", "binary": 2
        case "hex", "hexadecimal": 16
        case "dec", "decimal": 10
        default: nil
        }
    }

    private func integerText(_ value: Double, base: Int) -> String? {
        guard abs(value.rounded() - value) < 0.000_001, abs(value) < Double(Int.max) else { return nil }
        return String(Int(value.rounded()), radix: base).uppercased()
    }

    private func localizeVolume(_ unit: CalculatorUnit, context: CalculatorContext) -> CalculatorUnit {
        let imperial = switch context.gallonChoice {
        case .imperial: true
        case .us: false
        case .automatic: ["GB", "IE"].contains(context.regionCode ?? "")
        }
        guard imperial else { return unit }
        switch unit.symbol {
        case "gal":
            return CalculatorUnit(dimension: "volume", symbol: "gal", scale: 4.54609, offset: 0)
        case "pt":
            return CalculatorUnit(dimension: "volume", symbol: "pt", scale: 0.56826125, offset: 0)
        case "cup":
            return CalculatorUnit(dimension: "volume", symbol: "cup", scale: 0.284130625, offset: 0)
        default:
            return unit
        }
    }

    private func conversionContext(source: CalculatorUnit, target: CalculatorUnit, prefix: Bool) -> String? {
        var notes: [String] = []
        if prefix { notes.append("Completed \(target.symbol)") }
        if [source.symbol, target.symbol].contains(where: { $0 == "year" || $0 == "month" }) {
            notes.append("Average year, 365.25 days")
        }
        for unit in [source, target] {
            let label: String?
            switch unit.symbol {
            case "gal": label = unit.scale > 4 ? "Imperial gallon" : "US gallon"
            case "pt": label = unit.scale > 0.5 ? "Imperial pint" : "US pint"
            case "cup": label = unit.scale > 0.25 ? "Imperial cup" : "US cup"
            default: label = nil
            }
            if let label, !notes.contains(label) { notes.append(label) }
        }
        return notes.isEmpty ? nil : notes.joined(separator: " · ")
    }

    private func trigContext(for query: String) -> String? {
        let lower = query.lowercased()
        guard lower.range(of: #"(?<![a-z])(a?sin|a?cos|a?tan|sind|cosd|tand)\s*\("#, options: .regularExpression) != nil else {
            return nil
        }
        if lower.contains("sind(") || lower.contains("cosd(") || lower.contains("tand(") { return "degrees" }
        return lower.contains("pi") ? "radians" : "degrees"
    }

    private func isBaseLiteral(_ query: String) -> Bool {
        let lower = query.lowercased()
        return lower.hasPrefix("0x") || lower.hasPrefix("0b")
    }

    private func number(_ tokens: [Tok], _ index: Int) -> Double? {
        if case .num(let value) = token(tokens, index) { return value }
        return nil
    }

    private func readSpecialLiteral(_ characters: [Character], index: inout Int) -> String? {
        let saved = index
        if let iso = readISOLiteral(characters, index: &index) { return iso }
        index = saved
        if let clock = readClockLiteral(characters, index: &index) { return clock }
        index = saved
        return nil
    }

    private func readISOLiteral(_ characters: [Character], index: inout Int) -> String? {
        func digits(_ count: Int) -> String? {
            guard index + count <= characters.count else { return nil }
            let slice = characters[index..<(index + count)]
            guard slice.allSatisfy(\.isNumber) else { return nil }
            index += count
            return String(slice)
        }
        func character(_ expected: Character) -> Bool {
            guard index < characters.count, characters[index] == expected else { return false }
            index += 1
            return true
        }
        guard let year = digits(4), character("-"), let month = digits(2), character("-"), let day = digits(2) else { return nil }
        var text = "iso:\(year)-\(month)-\(day)"
        if character("T") || character("t") {
            guard let hour = digits(2), character(":"), let minute = digits(2) else { return nil }
            text += "T\(hour):\(minute)"
            if character(":"), let second = digits(2) { text += ":\(second)" }
            if character("Z") || character("z") { text += "Z" }
        }
        return text
    }

    private func readClockLiteral(_ characters: [Character], index: inout Int) -> String? {
        let start = index
        while index < characters.count, characters[index].isNumber { index += 1 }
        let hourCount = index - start
        guard (1...2).contains(hourCount), index < characters.count, characters[index] == ":" else { return nil }
        index += 1
        let minuteStart = index
        while index < characters.count, characters[index].isNumber { index += 1 }
        guard index - minuteStart == 2 else { return nil }
        if index < characters.count, characters[index] == ":" {
            let saved = index
            index += 1
            let secondStart = index
            while index < characters.count, characters[index].isNumber { index += 1 }
            if index - secondStart != 2 { index = saved }
        }
        if index + 1 < characters.count {
            let marker = String(characters[index...index + 1]).lowercased()
            if marker == "am" || marker == "pm" { index += 2 }
        }
        return String(characters[start..<index]).lowercased()
    }

    // MARK: - Units

    private struct ResolvedUnit {
        var unit: CalculatorUnit
        var exact: Bool
    }

    private struct Quantity {
        var value: Double
        var unit: CalculatorUnit
    }

    private struct ConversionSplit {
        var left: [Tok]
        var right: [Tok]
        var connectorWasInches: Bool
    }

    private func splitConversion(_ tokens: [Tok]) -> ConversionSplit? {
        var connector: Int?
        for index in tokens.indices.reversed() {
            guard index > 0, index < tokens.count - 1, let word = word(tokens, index) else { continue }
            guard word == "to" || word == "in" || word == "into" else { continue }
            connector = index
            break
        }
        guard let connector else { return nil }
        return ConversionSplit(
            left: Array(tokens[..<connector]),
            right: Array(tokens[(connector + 1)...]),
            connectorWasInches: word(tokens, connector) == "in"
        )
    }

    private func reversedUnit(_ tokens: [Tok]) -> (amount: Double, source: CalculatorUnit, target: CalculatorUnit)? {
        guard let target = resolveUnit(Array(tokens.prefix(2)), dimension: nil, allowPrefix: false)?.unit else { return nil }
        let rest = Array(tokens.dropFirst(targetWordCount(tokens)))
        guard word(rest, 0) == "in" || word(rest, 0) == "to", let quantity = quantity(Array(rest.dropFirst())) else { return nil }
        return (quantity.value, quantity.unit, target)
    }

    private func quantity(_ tokens: [Tok]) -> Quantity? {
        guard !tokens.isEmpty else { return nil }
        if let unit = resolveUnit(Array(tokens.suffix(2)), dimension: nil, allowPrefix: false)
            ?? resolveUnit(Array(tokens.suffix(1)), dimension: nil, allowPrefix: false) {
            let used = unitWordCount(Array(tokens.suffix(2)), unit: unit.unit)
            let head = Array(tokens.dropLast(used))
            if head.isEmpty { return nil }
            if head.count == 1, case .num(let value) = head[0] {
                return Quantity(value: value, unit: unit.unit)
            }
            if let value = evaluate(head, context: CalculatorContext()) {
                return Quantity(value: value, unit: unit.unit)
            }
            if let mixed = mixedQuantity(tokens) { return mixed }
        }
        return mixedQuantity(tokens)
    }

    private func mixedQuantity(_ tokens: [Tok]) -> Quantity? {
        var index = 0
        var base = 0.0
        var last: CalculatorUnit?
        while index < tokens.count {
            guard case .num(let value) = tokens[index] else { return nil }
            let resolved = resolveUnit(Array(tokens.dropFirst(index + 1).prefix(2)), dimension: last?.dimension, allowPrefix: false)
            guard let resolved else { return nil }
            if let last, last.dimension != resolved.unit.dimension || last.offset != 0 { return nil }
            base += value * resolved.unit.scale + resolved.unit.offset
            last = resolved.unit
            index += 1 + unitWordCount(Array(tokens.dropFirst(index + 1)), unit: resolved.unit)
        }
        guard let last, last.scale != 0 else { return nil }
        return Quantity(value: (base - last.offset) / last.scale, unit: last)
    }

    private func resolveUnit(_ tokens: [Tok], dimension: String?, allowPrefix: Bool) -> ResolvedUnit? {
        let words = tokens.compactMap { token -> String? in
            if case .word(let word) = token { return word }
            return nil
        }
        guard words.count == tokens.count, !words.isEmpty else { return nil }
        if words.count >= 2, let unit = CalculatorLexicon.unit(named: "\(words[0]) \(words[1])") {
            if let dimension, unit.dimension != dimension { return nil }
            return ResolvedUnit(unit: unit, exact: true)
        }
        if let unit = CalculatorLexicon.unit(named: words[0]), words.count == 1 {
            if let dimension, unit.dimension != dimension { return nil }
            return ResolvedUnit(unit: unit, exact: true)
        }
        guard allowPrefix, words.count == 1 else { return nil }
        guard let unit = CalculatorLexicon.uniqueUnit(prefixedBy: words[0], dimension: dimension) else { return nil }
        return ResolvedUnit(unit: unit, exact: false)
    }

    private func unitWordCount(_ tokens: [Tok], unit: CalculatorUnit) -> Int {
        if tokens.count >= 2, let two = resolveUnit(Array(tokens.prefix(2)), dimension: nil, allowPrefix: false),
           two.unit.symbol == unit.symbol { return 2 }
        return 1
    }

    private func targetWordCount(_ tokens: [Tok]) -> Int {
        if resolveUnit(Array(tokens.prefix(2)), dimension: nil, allowPrefix: false) != nil,
           tokens.count >= 2, word(tokens, 1) != "in", word(tokens, 1) != "to" { return 2 }
        return 1
    }

    private func convert(
        amount: Double,
        from source: CalculatorUnit,
        to target: CalculatorUnit,
        context: CalculatorContext,
        claimed: Bool,
        prefix: Bool = false
    ) -> CalculatorEvaluation {
        let source = localizeVolume(source, context: context)
        let target = localizeVolume(target, context: context)
        guard let converted = source.converted(amount, to: target) else {
            return claimed ? .invalid : .notExpression
        }
        let amountText = format(amount, context: context)
        let convertedText = format(converted, context: context)
        let display = "\(amountText) \(source.symbol) = \(convertedText) \(target.symbol)"
        return .value(CalculatorResult(
            displayText: display,
            copyText: convertedText,
            context: conversionContext(source: source, target: target, prefix: prefix)
        ))
    }

    private func timespan(_ seconds: Double) -> String {
        let total = Int(seconds.rounded())
        let sign = total < 0 ? "-" : ""
        let absolute = abs(total)
        let hours = absolute / 3600
        let minutes = (absolute % 3600) / 60
        let secs = absolute % 60
        var parts: [String] = []
        if hours > 0 { parts.append("\(hours) h") }
        if minutes > 0 { parts.append("\(minutes) min") }
        if secs > 0 || parts.isEmpty { parts.append("\(secs) s") }
        return sign + parts.joined(separator: " ")
    }

    // MARK: - Time and dates

    private struct Clock {
        var hour: Int
        var minute: Int
        var next: Int
    }

    private struct PlaceSpan {
        var place: CalculatorPlace
        var next: Int
        var ambiguous: [CalculatorPlace]
    }

    private func takeClock(_ tokens: [Tok], from index: Int) -> Clock? {
        if let word = word(tokens, index), word.contains(":"), !word.hasPrefix("iso:") {
            return clock(from: word, next: index + 1)
        }
        guard case .num(let value) = token(tokens, index) else { return nil }
        var hour = Int(value)
        var minute = 0
        var next = index + 1
        if value != Double(hour) { return nil }
        if let word = word(tokens, next), word.contains(":"), let parsed = minutePair(word) {
            hour = parsed.hour
            minute = parsed.minute
            next += 1
        }
        if let marker = word(tokens, next), marker == "am" || marker == "pm" {
            if hour == 12 { hour = marker == "am" ? 0 : 12 }
            else if marker == "pm", hour < 12 { hour += 12 }
            next += 1
        } else if hour > 24 {
            return nil
        }
        guard (0...23).contains(hour), (0...59).contains(minute) else { return nil }
        return Clock(hour: hour, minute: minute, next: next)
    }

    private func minutePair(_ word: String) -> (hour: Int, minute: Int)? {
        let parts = word.split(separator: ":")
        guard parts.count == 2, let hour = Int(parts[0]), let minute = Int(parts[1]) else { return nil }
        return (hour, minute)
    }

    private func takePlace(_ tokens: [Tok], from index: Int, context: CalculatorContext) -> PlaceSpan? {
        let words = (index..<min(index + 3, tokens.count)).compactMap { word(tokens, $0) }
        guard !words.isEmpty else { return nil }
        for length in stride(from: words.count, through: 1, by: -1) {
            let name = words.prefix(length).joined(separator: " ")
            switch CalculatorPlaces.resolve(name, regionCode: context.regionCode) {
            case .match(let place):
                return PlaceSpan(place: place, next: index + length, ambiguous: [])
            case .ambiguous(let places):
                guard let first = places.first else { return nil }
                return PlaceSpan(place: first, next: index + length, ambiguous: places)
            case .none:
                continue
            }
        }
        return nil
    }

    private func convertClock(
        _ clock: Clock,
        from source: PlaceSpan,
        to target: PlaceSpan,
        context: CalculatorContext
    ) -> CalculatorEvaluation {
        if !source.ambiguous.isEmpty || !target.ambiguous.isEmpty {
            let choices = (target.ambiguous.isEmpty ? [target.place] : target.ambiguous).prefix(3).compactMap { place -> CalculatorResult? in
                guard let text = convertedClock(clock, from: source.place, to: place, context: context) else { return nil }
                return CalculatorResult(displayText: text.time, copyText: text.time, context: text.line, presentsInline: false)
            }
            return choices.isEmpty ? .invalid : .choices(Array(choices))
        }
        guard let text = convertedClock(clock, from: source.place, to: target.place, context: context) else { return .invalid }
        return .value(CalculatorResult(displayText: text.time, copyText: text.time, context: text.line))
    }

    private func convertedClock(
        _ clock: Clock,
        from source: CalculatorPlace,
        to target: CalculatorPlace,
        context: CalculatorContext
    ) -> (time: String, line: String)? {
        guard let sourceZone = TimeZone(identifier: source.timeZoneIdentifier),
              let targetZone = TimeZone(identifier: target.timeZoneIdentifier) else { return nil }
        var calendar = context.calendar
        calendar.timeZone = sourceZone
        var parts = calendar.dateComponents([.year, .month, .day], from: context.now)
        parts.hour = clock.hour
        parts.minute = clock.minute
        guard let instant = calendar.date(from: parts) else { return nil }
        let time = formatTime(instant, zone: targetZone, context: context)
        let sourceTime = formatTime(instant, zone: sourceZone, context: context)
        let abbreviation = sourceZone.abbreviation(for: instant).map { " (\($0))" } ?? ""
        return (time, "\(sourceTime) in \(source.label)\(abbreviation) → \(target.label)")
    }

    private func renderPlaceTime(
        _ place: PlaceSpan,
        at date: Date,
        context: CalculatorContext,
        prefix: String
    ) -> CalculatorEvaluation {
        guard let zone = TimeZone(identifier: place.place.timeZoneIdentifier) else { return .invalid }
        let time = formatTime(date, zone: zone, context: context)
        let abbreviation = zone.abbreviation(for: date).map { " (\($0))" } ?? ""
        return .value(CalculatorResult(displayText: time, copyText: time, context: "\(prefix) \(place.place.label)\(abbreviation)"))
    }

    private func timeDifference(_ place: PlaceSpan, context: CalculatorContext) -> CalculatorEvaluation {
        guard let zone = TimeZone(identifier: place.place.timeZoneIdentifier) else { return .invalid }
        let delta = zone.secondsFromGMT(for: context.now) - context.timeZone.secondsFromGMT(for: context.now)
        let ahead = delta >= 0
        let text = timespan(Double(abs(delta)))
        let relation = ahead ? "ahead of you" : "behind you"
        return .value(CalculatorResult(
            displayText: text,
            copyText: text,
            context: "\(place.place.label) is \(text) \(relation)"
        ))
    }

    private func clockResult(_ date: Date, zone: TimeZone, context: CalculatorContext, contextLine: String) -> CalculatorResult {
        let time = formatTime(date, zone: zone, context: context)
        return CalculatorResult(displayText: time, copyText: time, context: contextLine)
    }

    private func takeDate(_ tokens: [Tok], from index: Int, context: CalculatorContext) -> Date? {
        let calendar = context.calendar
        let year = calendar.component(.year, from: context.now)
        if let monthWord = word(tokens, index), let month = months[monthWord], case .num(let day) = token(tokens, index + 1) {
            return calendar.date(from: DateComponents(year: year, month: month, day: Int(day)))
        }
        if case .num(let day) = token(tokens, index), let monthWord = word(tokens, index + 1), let month = months[monthWord] {
            var year = year
            if case .num(let explicit) = token(tokens, index + 2), explicit >= 1900, explicit < 10_000 {
                year = Int(explicit)
            }
            return calendar.date(from: DateComponents(year: year, month: month, day: Int(day)))
        }
        return nil
    }

    private func dateTokenCount(_ tokens: [Tok], from index: Int) -> Int {
        if word(tokens, index).flatMap({ months[$0] }) != nil { return index + 2 }
        if case .num = token(tokens, index), word(tokens, index + 1).flatMap({ months[$0] }) != nil {
            if case .num(let year) = token(tokens, index + 2), year >= 1900 { return index + 3 }
            return index + 2
        }
        return index
    }

    private func nextWeekday(_ weekday: Int, after date: Date, calendar: Calendar, weeks: Int) -> Date {
        var next = calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: date)) ?? date
        while calendar.component(.weekday, from: next) != weekday {
            next = calendar.date(byAdding: .day, value: 1, to: next) ?? next
        }
        if weeks > 1 {
            next = calendar.date(byAdding: .weekOfYear, value: weeks - 1, to: next) ?? next
        }
        return next
    }

    // MARK: - Currency and percents

    private struct CurrencyParse {
        var amount: Double
        var source: String
        var target: String?
    }

    private func parseCurrency(_ tokens: [Tok], context: CalculatorContext) -> CurrencyParse? {
        var amount: Double?
        var codes: [String] = []
        var sawConnector = false
        for token in tokens {
            switch token {
            case .num(let value):
                if amount == nil { amount = value } else { return nil }
            case .word(let word):
                if word == "to" || word == "in" || word == "into" {
                    sawConnector = true
                    continue
                }
                if let code = currencyCode(word, confirmed: sawConnector || !codes.isEmpty, rates: context.rates) {
                    codes.append(code)
                } else if word != "currency" {
                    return nil
                }
            default:
                return nil
            }
        }
        guard let amount, let source = codes.first else { return nil }
        return CurrencyParse(amount: amount, source: source, target: codes.dropFirst().first)
    }

    private func currencyCode(_ word: String, confirmed: Bool, rates: CurrencyRateSnapshot?) -> String? {
        if let known = CalculatorCurrencies.knownAlias(word) { return known }
        guard confirmed, word.count == 3, word.allSatisfy(\.isLetter) else { return nil }
        let code = word.uppercased()
        guard let rates, rates.base == code || rates.rates[code] != nil else { return nil }
        return code
    }

    private func percentValue(
        _ value: Double,
        context: CalculatorContext,
        line: String,
        suffix: String = ""
    ) -> CalculatorEvaluation {
        let shown = format(value, context: context) + suffix
        return .value(CalculatorResult(displayText: shown, copyText: shown, context: line))
    }

    private func percentHint(_ tokens: [Tok]) -> String {
        if case .num(let value) = token(tokens, 1) { return plain(value) }
        if case .num(let value) = token(tokens, 0) { return plain(value) }
        return ""
    }

    private func taxWord(_ word: String?) -> String? {
        guard let word, ["vat", "gst", "tax", "tip"].contains(word) else { return nil }
        return word.uppercased()
    }

    // MARK: - Expression

    private enum Tok: Equatable {
        case num(Double)
        case word(String)
        case plus, minus, mul, div, pow, percent, lparen, rparen, comma
    }

    private struct Parser {
        var tokens: [Tok]
        var index = 0
        var context: CalculatorContext

        mutating func parse() throws -> Double {
            let value = try additive()
            guard current == nil, value.isFinite else { throw ParseError.invalid }
            return value
        }

        private var current: Tok? { index < tokens.count ? tokens[index] : nil }
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
                case .mul:
                    advance()
                    value *= try unary()
                case .div:
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
            if current == .pow {
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
            while current == .lparen || current == .num(0) || isImplicitOperand(current) {
                if current == .num(0) { break }
                value *= try primary()
            }
            return value
        }

        private func isImplicitOperand(_ token: Tok?) -> Bool {
            switch token {
            case .num, .lparen: return true
            case .word(let word): return ["pi", "e", "ans"].contains(word)
            default: return false
            }
        }

        private mutating func primary() throws -> Double {
            switch current {
            case .num(let value):
                advance()
                return value
            case .word(let identifier):
                advance()
                if identifier == "pi" { return .pi }
                if identifier == "e" { return M_E }
                if identifier == "ans" {
                    guard let lastAnswer = context.lastAnswer else { throw ParseError.invalid }
                    return lastAnswer
                }
                guard current == .lparen else { throw ParseError.invalid }
                advance()
                let radians = nextArgumentContainsPi()
                let first = try additive()
                if current == .comma {
                    advance()
                    let second = try additive()
                    guard current == .rparen else { throw ParseError.invalid }
                    advance()
                    return try apply(function: identifier, to: first, and: second)
                }
                guard current == .rparen else { throw ParseError.invalid }
                advance()
                return try apply(function: identifier, to: first, radians: radians)
            case .lparen:
                advance()
                let value = try additive()
                guard current == .rparen else { throw ParseError.invalid }
                advance()
                return value
            default:
                throw ParseError.invalid
            }
        }

        private func nextArgumentContainsPi() -> Bool {
            var depth = 0
            var cursor = index
            while cursor < tokens.count {
                switch tokens[cursor] {
                case .lparen:
                    depth += 1
                case .rparen:
                    if depth == 0 { return false }
                    depth -= 1
                case .word(let word) where word == "pi":
                    return true
                default:
                    break
                }
                cursor += 1
            }
            return false
        }

        private func apply(function: String, to value: Double, radians: Bool = false) throws -> Double {
            let result: Double
            switch function {
            case "sqrt": result = Foundation.sqrt(value)
            case "sin": result = trig(value, radians: radians) { Foundation.sin($0) }
            case "cos": result = trig(value, radians: radians) { Foundation.cos($0) }
            case "tan": result = trig(value, radians: radians) { Foundation.tan($0) }
            case "asin": result = inverseTrig(Foundation.asin(value), radians: radians)
            case "acos": result = inverseTrig(Foundation.acos(value), radians: radians)
            case "atan": result = inverseTrig(Foundation.atan(value), radians: radians)
            case "sind": result = Foundation.sin(value * .pi / 180)
            case "cosd": result = Foundation.cos(value * .pi / 180)
            case "tand": result = Foundation.tan(value * .pi / 180)
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

        private func trig(_ value: Double, radians: Bool, _ function: (Double) -> Double) -> Double {
            let radiansValue = radians ? value : value * .pi / 180
            return snap(function(radiansValue))
        }

        private func inverseTrig(_ radiansValue: Double, radians: Bool) -> Double {
            snap(radians ? radiansValue : radiansValue * 180 / .pi)
        }

        private func snap(_ value: Double) -> Double {
            let nearest = value.rounded()
            return abs(value - nearest) < 0.000_000_001 ? nearest : value
        }

        private func apply(function: String, to first: Double, and second: Double) throws -> Double {
            switch function {
            case "gcd":
                guard let result = CalculatorEngine.integerGCD(first, second) else { throw ParseError.invalid }
                return result
            case "lcm":
                guard let divisor = CalculatorEngine.integerGCD(first, second), divisor != 0 else { throw ParseError.invalid }
                return abs(first.rounded() * second.rounded()) / divisor
            case "mod":
                guard second != 0 else { throw ParseError.invalid }
                return first.truncatingRemainder(dividingBy: second)
            default:
                throw ParseError.invalid
            }
        }
    }

    private enum ParseError: Error { case invalid }

    private func evaluate(_ tokens: [Tok], context: CalculatorContext) -> Double? {
        var parser = Parser(tokens: tokens, context: context)
        return try? parser.parse()
    }

    private static func integerGCD(_ first: Double, _ second: Double) -> Double? {
        guard abs(first.rounded() - first) < 0.000_001, abs(second.rounded() - second) < 0.000_001 else { return nil }
        var a = Int(first.rounded())
        var b = Int(second.rounded())
        while b != 0 {
            let remainder = a % b
            a = b
            b = remainder
        }
        return Double(abs(a))
    }

    private func isConfident(_ query: String, tokens: [Tok]) -> Bool {
        if query.range(of: #"[+*/×÷^%]"#, options: .regularExpression) != nil,
           query.rangeOfCharacter(from: .decimalDigits) != nil { return true }
        if query.range(of: #"[0-9)]\s*[+\-−*/×÷^%]\s*[0-9(]"#, options: .regularExpression) != nil { return true }
        if tokens.contains(where: { [.plus, .mul, .div, .pow, .percent].contains($0) }) { return true }
        let functions = ["sqrt", "sin", "cos", "tan", "asin", "acos", "atan", "log", "ln", "abs", "floor", "ceil", "round", "sind", "cosd", "tand", "gcd", "lcm", "mod"]
        if tokens.contains(where: { token in
            if case .word(let word) = token { return functions.contains(word) }
            return false
        }) { return true }
        if tokens.count >= 2, case .num = tokens[0], case .word(let word) = tokens[1], ["pi", "e"].contains(word) {
            return true
        }
        return false
    }

    private func isIncomplete(_ query: String, tokens: [Tok]) -> Bool {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        if let last = trimmed.unicodeScalars.last, CharacterSet(charactersIn: "+-−*/×÷^").contains(last) { return true }
        var balance = 0
        for token in tokens {
            if token == .lparen { balance += 1 }
            if token == .rparen {
                balance -= 1
                if balance < 0 { return false }
            }
        }
        if balance > 0 { return true }
        let lower = trimmed.lowercased()
        return lower.hasSuffix(" in") || lower.hasSuffix(" to") || lower.hasSuffix(" into")
    }

    // MARK: - Lexing

    private func lex(_ query: String, locale: Locale) -> [Tok] {
        let characters = Array(query)
        let decimal = Character(locale.decimalSeparator ?? ".")
        let grouping = Character(locale.groupingSeparator ?? ",")
        var tokens: [Tok] = []
        var index = 0
        while index < characters.count {
            let character = characters[index]
            if character.isWhitespace { index += 1; continue }
            if "$€£¥₹".contains(character) {
                tokens.append(.word(String(character)))
                index += 1
                continue
            }
            if let literal = readSpecialLiteral(characters, index: &index) {
                tokens.append(.word(literal))
                continue
            }
            if character.isNumber || character == decimal {
                guard let number = readNumber(characters, index: &index, decimal: decimal, grouping: grouping) else { return [] }
                tokens.append(.num(number.value))
                if number.gluedSuffix != nil, let suffix = number.gluedSuffix {
                    appendSuffix(suffix, original: number.originalSuffix, to: &tokens)
                }
                continue
            }
            if character.isLetter || character == "°" {
                let start = index
                index += 1
                while index < characters.count {
                    let next = characters[index]
                    if next.isLetter || next == "°" || next.isNumber { index += 1; continue }
                    if next == "/", index + 1 < characters.count, characters[index + 1].isLetter { index += 1; continue }
                    break
                }
                let word = String(characters[start..<index])
                if word.contains(":"), word.split(separator: ":").count == 2 {
                    tokens.append(.word(word.lowercased()))
                } else {
                    tokens.append(.word(CalculatorLexicon.normalize(word)))
                }
                continue
            }
            switch character {
            case "+": tokens.append(.plus)
            case "-", "−": tokens.append(.minus)
            case "*", "×": tokens.append(.mul)
            case "/", "÷": tokens.append(.div)
            case "^": tokens.append(.pow)
            case "%": tokens.append(.percent)
            case "(": tokens.append(.lparen)
            case ")": tokens.append(.rparen)
            case ",": tokens.append(.comma)
            default: return []
            }
            index += 1
        }
        return rewriteWords(tokens)
    }

    private struct ScannedNumber {
        var value: Double
        var gluedSuffix: String?
        var originalSuffix: String
    }

    private func readNumber(
        _ characters: [Character],
        index: inout Int,
        decimal: Character,
        grouping: Character
    ) -> ScannedNumber? {
        if characters[index] == "0", index + 1 < characters.count, characters[index + 1] == "x" || characters[index + 1] == "X" {
            index += 2
            let start = index
            while index < characters.count, characters[index].isHexDigit { index += 1 }
            guard let value = Int(String(characters[start..<index]), radix: 16) else { return nil }
            return ScannedNumber(value: Double(value), gluedSuffix: nil, originalSuffix: "")
        }
        if characters[index] == "0", index + 1 < characters.count, characters[index + 1] == "b" || characters[index + 1] == "B" {
            index += 2
            let start = index
            while index < characters.count, characters[index] == "0" || characters[index] == "1" { index += 1 }
            guard start < index, let value = Int(String(characters[start..<index]), radix: 2) else { return nil }
            return ScannedNumber(value: Double(value), gluedSuffix: nil, originalSuffix: "")
        }
        let start = index
        var text = ""
        var sawDecimal = false
        while index < characters.count {
            let next = characters[index]
            if next.isNumber {
                text.append(next)
                index += 1
                continue
            }
            if next == grouping, grouping != decimal, index + 3 < characters.count,
               characters[(index + 1)...(index + 3)].allSatisfy(\.isNumber),
               index + 4 >= characters.count || !characters[index + 4].isNumber {
                index += 4
                text.append(contentsOf: characters[(index - 3)..<index])
                continue
            }
            if next == decimal, !sawDecimal {
                sawDecimal = true
                text.append(".")
                index += 1
                continue
            }
            break
        }
        guard let value = Double(text), start < index else { return nil }
        if index < characters.count, characters[index].isLetter {
            let suffixStart = index
            while index < characters.count, characters[index].isLetter { index += 1 }
            let original = String(characters[suffixStart..<index])
            return ScannedNumber(value: value, gluedSuffix: original.lowercased(), originalSuffix: original)
        }
        return ScannedNumber(value: value, gluedSuffix: nil, originalSuffix: "")
    }

    private func appendSuffix(_ suffix: String, original: String, to tokens: inout [Tok]) {
        if original.count == 1, original == "M" {
            if case .num(let value) = tokens.last {
                tokens[tokens.count - 1] = .num(value * 1_000_000)
                return
            }
        }
        if original.count == 1, original == "B" {
            if case .num(let value) = tokens.last {
                tokens[tokens.count - 1] = .num(value * 1_000_000_000)
                return
            }
        }
        if CalculatorLexicon.unit(named: suffix) != nil || suffix.contains("/") {
            tokens.append(.word(CalculatorLexicon.normalize(suffix)))
            return
        }
        if suffix == "k", case .num(let value) = tokens.last {
            tokens[tokens.count - 1] = .num(value * 1_000)
            return
        }
        tokens.append(.word(suffix))
    }

    private func rewriteWords(_ tokens: [Tok]) -> [Tok] {
        tokens.map { token in
            guard case .word(let word) = token else { return token }
            switch word {
            case "plus": return .plus
            case "minus": return .minus
            case "times", "x": return .mul
            case "over": return token
            default: return token
            }
        }
    }

    private func stripFiller(_ tokens: [Tok]) -> [Tok] {
        let filler: Set<String> = ["what", "is", "whats", "what's", "calculate", "convert", "how", "many", "much", "please", "the"]
        var index = 0
        while index < tokens.count {
            guard case .word(let word) = tokens[index], filler.contains(word) else { break }
            index += 1
        }
        return Array(tokens.dropFirst(index))
    }

    private func normalizeEquals(in rawQuery: String) -> (expression: String, explicitlyRequested: Bool)? {
        let equalsIndices = rawQuery.indices.filter { rawQuery[$0] == "=" }
        guard equalsIndices.count <= 1 else { return nil }
        guard let equalsIndex = equalsIndices.first else { return (rawQuery, false) }
        let before = rawQuery[..<equalsIndex]
        let after = rawQuery[rawQuery.index(after: equalsIndex)...]
        let beforeTrimmed = before.trimmingCharacters(in: .whitespacesAndNewlines)
        let afterTrimmed = after.trimmingCharacters(in: .whitespacesAndNewlines)
        let isBoundary = beforeTrimmed.isEmpty || afterTrimmed.isEmpty
        let operators = CharacterSet(charactersIn: "+-−*/×÷^%")
        let isBesideOperator = beforeTrimmed.unicodeScalars.last.map(operators.contains) == true
            || afterTrimmed.unicodeScalars.first.map(operators.contains) == true
        guard isBoundary || isBesideOperator else { return nil }
        let expression = String(before + after).trimmingCharacters(in: .whitespacesAndNewlines)
        return (expression, true)
    }

    private func mightCalculate(_ raw: String) -> Bool {
        if raw.contains(where: \.isNumber) { return true }
        if raw.contains(where: { "$€£¥₹=(".contains($0) }) { return true }
        let hints: Set<String> = ["time", "today", "tomorrow", "yesterday", "now", "date", "days", "next"]
        let words = raw.lowercased().split(whereSeparator: \.isWhitespace).map(String.init)
        return words.contains(where: { hints.contains($0) })
    }

    // MARK: - Formatting

    private func format(_ value: Double, context: CalculatorContext, maximumFractionDigits: Int? = nil) -> String {
        FormatterBox.shared.string(
            value,
            locale: context.locale,
            maximumSignificantDigits: context.maximumSignificantDigits,
            usesGroupingSeparator: context.usesGroupingSeparator,
            maximumFractionDigits: maximumFractionDigits
        )
    }

    private func formatTime(_ date: Date, zone: TimeZone, context: CalculatorContext) -> String {
        let formatter = DateFormatter()
        formatter.locale = context.locale
        formatter.timeZone = zone
        formatter.dateStyle = .none
        formatter.timeStyle = .short
        return formatter.string(from: date)
    }

    private func formatDate(_ date: Date, context: CalculatorContext) -> String {
        let formatter = DateFormatter()
        formatter.locale = context.locale
        formatter.timeZone = context.timeZone
        formatter.dateStyle = .medium
        formatter.timeStyle = .none
        return formatter.string(from: date)
    }

    private func shortRateDate(_ providerDate: String, context: CalculatorContext) -> String {
        let parser = DateFormatter()
        parser.calendar = Calendar(identifier: .gregorian)
        parser.locale = Locale(identifier: "en_US_POSIX")
        parser.timeZone = TimeZone(secondsFromGMT: 0)
        parser.dateFormat = "yyyy-MM-dd"
        guard let date = parser.date(from: providerDate) else { return providerDate }
        let formatter = DateFormatter()
        formatter.locale = context.locale
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.setLocalizedDateFormatFromTemplate("d MMM")
        return formatter.string(from: date)
    }

    private func plain(_ value: Double) -> String {
        if value.rounded() == value, abs(value) < 1_000_000_000_000 { return String(Int(value)) }
        return String(value)
    }

    private func token(_ tokens: [Tok], _ index: Int) -> Tok? {
        tokens.indices.contains(index) ? tokens[index] : nil
    }

    private func word(_ tokens: [Tok], _ index: Int) -> String? {
        if case .word(let word) = token(tokens, index) { return word }
        return nil
    }

    private func durationSeconds(_ amount: Double, unitWord: String) -> Double? {
        switch unitWord {
        case "hour", "hours", "hr", "hrs", "h": return amount * 3_600
        case "minute", "minutes", "min", "mins": return amount * 60
        case "second", "seconds", "sec", "s": return amount
        case "day", "days": return amount * 86_400
        default: return nil
        }
    }

    private func dayWord(_ word: String) -> Int? {
        switch word {
        case "today", "now": return 0
        case "tomorrow": return 1
        case "yesterday": return -1
        default: return nil
        }
    }

    private func dateComponent(_ word: String) -> Calendar.Component? {
        switch word {
        case "day", "days": return .day
        case "week", "weeks": return .weekOfYear
        case "month", "months": return .month
        case "year", "years": return .year
        default: return nil
        }
    }

    private let months = [
        "jan": 1, "january": 1, "feb": 2, "february": 2, "mar": 3, "march": 3,
        "apr": 4, "april": 4, "may": 5, "jun": 6, "june": 6, "jul": 7, "july": 7,
        "aug": 8, "august": 8, "sep": 9, "sept": 9, "september": 9, "oct": 10, "october": 10,
        "nov": 11, "november": 11, "dec": 12, "december": 12
    ]

    private let weekdays = [
        "sunday": 1, "monday": 2, "tuesday": 3, "wednesday": 4, "thursday": 5, "friday": 6, "saturday": 7
    ]
}

private extension CalculatorContext {
    var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        calendar.locale = locale
        return calendar
    }

    var withoutGrouping: CalculatorContext {
        var copy = self
        copy.usesGroupingSeparator = false
        return copy
    }
}

private final class FormatterBox: @unchecked Sendable {
    static let shared = FormatterBox()
    private let lock = NSLock()
    private var storage: [Key: NumberFormatter] = [:]

    func string(
        _ value: Double,
        locale: Locale,
        maximumSignificantDigits: Int,
        usesGroupingSeparator: Bool,
        maximumFractionDigits: Int?
    ) -> String {
        let key = Key(
            locale: locale.identifier,
            digits: min(12, max(1, maximumSignificantDigits)),
            grouping: usesGroupingSeparator,
            fraction: maximumFractionDigits ?? -1
        )
        lock.lock()
        defer { lock.unlock() }
        let formatter = storage[key] ?? {
            let formatter = NumberFormatter()
            formatter.locale = locale
            formatter.numberStyle = .decimal
            formatter.usesGroupingSeparator = usesGroupingSeparator
            if let maximumFractionDigits {
                formatter.minimumFractionDigits = maximumFractionDigits
                formatter.maximumFractionDigits = maximumFractionDigits
            } else {
                formatter.maximumSignificantDigits = key.digits
                formatter.minimumSignificantDigits = 1
            }
            storage[key] = formatter
            return formatter
        }()
        return formatter.string(from: NSNumber(value: value)) ?? String(value)
    }

    private struct Key: Hashable {
        var locale: String
        var digits: Int
        var grouping: Bool
        var fraction: Int
    }
}
