import XCTest
@testable import BroccoliCore

final class WebSearchTests: XCTestCase {
    func testQueryIsTrimmedAndEncodedSoGoogleReceivesItLiterally() throws {
        XCTAssertEqual(
            try XCTUnwrap(WebSearch.googleURL(for: "  c++ & rust = fun  ")).absoluteString,
            "https://www.google.com/search?q=c%2B%2B%20%26%20rust%20%3D%20fun"
        )
        XCTAssertEqual(
            try XCTUnwrap(WebSearch.googleURL(for: "café 50%")).absoluteString,
            "https://www.google.com/search?q=caf%C3%A9%2050%25"
        )
    }

    func testBlankQueryHasNoWebSearch() {
        XCTAssertNil(WebSearch.googleURL(for: "   "))
        XCTAssertNil(WebSearch.googleEntry(for: ""))
    }

    func testDuckDuckGoUsesItsOwnAddressAndAFixedIdentity() throws {
        let entry = try XCTUnwrap(WebSearch.entry(for: "c++ tutorial", engine: .duckDuckGo))
        XCTAssertEqual(entry.id, WebSearch.duckDuckGoEntryID)
        XCTAssertEqual(entry.iconKey, WebSearch.duckDuckGoIconKey)
        XCTAssertEqual(entry.title, "Search DuckDuckGo for “c++ tutorial”")
        guard case .webSearch(let url) = entry.target else {
            return XCTFail("DuckDuckGo must open a web search")
        }
        XCTAssertEqual(url.absoluteString, "https://duckduckgo.com/?q=c%2B%2B%20tutorial")
        XCTAssertFalse(entry.id.contains("tutorial"))
    }

    func testANumberBeingTypedIsNotReadyForAWebSearch() {
        XCTAssertTrue(WebSearch.isCalculationInProgress("3"))
        XCTAssertTrue(WebSearch.isCalculationInProgress(" 3.14 "))
        XCTAssertFalse(WebSearch.isCalculationInProgress("3+1"))
        XCTAssertFalse(WebSearch.isCalculationInProgress("2 + )"))
    }

    func testEntryIdentityNeverContainsTheQuery() throws {
        let entry = try XCTUnwrap(WebSearch.googleEntry(for: "private words"))
        XCTAssertEqual(entry.id, WebSearch.googleEntryID)
        XCTAssertEqual(entry.iconKey, WebSearch.googleIconKey)
        XCTAssertEqual(entry.kind, .webSearch)
        XCTAssertEqual(entry.title, "Search Google for “private words”")
        XCTAssertFalse(entry.id.contains("private"))
        XCTAssertFalse(entry.iconKey.contains("private"))
    }
}
