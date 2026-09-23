import XCTest
@testable import BroccoliCore

final class CalculatorEngineTests: XCTestCase {
    private let calculator = CalculatorEngine()
    private let locale = Locale(identifier: "en_US_POSIX")

    func testArithmeticPrecedenceAndPower() {
        XCTAssertEqual(calculator.evaluate("2 + 3 * 4", locale: locale)?.copyText, "14")
        XCTAssertEqual(calculator.evaluate("2 ^ 3 ^ 2", locale: locale)?.copyText, "512")
        XCTAssertEqual(calculator.evaluate("(2 + 3) * 4", locale: locale)?.copyText, "20")
    }

    func testScientificFunctionsAndConstants() {
        XCTAssertEqual(calculator.evaluate("sqrt(144)", locale: locale)?.copyText, "12")
        XCTAssertEqual(calculator.evaluate("round(pi)", locale: locale)?.copyText, "3")
        XCTAssertEqual(calculator.evaluate("abs(-42)", locale: locale)?.copyText, "42")
    }

    func testPercentAndExplicitExpression() {
        XCTAssertEqual(calculator.evaluate("50% * 200", locale: locale)?.copyText, "100")
        XCTAssertEqual(calculator.evaluate("= 42", locale: locale)?.copyText, "42")
        XCTAssertNil(calculator.evaluate("42", locale: locale))
    }

    func testOneAccidentalEqualsAtAnExpressionBoundaryIsAccepted() {
        XCTAssertEqual(calculator.evaluate("10 + 1 =", locale: locale)?.copyText, "11")
        XCTAssertEqual(calculator.evaluate("10 += 1", locale: locale)?.copyText, "11")
        XCTAssertEqual(calculator.evaluate("= 10 + 1", locale: locale)?.copyText, "11")
    }

    func testEqualsInsideOperandsOrRepeatedEqualsIsInvalid() {
        XCTAssertEqual(calculator.classify("1 = 1", locale: locale), .invalid)
        XCTAssertEqual(calculator.classify("10 + 1 ==", locale: locale), .invalid)
    }

    func testLengthAndTemperatureConversions() {
        XCTAssertEqual(calculator.evaluate("10 km in mi", locale: locale)?.copyText, "6.21371192237")
        XCTAssertEqual(calculator.evaluate("32 f in c", locale: locale)?.copyText, "0")
        XCTAssertEqual(calculator.evaluate("100 c to f", locale: locale)?.copyText, "212")
    }

    func testOtherUnitFamilies() {
        XCTAssertEqual(calculator.evaluate("1 hour in min", locale: locale)?.copyText, "60")
        XCTAssertEqual(calculator.evaluate("1 gb in mb", locale: locale)?.copyText, "1000")
        XCTAssertEqual(calculator.evaluate("1 acre in m2", locale: locale)?.copyText, "4046.8564224")
        XCTAssertEqual(calculator.evaluate("60 mph in km/h", locale: locale)?.copyText, "96.56064")
    }

    func testInvalidInputDoesNotProduceResult() {
        XCTAssertNil(calculator.evaluate("hello world", locale: locale))
        XCTAssertNil(calculator.evaluate("1 / 0", locale: locale))
        XCTAssertNil(calculator.evaluate("sqrt(-1)", locale: locale))
        XCTAssertNil(calculator.evaluate("10 kg in km", locale: locale))
    }

    func testIncompleteExpressionClassification() {
        XCTAssertTrue(calculator.looksLikeIncompleteExpression("2 +"))
        XCTAssertTrue(calculator.looksLikeIncompleteExpression("= sqrt("))
        XCTAssertFalse(calculator.looksLikeIncompleteExpression("visual studio code"))
        XCTAssertFalse(calculator.looksLikeIncompleteExpression("version 2"))
        XCTAssertEqual(calculator.classify("2 +", locale: locale), .incomplete)
        XCTAssertEqual(calculator.classify("2 + )", locale: locale), .invalid)
    }

    func testGluedUnitsBareQuantitiesAndPercentPhrases() {
        XCTAssertNotNil(calculator.evaluate("10cm to in", locale: locale))
        XCTAssertNotNil(calculator.evaluate("10 cm", locale: locale))
        XCTAssertEqual(calculator.evaluate("18% of 2400", locale: locale)?.copyText, "432")
        XCTAssertEqual(calculator.evaluate("2400 + 18%", locale: locale)?.copyText, "2832")
        guard case .choices(let options) = calculator.classify("20% 100", locale: locale) else {
            return XCTFail("Expected a choice")
        }
        XCTAssertEqual(options.count, 2)
    }

