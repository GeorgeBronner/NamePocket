import XCTest

/// Regression coverage for the trash/restore/empty-trash flow, added
/// alongside the fix removing TrashView's `@Query` usage (which reproduced
/// the freeze pattern documented in `amanda_freeze.md`) and switching
/// `softDeleteCategory`/`detachRestoredChildren` to scalar-ID-filtered
/// fetches instead of relationship traversal. Exercises trash, restore, and
/// permanent deletion for both a category and a person on a fresh app state.
final class TrashFlowUITests: XCTestCase {
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
    func testTrashRestoreAndEmpty() throws {
        app.launch()

        // Add a category and a person at the root level.
        addCategory(named: "ToTrash")
        addPerson(named: "Trashee")

        XCTAssertTrue(app.staticTexts["ToTrash"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.staticTexts["Trashee"].waitForExistence(timeout: 5))

        // Swipe-trash the category. Swipe-action buttons are scoped to the
        // collection view since the toolbar's Trash nav link shares the same
        // "Trash" label and would otherwise make the lookup ambiguous.
        let categoryCell = app.staticTexts["ToTrash"]
        categoryCell.swipeLeft()
        app.collectionViews.buttons["Trash"].tap()
        app.buttons["Move to Trash"].tap()
        XCTAssertTrue(waitForDisappearance(of: categoryCell, timeout: 10),
                      "Category should be removed from the active list after trashing")

        // Swipe-trash the person.
        let personCell = app.staticTexts["Trashee"]
        XCTAssertTrue(personCell.waitForExistence(timeout: 5))
        personCell.swipeLeft()
        app.collectionViews.buttons["Trash"].tap()
        app.buttons["Move to Trash"].tap()

        // Open Trash and confirm both items appear (exercises the fixed
        // @State-based refreshTrash() fetch instead of @Query).
        let trashButton = app.navigationBars.buttons["trash"]
        XCTAssertTrue(trashButton.waitForExistence(timeout: 5))
        trashButton.tap()

        XCTAssertTrue(app.staticTexts["ToTrash"].waitForExistence(timeout: 10), "Trashed category did not appear in Trash")
        XCTAssertTrue(app.staticTexts["Trashee"].waitForExistence(timeout: 5), "Trashed person did not appear in Trash")

        // Restore the person via leading swipe action, confirm it disappears from Trash.
        let trashedPerson = app.staticTexts["Trashee"]
        trashedPerson.swipeRight()
        app.collectionViews.buttons["Restore"].tap()
        XCTAssertTrue(waitForDisappearance(of: trashedPerson, timeout: 10), "Restored person should leave the Trash list")

        // Permanently delete the category via trailing swipe action (exercises
        // the fixed detachRestoredChildren, which now uses scalar-ID fetches).
        let trashedCategory = app.staticTexts["ToTrash"]
        XCTAssertTrue(trashedCategory.waitForExistence(timeout: 5))
        trashedCategory.swipeLeft()
        app.collectionViews.buttons["Delete"].tap()
        XCTAssertTrue(waitForDisappearance(of: trashedCategory, timeout: 10), "Permanently deleted category should leave the Trash list")

        // Trash is now empty.
        XCTAssertTrue(app.staticTexts["Trash is Empty"].waitForExistence(timeout: 10))
    }

    // MARK: - Helpers

    private func waitForDisappearance(of element: XCUIElement, timeout: TimeInterval) -> Bool {
        let predicate = NSPredicate(format: "exists == false")
        let expectation = XCTNSPredicateExpectation(predicate: predicate, object: element)
        return XCTWaiter().wait(for: [expectation], timeout: timeout) == .completed
    }

    private func addCategory(named name: String) {
        app.buttons["plus"].tap()
        app.buttons["Add Category"].tap()
        let alert = app.alerts["New Category"]
        let textField = alert.textFields["Category Name"]
        textField.tap()
        textField.typeText(name)
        alert.buttons["Add"].tap()
    }

    private func addPerson(named name: String) {
        app.buttons["plus"].tap()
        app.buttons["Add Person"].tap()
        let alert = app.alerts["New Person"]
        let textField = alert.textFields["Person Name"]
        textField.tap()
        textField.typeText(name)
        alert.buttons["Add"].tap()
    }
}
