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
}
