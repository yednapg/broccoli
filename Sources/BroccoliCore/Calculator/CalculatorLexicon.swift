import Foundation

struct CalculatorUnit: Equatable, Sendable {
    let dimension: String
    let symbol: String
    let scale: Double
    let offset: Double

    func converted(_ value: Double, to target: CalculatorUnit) -> Double? {
        guard dimension == target.dimension else { return nil }
        let base = value * scale + offset
        let result = (base - target.offset) / target.scale
        return result.isFinite ? result : nil
    }
}

enum CalculatorLexicon {
    private static let units: [String: CalculatorUnit] = {
        var result: [String: CalculatorUnit] = [:]
        func add(
            _ dimension: String,
            _ symbol: String,
            _ scale: Double,
            _ aliases: [String],
            offset: Double = 0
        ) {
            let unit = CalculatorUnit(dimension: dimension, symbol: symbol, scale: scale, offset: offset)
            for alias in aliases { result[alias] = unit }
        }

        add("length", "m", 1, ["m", "meter", "meters", "metre", "metres"])
        add("length", "km", 1_000, ["km", "kilometer", "kilometers", "kilometre", "kilometres"])
        add("length", "cm", 0.01, ["cm", "centimeter", "centimeters", "centimetre", "centimetres"])
        add("length", "mm", 0.001, ["mm", "millimeter", "millimeters", "millimetre", "millimetres"])
        add("length", "mi", 1_609.344, ["mi", "mile", "miles"])
        add("length", "yd", 0.9144, ["yd", "yard", "yards"])
        add("length", "ft", 0.3048, ["ft", "foot", "feet"])
        add("length", "in", 0.0254, ["in", "inch", "inches"])
        add("length", "nmi", 1_852, ["nmi", "nautical mile", "nautical miles"])

        add("area", "m²", 1, ["m2", "sqm", "sq m"])
        add("area", "km²", 1_000_000, ["km2", "sqkm", "sq km"])
        add("area", "cm²", 0.0001, ["cm2", "sqcm"])
        add("area", "ft²", 0.09290304, ["ft2", "sqft", "sq ft"])
        add("area", "in²", 0.00064516, ["in2", "sqin", "sq in"])
        add("area", "acre", 4_046.8564224, ["acre", "acres"])
        add("area", "ha", 10_000, ["ha", "hectare", "hectares"])

        add("volume", "L", 1, ["l", "liter", "liters", "litre", "litres"])
        add("volume", "mL", 0.001, ["ml", "milliliter", "milliliters", "millilitre", "millilitres"])
        add("volume", "m³", 1_000, ["m3"])
        add("volume", "cm³", 0.001, ["cm3"])
        add("volume", "gal", 3.785411784, ["gal", "gallon", "gallons"])
        add("volume", "US gal", 3.785411784, ["us gal", "usgal", "us gallon", "us gallons"])
        add("volume", "qt", 0.946352946, ["qt", "quart", "quarts"])
        add("volume", "pt", 0.473176473, ["pt", "pint", "pints"])
        add("volume", "US pt", 0.473176473, ["us pt", "us pint", "us pints"])
        add("volume", "cup", 0.2365882365, ["cup", "cups"])
        add("volume", "US cup", 0.2365882365, ["us cup", "us cups"])
        add("volume", "imperial cup", 0.284130625, ["imperial cup", "imperial cups", "uk cup", "uk cups"])
        add("volume", "fl oz", 0.0295735295625, ["fl oz", "floz", "fluid ounce", "fluid ounces"])
        add("volume", "uk gal", 4.54609, ["uk gal", "ukgal", "imperial gallon", "imperial gallons"])
        add("volume", "uk pt", 0.56826125, ["uk pt", "ukpt", "imperial pint", "imperial pints"])
        add("volume", "tsp", 0.00492892159375, ["tsp", "teaspoon", "teaspoons"])
        add("volume", "tbsp", 0.01478676478125, ["tbsp", "tablespoon", "tablespoons"])

        add("mass", "kg", 1, ["kg", "kilogram", "kilograms"])
        add("mass", "g", 0.001, ["g", "gram", "grams"])
        add("mass", "mg", 0.000001, ["mg", "milligram", "milligrams"])
        add("mass", "lb", 0.45359237, ["lb", "lbs", "pound", "pounds"])
        add("mass", "oz", 0.028349523125, ["oz", "ounce", "ounces"])
        add("mass", "t", 1_000, ["t", "tonne", "tonnes"])
        add("mass", "st", 6.35029318, ["st", "stone", "stones"])

        add("temperature", "°C", 1, ["c", "°c", "celsius", "celcius", "centigrade"])
        add("temperature", "°F", 5.0 / 9.0, ["f", "°f", "fahrenheit", "farenheit"], offset: -32 * 5.0 / 9.0)
        add("temperature", "K", 1, ["k", "kelvin"], offset: -273.15)

        add("time", "s", 1, ["s", "sec", "second", "seconds"])
        add("time", "min", 60, ["min", "mins", "minute", "minutes"])
        add("time", "h", 3_600, ["h", "hr", "hrs", "hour", "hours"])
        add("time", "day", 86_400, ["day", "days"])
        add("time", "week", 604_800, ["week", "weeks"])
        add("time", "year", 31_557_600, ["year", "years", "yr", "yrs"])
        add("time", "month", 2_629_800, ["month", "months", "mo"])

        add("speed", "m/s", 1, ["m/s", "mps"])
        add("speed", "km/h", 1 / 3.6, ["km/h", "kph", "kmh"])
        add("speed", "mph", 0.44704, ["mph"])
        add("speed", "kn", 0.514444, ["kn", "knot", "knots"])

        add("angle", "rad", 1, ["rad", "radian", "radians"])
        add("angle", "°", .pi / 180, ["deg", "degree", "degrees"])

        add("pressure", "Pa", 1, ["pa", "pascal", "pascals"])
        add("pressure", "kPa", 1_000, ["kpa", "kilopascal"])
        add("pressure", "bar", 100_000, ["bar"])
        add("pressure", "mbar", 100, ["mbar", "millibar"])
        add("pressure", "psi", 6_894.757, ["psi"])

        add("energy", "J", 1, ["j", "joule", "joules"])
        add("energy", "kJ", 1_000, ["kj", "kilojoule"])
        add("energy", "cal", 4.184, ["cal", "calorie", "calories"])
        add("energy", "kcal", 4_184, ["kcal"])
        add("energy", "Wh", 3_600, ["wh", "watt hour"])
        add("energy", "kWh", 3_600_000, ["kwh", "kilowatt hour"])

        add("power", "W", 1, ["w", "watt", "watts"])
        add("power", "kW", 1_000, ["kw", "kilowatt"])
        add("power", "hp", 745.7, ["hp", "horsepower"])

        add("data", "B", 1, ["b", "byte", "bytes"])
        add("data", "KB", 1_000, ["kb"])
        add("data", "MB", 1_000_000, ["mb"])
        add("data", "GB", 1_000_000_000, ["gb"])
        add("data", "TB", 1_000_000_000_000, ["tb"])
        add("data", "PB", 1_000_000_000_000_000, ["pb"])
        add("data", "bit", 0.125, ["bit", "bits"])
        add("data", "KiB", 1_024, ["kib"])
        add("data", "MiB", 1_048_576, ["mib"])
        add("data", "GiB", 1_073_741_824, ["gib"])
        add("data", "TiB", 1_099_511_627_776, ["tib"])
        return result
    }()

