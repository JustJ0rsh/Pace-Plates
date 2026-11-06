import XCTest

@MainActor
final class NonblockingHistoryUITests: XCTestCase {
    override func setUpWithError() throws { continueAfterFailure = false }

    func testUnavailableHistoryCanContinueSavingAndReopen() {
        let app = XCUIApplication()
        app.launchEnvironment = ["UITEST_MODE": "1", "UITEST_RESET_STATE": "1",
                                 "UITEST_START_TAB": "home", "UITEST_FIXTURE": "unavailable_history"]
        app.launch()
        defer { app.terminate() }
        let proceed = app.buttons["storage.continueLocal"]
        XCTAssertTrue(proceed.waitForExistence(timeout: 15))
        proceed.tap()
        let banner = app.buttons["cloud.history.banner"]
        XCTAssertTrue(banner.waitForExistence(timeout: 10))
        XCTAssertFalse(app.alerts.firstMatch.exists)
        let logWeight = app.buttons["Log Weight"].firstMatch
        for _ in 0..<6 {
            if logWeight.exists && logWeight.isHittable { break }
            app.swipeUp()
        }
        XCTAssertTrue(logWeight.isHittable)
        logWeight.tap()
        let field = app.textFields["Enter weight"]
        XCTAssertTrue(field.waitForExistence(timeout: 5))
        field.tap(); field.typeText("88")
        app.navigationBars["Log Weight"].buttons["Save"].tap()
        let healthWarning = app.alerts["Saved in Pace & Plates"]
        if healthWarning.waitForExistence(timeout: 10) {
            XCTAssertTrue(healthWarning.staticTexts.matching(NSPredicate(format: "label CONTAINS %@", "not in Apple Health")).firstMatch.exists)
            healthWarning.buttons["Done"].tap()
        }
        XCTAssertTrue(app.navigationBars["Log Weight"].waitForNonExistence(timeout: 10), app.debugDescription)
        app.tabBars.buttons["Weight"].tap()
        XCTAssertTrue(app.staticTexts["1 result"].waitForExistence(timeout: 10))

        app.terminate()
        app.launchEnvironment["UITEST_RESET_STATE"] = "0"
        app.launchEnvironment["UITEST_START_TAB"] = "weight"
        app.launch()
        XCTAssertTrue(app.staticTexts["1 result"].waitForExistence(timeout: 15), "The new entry must survive a new process")
        XCTAssertFalse(proceed.exists, "Relaunch keeps the selected local history")
        let search = app.textFields["weight.history.filters.search"]
        for _ in 0..<5 {
            if search.isHittable { break }
            app.swipeUp()
        }
        XCTAssertTrue(search.isHittable); search.tap(); search.typeText("88")
        XCTAssertTrue(app.staticTexts["1 result"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.alerts.firstMatch.exists)
    }
}
