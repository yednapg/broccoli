import Foundation

public enum CurrencyRateFreshness: Equatable, Sendable {
    case current
    case stale
    case missing
}

public struct CurrencyRateSnapshot: Codable, Equatable, Sendable {
    public var base: String
    public var rates: [String: Decimal]
    public var providerDate: String
    public var fetchedAt: Date
    public var sourceName: String

    public init(
        base: String,
        rates: [String: Decimal],
        providerDate: String,
        fetchedAt: Date,
        sourceName: String
    ) {
        self.base = base.uppercased()
        self.rates = rates
        self.providerDate = providerDate
        self.fetchedAt = fetchedAt
        self.sourceName = sourceName
    }

    public func freshness(now: Date, calendar: Calendar = .current) -> CurrencyRateFreshness {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "yyyy-MM-dd"
        guard let published = formatter.date(from: providerDate) else { return .stale }
        let startNow = calendar.startOfDay(for: now)
        let startRate = calendar.startOfDay(for: published)
        let days = calendar.dateComponents([.day], from: startRate, to: startNow).day ?? 99
        if days <= 1 { return .current }
        let weekday = calendar.component(.weekday, from: startNow)
        if days <= 3, weekday == 1 || weekday == 2 || weekday == 7 { return .current }
        return .stale
    }

    public func convert(_ amount: Decimal, from source: String, to target: String) -> Decimal? {
        let source = source.uppercased()
        let target = target.uppercased()
        guard let sourceRate = rate(source), let targetRate = rate(target), sourceRate != 0 else { return nil }
        return amount / sourceRate * targetRate
    }

    private func rate(_ code: String) -> Decimal? {
        if code == base { return 1 }
        return rates[code]
    }
}

public enum CurrencyRateDecoding {
    public static func frankfurter(_ data: Data, fetchedAt: Date) -> CurrencyRateSnapshot? {
        struct Row: Decodable {
            let date: String
            let base: String
            let quote: String
            let rate: Decimal
        }
        guard let rows = try? JSONDecoder().decode([Row].self, from: data), let first = rows.first else {
            return nil
        }
        var rates: [String: Decimal] = [first.base.uppercased(): 1]
        for row in rows where row.rate > 0 {
            rates[row.quote.uppercased()] = row.rate
        }
        guard rates.count > 1 else { return nil }
        return CurrencyRateSnapshot(
            base: first.base,
            rates: rates,
            providerDate: first.date,
            fetchedAt: fetchedAt,
            sourceName: "Frankfurter"
        )
    }

    public static func fawazahmed(_ data: Data, fetchedAt: Date) -> CurrencyRateSnapshot? {
        guard let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let date = object["date"] as? String else { return nil }
        let table = object.first { $0.key != "date" }?.value as? [String: Any]
        guard let table else { return nil }
        var rates: [String: Decimal] = [:]
        for (key, value) in table {
            let number: Decimal?
            if let double = value as? Double, double > 0, double.isFinite {
                number = Decimal(double)
            } else if let string = value as? String, let decimal = Decimal(string: string), decimal > 0 {
                number = decimal
            } else {
                number = nil
            }
            if let number { rates[key.uppercased()] = number }
        }
        let base = object.keys.first { $0 != "date" }?.uppercased() ?? "USD"
        rates[base] = 1
        guard rates.count > 1 else { return nil }
        return CurrencyRateSnapshot(
            base: base,
            rates: rates,
            providerDate: date,
            fetchedAt: fetchedAt,
            sourceName: "currency-api"
        )
    }

    public static func accepting(
        _ incoming: CurrencyRateSnapshot,
        replacing existing: CurrencyRateSnapshot?
    ) -> CurrencyRateSnapshot? {
        guard incoming.rates.values.allSatisfy({ $0 > 0 }) else { return nil }
        guard let existing else { return incoming }
        for code in ["EUR", "GBP", "JPY", "INR"] {
            guard let previous = existing.rates[code], let next = incoming.rates[code], previous != 0 else { continue }
            let change = abs((next - previous) / previous)
            if change > Decimal(string: "0.5")! { return nil }
        }
        return incoming
    }
}

public actor CurrencyRateStore {
    private let fileURL: URL
    private let version = 1

    public init(fileURL: URL) {
        self.fileURL = fileURL
    }

    public func load() -> CurrencyRateSnapshot? {
        guard let data = try? Data(contentsOf: fileURL) else { return nil }
        guard let file = try? JSONDecoder().decode(File.self, from: data), file.version == version else {
            return nil
        }
        return file.snapshot
    }

    public func save(_ snapshot: CurrencyRateSnapshot) {
        let file = File(version: version, snapshot: snapshot)
        guard let data = try? JSONEncoder().encode(file) else { return }
        try? FileManager.default.createDirectory(
            at: fileURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try? data.write(to: fileURL, options: .atomic)
    }

    private struct File: Codable {
        var version: Int
        var snapshot: CurrencyRateSnapshot
    }
}
