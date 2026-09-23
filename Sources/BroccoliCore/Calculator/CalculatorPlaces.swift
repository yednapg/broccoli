import Foundation

struct CalculatorPlace: Equatable, Sendable {
    var timeZoneIdentifier: String
    var label: String
}

enum CalculatorPlaceMatch: Equatable, Sendable {
    case match(CalculatorPlace)
    case ambiguous([CalculatorPlace])
    case none
}

enum CalculatorPlaces {
    static func resolve(_ name: String, regionCode: String?) -> CalculatorPlaceMatch {
        let key = name.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
        guard !key.isEmpty, !connectors.contains(key) else { return .none }
        if let airport = CalculatorAirports.aliases[key],
           TimeZone(identifier: airport.identifier) != nil {
            return .match(CalculatorPlace(timeZoneIdentifier: airport.identifier, label: airport.label))
        }
        if let hits = abbreviations[key] {
            return pick(hits, regionCode: regionCode)
        }
        if let country = countries[key] {
            return .match(country)
        }
        if let identifier = cities[key] {
            let label = key.split(separator: " ").map { $0.capitalized }.joined(separator: " ")
            return .match(CalculatorPlace(timeZoneIdentifier: identifier, label: label))
        }
        return .none
    }

    private static func pick(_ hits: [Abbreviation], regionCode: String?) -> CalculatorPlaceMatch {
        let region = regionCode?.uppercased()
        if let region, let match = hits.first(where: { $0.regions.contains(region) }) {
            return .match(match.place)
        }
        let places = hits.map(\.place)
        if places.count == 1 { return .match(places[0]) }
        return places.isEmpty ? .none : .ambiguous(places)
    }

    private struct Abbreviation {
        var place: CalculatorPlace
        var regions: Set<String>
    }

    private static let connectors: Set<String> = ["to", "in", "into", "at", "from", "on", "of"]

    private static let cities: [String: String] = {
        var result: [String: String] = [:]
        for identifier in TimeZone.knownTimeZoneIdentifiers {
            guard let city = identifier.split(separator: "/").last else { continue }
            let name = city.replacingOccurrences(of: "_", with: " ").lowercased()
            if result[name] == nil { result[name] = identifier }
        }
        return result
    }()

    private static let abbreviations: [String: [Abbreviation]] = {
        var result: [String: [Abbreviation]] = [:]
        func add(_ key: String, _ identifier: String, _ label: String, _ regions: [String] = []) {
            result[key, default: []].append(
                Abbreviation(
                    place: CalculatorPlace(timeZoneIdentifier: identifier, label: label),
                    regions: Set(regions)
                )
            )
        }
        add("ist", "Asia/Kolkata", "India Standard Time", ["IN"])
        add("ist", "Europe/Dublin", "Irish Standard Time", ["IE"])
        add("ist", "Asia/Jerusalem", "Israel Standard Time", ["IL"])
        add("pst", "America/Los_Angeles", "Pacific Time", ["US", "CA"])
        add("pdt", "America/Los_Angeles", "Pacific Time", ["US", "CA"])
        add("est", "America/New_York", "Eastern Time", ["US", "CA"])
        add("edt", "America/New_York", "Eastern Time", ["US", "CA"])
        add("cst", "America/Chicago", "Central Time", ["US", "CA"])
        add("cdt", "America/Chicago", "Central Time", ["US", "CA"])
        add("mst", "America/Denver", "Mountain Time", ["US", "CA"])
        add("gmt", "GMT", "Greenwich Mean Time")
        add("utc", "GMT", "Coordinated Universal Time")
        add("cet", "Europe/Berlin", "Central European Time", ["DE", "FR", "NL", "IT", "ES"])
        add("cest", "Europe/Berlin", "Central European Time", ["DE", "FR", "NL", "IT", "ES"])
        add("jst", "Asia/Tokyo", "Japan Standard Time", ["JP"])
        add("bst", "Europe/London", "United Kingdom", ["GB"])
        add("aest", "Australia/Sydney", "Australian Eastern Time", ["AU"])
        add("nzst", "Pacific/Auckland", "New Zealand", ["NZ"])
        return result
    }()

    private static let countries: [String: CalculatorPlace] = {
        var result: [String: CalculatorPlace] = [:]
        let lines = """
        germany Europe/Berlin Germany
        india Asia/Kolkata India
        japan Asia/Tokyo Japan
        france Europe/Paris France
        italy Europe/Rome Italy
        spain Europe/Madrid Spain
        portugal Europe/Lisbon Portugal
        netherlands Europe/Amsterdam Netherlands
        belgium Europe/Brussels Belgium
        switzerland Europe/Zurich Switzerland
        austria Europe/Vienna Austria
        sweden Europe/Stockholm Sweden
        norway Europe/Oslo Norway
        denmark Europe/Copenhagen Denmark
        finland Europe/Helsinki Finland
        poland Europe/Warsaw Poland
        greece Europe/Athens Greece
        ireland Europe/Dublin Ireland
        uk Europe/London United Kingdom
        britain Europe/London United Kingdom
        england Europe/London United Kingdom
        scotland Europe/London United Kingdom
        usa America/New_York United States
        america America/New_York United States
        canada America/Toronto Canada
        mexico America/Mexico_City Mexico
        brazil America/Sao_Paulo Brazil
        argentina America/Argentina/Buenos_Aires Argentina
        australia Australia/Sydney Australia
        new zealand Pacific/Auckland New Zealand
        china Asia/Shanghai China
        taiwan Asia/Taipei Taiwan
        singapore Asia/Singapore Singapore
        malaysia Asia/Kuala_Lumpur Malaysia
        thailand Asia/Bangkok Thailand
        vietnam Asia/Ho_Chi_Minh Vietnam
        indonesia Asia/Jakarta Indonesia
        philippines Asia/Manila Philippines
        korea Asia/Seoul South Korea
        uae Asia/Dubai United Arab Emirates
        dubai Asia/Dubai Dubai
        israel Asia/Jerusalem Israel
        turkey Europe/Istanbul Turkey
        egypt Africa/Cairo Egypt
        nigeria Africa/Lagos Nigeria
        kenya Africa/Nairobi Kenya
        russia Europe/Moscow Russia
        ukraine Europe/Kyiv Ukraine
        """
        for line in lines.split(separator: "\n") {
            let parts = line.split(separator: " ", omittingEmptySubsequences: true).map(String.init)
            guard parts.count >= 3 else { continue }
            let label = parts.dropFirst(2).joined(separator: " ")
            result[parts[0]] = CalculatorPlace(timeZoneIdentifier: parts[1], label: label)
        }
        result["united kingdom"] = CalculatorPlace(timeZoneIdentifier: "Europe/London", label: "United Kingdom")
        result["united states"] = CalculatorPlace(timeZoneIdentifier: "America/New_York", label: "United States")
        result["new zealand"] = CalculatorPlace(timeZoneIdentifier: "Pacific/Auckland", label: "New Zealand")
        result["south korea"] = CalculatorPlace(timeZoneIdentifier: "Asia/Seoul", label: "South Korea")
        result["hong kong"] = CalculatorPlace(timeZoneIdentifier: "Asia/Hong_Kong", label: "Hong Kong")
        result["saudi arabia"] = CalculatorPlace(timeZoneIdentifier: "Asia/Riyadh", label: "Saudi Arabia")
        result["south africa"] = CalculatorPlace(timeZoneIdentifier: "Africa/Johannesburg", label: "South Africa")
        return result
    }()
}
