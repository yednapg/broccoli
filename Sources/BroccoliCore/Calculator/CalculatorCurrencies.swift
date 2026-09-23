import Foundation

enum CalculatorCurrencies {
    static func code(for token: String) -> String? {
        let key = token.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
        if let code = aliases[key] { return code }
        let upper = key.uppercased()
        if upper.count == 3, upper.allSatisfy(\.isLetter) { return upper }
        return nil
    }

    static func knownAlias(_ token: String) -> String? {
        aliases[token.lowercased()]
    }

    static func name(for code: String) -> String {
        names[code.uppercased()] ?? code.uppercased()
    }

    static func symbol(for code: String) -> String {
        symbols[code.uppercased()] ?? code.uppercased()
    }

    private static let aliases: [String: String] = [
        "$": "USD", "usd": "USD", "us$": "USD", "dollar": "USD", "dollars": "USD", "us dollar": "USD", "us dollars": "USD",
        "€": "EUR", "eur": "EUR", "euro": "EUR", "euros": "EUR",
        "£": "GBP", "gbp": "GBP", "pound": "GBP", "pounds": "GBP", "sterling": "GBP",
        "¥": "JPY", "jpy": "JPY", "yen": "JPY",
        "₹": "INR", "inr": "INR", "rupee": "INR", "rupees": "INR",
        "cny": "CNY", "yuan": "CNY", "rmb": "CNY",
        "cad": "CAD", "aud": "AUD", "chf": "CHF", "nzd": "NZD", "sek": "SEK", "nok": "NOK",
        "dkk": "DKK", "sgd": "SGD", "hkd": "HKD", "krw": "KRW", "aed": "AED", "sar": "SAR",
        "zar": "ZAR", "brl": "BRL", "mxn": "MXN", "try": "TRY", "rub": "RUB", "thb": "THB",
        "idr": "IDR", "myr": "MYR", "php": "PHP", "pln": "PLN", "czk": "CZK", "huf": "HUF"
    ]

    private static let names: [String: String] = [
        "USD": "US dollars", "EUR": "euros", "GBP": "pounds", "JPY": "yen", "INR": "rupees",
        "CNY": "yuan", "CAD": "Canadian dollars", "AUD": "Australian dollars", "CHF": "francs"
    ]

    private static let symbols: [String: String] = [
        "USD": "US$", "EUR": "€", "GBP": "£", "JPY": "JP¥", "INR": "₹", "CNY": "CN¥",
        "CAD": "C$", "AUD": "A$", "CHF": "CHF"
    ]
}
