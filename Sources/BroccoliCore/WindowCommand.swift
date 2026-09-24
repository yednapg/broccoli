import Foundation

/// A window size in points or as a share of the usable display.
public enum WindowDimension: Codable, Hashable, Sendable {
    case points(Double)
    case percent(Double)

    public static let pointRange: ClosedRange<Double> = 50...20_000
    public static let percentRange: ClosedRange<Double> = 5...100

    public var sanitized: WindowDimension {
        switch self {
        case .points(let value):
            .points(value.isFinite ? min(max(value, Self.pointRange.lowerBound), Self.pointRange.upperBound) : 800)
        case .percent(let value):
            .percent(value.isFinite ? min(max(value, Self.percentRange.lowerBound), Self.percentRange.upperBound) : 50)
        }
    }

    public var displayText: String {
        switch self {
        case .points(let value): Self.format(value)
        case .percent(let value): "\(Self.format(value))%"
        }
    }

    var identifier: String {
        switch self {
        case .points(let value): "\(Self.format(value))pt"
        case .percent(let value): "\(Self.format(value))pct"
        }
    }

    init?(identifier: String) {
        if identifier.hasSuffix("pct"), let value = Double(identifier.dropLast(3)) {
            self = .percent(value)
        } else if identifier.hasSuffix("pt"), let value = Double(identifier.dropLast(2)) {
            self = .points(value)
        } else {
            return nil
        }
    }

    static func format(_ value: Double) -> String {
        value.rounded() == value ? String(Int(value)) : String(format: "%.1f", value)
    }
}