    private static let prefixes: [String: [String]] = {
        var result: [String: [String]] = [:]
        for alias in units.keys {
            var prefix = ""
            for character in alias {
                prefix.append(character)
                result[prefix, default: []].append(alias)
            }
        }
        return result
    }()

    static let alternateSymbol: [String: String] = [
        "m": "ft", "ft": "m", "km": "mi", "mi": "km", "cm": "in", "in": "cm", "mm": "in",
        "kg": "lb", "lb": "kg", "g": "oz", "oz": "g", "°C": "°F", "°F": "°C",
        "km/h": "mph", "mph": "km/h", "L": "gal", "gal": "L", "mL": "fl oz", "fl oz": "mL",
        "kPa": "psi", "psi": "kPa", "m/s": "mph"
    ]

    static func unit(named name: String) -> CalculatorUnit? {
        units[normalize(name)]
    }

    static func uniqueUnit(prefixedBy name: String, dimension: String?) -> CalculatorUnit? {
        let key = normalize(name)
        guard !key.isEmpty, let aliases = prefixes[key] else { return nil }
        let matches = aliases.compactMap { alias -> CalculatorUnit? in
            guard let unit = units[alias] else { return nil }
            if let dimension, unit.dimension != dimension { return nil }
            return unit
        }
        let symbols = Set(matches.map(\.symbol))
        guard symbols.count == 1 else { return nil }
        return matches[0]
    }

    static func normalize(_ name: String) -> String {
        name.lowercased()
            .replacingOccurrences(of: "²", with: "2")
            .replacingOccurrences(of: "³", with: "3")
            .replacingOccurrences(of: "°", with: "")
            .replacingOccurrences(of: "^", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