    func testGermanyEveningConvertsToIndiaStandardTime() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let now = calendar.date(from: DateComponents(year: 2026, month: 9, day: 23, hour: 12))!
        let context = CalculatorContext(
            now: now,
            timeZone: TimeZone(identifier: "Asia/Kolkata")!,
            locale: Locale(identifier: "en_US"),
            regionCode: "IN"
        )
        guard case .value(let result) = calculator.classify("5pm germany to ist", context: context) else {
            return XCTFail("Expected a time conversion")
        }
        XCTAssertTrue(result.copyText.contains("8:30") || result.copyText.contains("20:30"), result.copyText)
        XCTAssertTrue(result.context?.contains("India Standard Time") == true, result.context ?? "")
    }

    func testCurrencyUsesTheSuppliedRateAndRejectsInventedModelNumbers() {
        let rates = CurrencyRateSnapshot(
            base: "USD",
            rates: ["USD": 1, "INR": Decimal(string: "95.66")!],
            providerDate: "2026-09-23",
            fetchedAt: Date(timeIntervalSince1970: 1_758_643_200),
            sourceName: "Frankfurter"
        )
        let context = CalculatorContext(
            now: Date(timeIntervalSince1970: 1_758_643_200),
            locale: locale,
            homeCurrencyCode: "INR",
            rates: rates
        )
        guard case .value(let result) = calculator.classify("100 usd in inr", context: context) else {
            return XCTFail("Expected a currency conversion")
        }
        XCTAssertTrue(result.copyText.contains("9566"), result.copyText)
        XCTAssertNil(CalculatorProposalValidator.canonicalQuery(
            kind: "unit",
            numbers: [50],
            source: "cm",
            target: "in",
            operation: "",
            originalQuery: "10cm to inches"
        ))
        XCTAssertEqual(
            CalculatorProposalValidator.canonicalQuery(
                kind: "unit",
                numbers: [10],
                source: "cm",
                target: "in",
                operation: "",
                originalQuery: "10cm to inches"
            ),
            "10 cm in in"
        )
    }

    func testFormattingPreferencesAndLocale() {
        let result = calculator.evaluate(
            "1000000 / 3",
            locale: Locale(identifier: "en_US"),
            maximumSignificantDigits: 6,
            usesGroupingSeparator: true
        )
        XCTAssertEqual(result?.displayText, "333,333")

        let ungrouped = calculator.evaluate(
            "1000 + 1",
            locale: Locale(identifier: "en_US"),
            maximumSignificantDigits: 12,
            usesGroupingSeparator: false
        )
        XCTAssertEqual(ungrouped?.copyText, "1001")
    }

    func testDegreesRadiansBinaryDurationsAndGallons() {
        XCTAssertEqual(calculator.evaluate("sin(90)", locale: locale)?.copyText, "1")
        XCTAssertEqual(calculator.evaluate("sin(pi / 2)", locale: locale)?.copyText, "1")
        XCTAssertEqual(calculator.classify("sin(90)", locale: locale), .value(CalculatorResult(displayText: "1", copyText: "1", context: "degrees")))
        XCTAssertEqual(calculator.evaluate("0b1010", locale: locale)?.copyText, "10")
        XCTAssertEqual(calculator.evaluate("255 in bin", locale: locale)?.copyText, "11111111")
        XCTAssertEqual(calculator.evaluate("0xFF in hex", locale: locale)?.copyText, "FF")
        let hours = calculator.evaluate("10 years in hours", locale: locale)
        XCTAssertEqual(hours?.copyText, "87660")
        XCTAssertEqual(hours?.context, "Average year, 365.25 days")

        let imperial = CalculatorContext(locale: locale, regionCode: "GB")
        XCTAssertEqual(calculator.classify("1 gallon in l", context: imperial), .value(CalculatorResult(
            displayText: "1 gal = 4.54609 L",
            copyText: "4.54609",
            context: "Imperial gallon"
        )))
        guard case .value(let usGallon) = calculator.classify("1 us gallon in l", context: imperial) else {
            return XCTFail("Expected a US gallon conversion")
        }
        XCTAssertEqual(usGallon.copyText, "3.785411784")
    }

    func testClockCalendarDesignAndInterest() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let now = calendar.date(from: DateComponents(year: 2026, month: 9, day: 23, hour: 12))!
        let context = CalculatorContext(
            now: now,
            timeZone: TimeZone(secondsFromGMT: 0)!,
            locale: Locale(identifier: "en_US")
        )
        let shifted = calculator.classify("3:45pm + 2 hours", context: context)
        guard case .value(let clock) = shifted else { return XCTFail("\(shifted)") }
        XCTAssertTrue(clock.copyText.contains("5:45"), clock.copyText)

        let iso = calculator.classify("2024-03-15T14:30:00Z", context: context)
        guard case .value(let stamp) = iso else { return XCTFail("\(iso)") }
        XCTAssertTrue(stamp.context?.contains("2024-03-15") == true)

        XCTAssertEqual(calculator.evaluate("2 inches in px at 72 ppi", locale: locale)?.copyText, "144")
        XCTAssertEqual(calculator.evaluate("12px in em", locale: locale)?.copyText, "0.75")
        XCTAssertEqual(calculator.evaluate("1000 at 7% for 3 years", locale: locale)?.copyText, "1225.04")

        let mortgage = calculator.evaluate("mortgage 400000 at 6.5% for 30 years", locale: locale)
        let payment = Double(mortgage?.copyText ?? "")
        XCTAssertEqual(payment ?? 0, 2528.27, accuracy: 0.02)
        XCTAssertEqual(calculator.classify("1000 at 7%", locale: locale), .hint("For how many years?"))
    }
}
