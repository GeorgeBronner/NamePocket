//
//  NamePocketUITests.swift
//  NamePocketUITests
//
//  Created by George Bronner on 12/16/25.
//

import XCTest

final class NamePocketUITests: XCTestCase {

    var app: XCUIApplication!

    @MainActor
    override func setUpWithError() throws {
        continueAfterFailure = false

        app = XCUIApplication()
        app.launchArguments = ["UI-Testing"]

        // Set up initial state for screenshots
        setupSnapshot(app)
    }

    override func tearDownWithError() throws {
        app = nil
    }

    @MainActor
    func testScreenshotFlow() throws {
        app.launch()

        // Give the app time to fully load
        sleep(2)

        // Screenshot 1: Main screen with empty state
        snapshot("01-EmptyState")

        // Add a category
        addCategory(named: "Work")
        sleep(1)

        // Add another category
        addCategory(named: "Friends")
        sleep(1)

        // Add a third category
        addCategory(named: "Family")
        sleep(1)

        // Screenshot 2: Main screen with categories
        snapshot("02-Categories")

        // Navigate into "Friends" category
        app.staticTexts["Friends"].tap()
        sleep(1)

        // Add a person in Friends category
        addPerson(named: "Sarah Johnson")
        sleep(1)

        // Add another person
        addPerson(named: "Mike Chen")
        sleep(1)

        // Add a subcategory
        addCategory(named: "Close Friends")
        sleep(1)

        // Screenshot 3: Category with people and subcategories
        snapshot("03-CategoryWithPeople")

        // Tap on a person to view details
        app.staticTexts["Sarah Johnson"].tap()
        sleep(1)

        // Screenshot 4: Person detail view
        snapshot("04-PersonDetail")

        // Go back
        app.navigationBars.buttons.element(boundBy: 0).tap()
        sleep(1)

        // Navigate into subcategory
        app.staticTexts["Close Friends"].tap()
        sleep(1)

        // Add a person in subcategory
        addPerson(named: "Alex Rivera")
        sleep(1)

        // Screenshot 5: Nested category
        snapshot("05-NestedCategory")

        // Tap on person in subcategory
        app.staticTexts["Alex Rivera"].tap()
        sleep(1)

        // Edit person details
        let nameField = app.textFields["Name"]
        nameField.tap()

        let phoneField = app.textFields["Phone Number"]
        phoneField.tap()
        phoneField.typeText("555-0123")

        let emailField = app.textFields["Email"]
        emailField.tap()
        emailField.typeText("alex@example.com")

        sleep(1)

        // Screenshot 6: Editing contact details
        snapshot("06-EditingContact")
    }

    func testLaunchPerformance() throws {
        measure(metrics: [XCTApplicationLaunchMetric()]) {
            XCUIApplication().launch()
        }
    }

    // MARK: - Helper Methods

    private func addCategory(named name: String) {
        // Tap the + button in toolbar
        app.buttons["plus"].tap()
        sleep(1)

        // Tap "Add Category" in menu
        app.buttons["Add Category"].tap()
        sleep(1)

        // Type category name
        let alert = app.alerts["New Category"]
        let textField = alert.textFields["Category Name"]
        textField.tap()
        textField.typeText(name)

        // Tap Add button
        alert.buttons["Add"].tap()
        sleep(1)
    }

    private func addPerson(named name: String) {
        // Tap the + button in toolbar
        app.buttons["plus"].tap()
        sleep(1)

        // Tap "Add Person" in menu
        app.buttons["Add Person"].tap()
        sleep(1)

        // Type person name
        let alert = app.alerts["New Person"]
        let textField = alert.textFields["Person Name"]
        textField.tap()
        textField.typeText(name)

        // Tap Add button
        alert.buttons["Add"].tap()
        sleep(1)
    }
}
