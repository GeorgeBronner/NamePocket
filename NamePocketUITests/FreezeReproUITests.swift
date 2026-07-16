import XCTest

/// Automated repro attempt for the "George" folder freeze report: entering
/// George shows its subfolders, but taps stop registering. Data for this
/// test is seeded directly into the simulator's app container before
/// launch (see the orchestrating script) from the user's real backup, so
/// this exercises the exact hierarchy she has (George -> Food/Friends/Family).
///
/// Every wait below has an explicit timeout so a genuine hang surfaces as a
/// normal XCTest failure instead of blocking the run indefinitely.
final class FreezeReproUITests: XCTestCase {
    var app: XCUIApplication!

    @MainActor
    override func setUpWithError() throws {
        continueAfterFailure = false
        app = XCUIApplication()
    }

    override func tearDownWithError() throws {
        app = nil
    }

    @MainActor
    func testEnterGeorgeAndTapSubfolders() throws {
        app.launch()

        let george = app.staticTexts["George"]
        XCTAssertTrue(george.waitForExistence(timeout: 15), "Root list never showed a 'George' row")

        // Sanity check the rest of the seeded root data loaded too.
        XCTAssertTrue(app.staticTexts["Wine"].waitForExistence(timeout: 5), "Root list missing 'Wine' — seeded data may not have loaded")

        george.tap()

        // This is the exact point the report describes: subfolders appear...
        // Note: her "Friends" category name has a genuine trailing space in
        // the data (confirmed via sqlite hex dump), so match by prefix.
        let friendsPredicate = NSPredicate(format: "label BEGINSWITH 'Friends'")
        let food = app.staticTexts["Food"]
        XCTAssertTrue(food.waitForExistence(timeout: 15), "Did not see Food subfolder after entering George")
        XCTAssertTrue(app.staticTexts.matching(friendsPredicate).firstMatch.waitForExistence(timeout: 5), "Did not see Friends subfolder after entering George")
        XCTAssertTrue(app.staticTexts["Family"].waitForExistence(timeout: 5), "Did not see Family subfolder after entering George")

        // ...but does the UI actually respond to a press now?
        food.tap()
        let noOnions = app.staticTexts["No Onions"]
        XCTAssertTrue(noOnions.waitForExistence(timeout: 15), "Tapping 'Food' after entering George did not navigate — UI unresponsive, reproduces the freeze")

        // Back out and try the other two subfolders as well.
        app.navigationBars.buttons.element(boundBy: 0).tap()
        XCTAssertTrue(food.waitForExistence(timeout: 10), "Did not return to George after tapping back from Food")

        let friends = app.staticTexts.matching(friendsPredicate).firstMatch
        friends.tap()
        XCTAssertTrue(app.staticTexts["Stephen Bolt"].waitForExistence(timeout: 15), "Tapping 'Friends' after entering George did not navigate")
        app.navigationBars.buttons.element(boundBy: 0).tap()
        XCTAssertTrue(friends.waitForExistence(timeout: 10), "Did not return to George after tapping back from Friends")

        let family = app.staticTexts["Family"]
        family.tap()
        XCTAssertTrue(app.staticTexts["Courtney"].waitForExistence(timeout: 15), "Tapping 'Family' after entering George did not navigate")

        // Also confirm the toolbar (a non-NavigationLink control) still responds,
        // since the report says "does not respond to any presses", not just links.
        app.navigationBars.buttons.element(boundBy: 0).tap()
        XCTAssertTrue(family.waitForExistence(timeout: 10), "Did not return to George after tapping back from Family")
        let plusButton = app.buttons["plus"]
        XCTAssertTrue(plusButton.waitForExistence(timeout: 5))
        plusButton.tap()
        XCTAssertTrue(app.buttons["Add Category"].waitForExistence(timeout: 10), "Toolbar '+' menu did not respond while on George's screen")
    }
}
