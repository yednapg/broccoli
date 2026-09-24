import AppKit
import XCTest
@testable import BroccoliApp

final class CalculatorCapabilityLayoutTests: XCTestCase {
    func testEveryCapabilitySymbolFitsTheSharedColumn() throws {
        let configuration = NSImage.SymbolConfiguration(
            pointSize: CalculatorSettingsPane.capabilitySymbolPointSize,
            weight: .regular
        )
        let symbols = CalculatorSettingsPane.capabilityColumns.flatMap { $0.map(\.symbol) }

        for symbol in symbols {
            let image = NSImage(systemSymbolName: symbol, accessibilityDescription: nil)?
                .withSymbolConfiguration(configuration)
            let width = try XCTUnwrap(image).size.width
            XCTAssertLessThanOrEqual(
                width,
                CalculatorSettingsPane.capabilitySymbolColumn,
                "\(symbol) is wider than the column, so it would push its title off the shared line"
            )
        }
    }
}
