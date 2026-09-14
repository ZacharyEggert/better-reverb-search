import XCTest

/// The four screens App Review touched, driven through the real UI. Deliberately
/// offline: none of these searches reach Reverb, so they spend no quota and can't
/// flake on the network.
@MainActor
final class SmokeUITests: XCTestCase {
    override func setUp() {
        continueAfterFailure = false
    }

    private func launch() -> XCUIApplication {
        let app = XCUIApplication()
        app.launch()
        return app
    }

    /// The hint `SearchQuery.emptyHint` shows. Duplicated rather than imported —
    /// UI tests run in their own process, and this is the string a user reads.
    private let emptyHint = "Enter a search term first"

    /// A CI simulator is slow enough that the first tap can land before the
    /// field will take focus, and `typeText` then fails outright rather than
    /// waiting. Tap until focus sticks.
    private func tapUntilFocused(_ field: XCUIElement) {
        let focused = NSPredicate(format: "hasKeyboardFocus == true")
        for _ in 0..<3 {
            field.tap()
            let check = XCTNSPredicateExpectation(predicate: focused, object: field)
            if XCTWaiter().wait(for: [check], timeout: 3) == .completed { return }
        }
        XCTFail("The search field never took keyboard focus")
    }

    func testSubmittingAnEmptySearchExplainsWhatIsMissing() {
        let app = launch()
        let field = app.searchFields.firstMatch
        XCTAssertTrue(field.waitForExistence(timeout: 10))
        tapUntilFocused(field)
        // A space, so the Return key is live on an otherwise empty field — and
        // whitespace has to read as empty anyway.
        field.typeText(" \n")

        XCTAssertTrue(
            app.staticTexts.containing(NSPredicate(format: "label CONTAINS %@", emptyHint))
                .firstMatch.waitForExistence(timeout: 5),
            "An empty search must say what to enter — it must never show a raw API error")
        XCTAssertFalse(app.staticTexts["API error 500: Unknown Error"].exists)
    }

    func testFlippingToSoldCompsWithNothingEnteredIsAlsoExplained() {
        let app = launch()
        let toggle = app.buttons["Active"]
        XCTAssertTrue(toggle.waitForExistence(timeout: 10))
        toggle.tap()

        XCTAssertTrue(
            app.staticTexts.containing(NSPredicate(format: "label CONTAINS %@", emptyHint))
                .firstMatch.waitForExistence(timeout: 5))
        // The toggle still flipped — the refusal is about the empty query, not the mode.
        XCTAssertTrue(app.buttons["Sold comps"].waitForExistence(timeout: 2))
    }

    func testFiltersSheetOpensAndCloses() {
        let app = launch()
        let filters = app.buttons["Filters"]
        XCTAssertTrue(filters.waitForExistence(timeout: 10))
        filters.tap()

        XCTAssertTrue(app.navigationBars["Filters"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.textFields["Make"].exists)
        XCTAssertTrue(app.textFields["Model"].exists)
        XCTAssertTrue(app.buttons["Search"].exists)

        app.buttons["Close"].tap()
        XCTAssertFalse(app.navigationBars["Filters"].waitForExistence(timeout: 2))
    }

    func testLaunchShowsTheEmptyStateAndTheMenuOpens() {
        let app = launch()
        XCTAssertTrue(app.navigationBars["Better Reverb Search"].waitForExistence(timeout: 10))
        // The empty state tells a first-time user what to do, and names the app's
        // relationship to Reverb — both are App Review surface.
        XCTAssertTrue(app.staticTexts["Search Reverb"].waitForExistence(timeout: 5))
        XCTAssertTrue(
            app.staticTexts.containing(
                NSPredicate(format: "label CONTAINS %@", "Not affiliated with Reverb.com"))
                .firstMatch.exists)

        app.buttons["More"].tap()
        XCTAssertTrue(app.buttons["API key"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["Promo code"].exists)
        XCTAssertTrue(app.buttons["Clear"].exists)
    }
}
