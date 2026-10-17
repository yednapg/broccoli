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
}
