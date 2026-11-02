import XCTest

@MainActor
final class RestoredHistoryUITests: XCTestCase {
    func testDuplicateRunUUIDsOpenTheirOwnDetails() {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchEnvironment["UITEST_MODE"] = "1"
        app.launchEnvironment["UITEST_RESET_STATE"] = "1"
        app.launchEnvironment["UITEST_START_TAB"] = "runs"
        app.launchEnvironment["UITEST_FIXTURE"] = "restored_duplicate_runs"
        app.launch()
        defer { app.terminate() }
        let rows = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "runs.history.row."))
        func revealRows() {
            for _ in 0..<7 {
                if rows.count == 2 && rows.element(boundBy: 1).isHittable { return }
                app.scrollViews.firstMatch.swipeUp()
            }
            XCTAssertEqual(rows.count, 2)
        }
        revealRows()
        let identifiers = rows.allElementsBoundByIndex.map(\.identifier)
        XCTAssertEqual(Set(identifiers).count, 2, "Duplicate application UUIDs retain separate row identities")
        for index in 0..<2 {
            revealRows()
            app.buttons.matching(NSPredicate(format: "identifier == %@", identifiers[index])).firstMatch.tap()
            XCTAssertTrue(app.navigationBars["Run Details"].waitForExistence(timeout: 5))
            let note = app.staticTexts["Notes: Synthetic restored run \(index + 1)"]
            for _ in 0..<6 {
                if note.exists { break }
                app.scrollViews.firstMatch.swipeUp()
            }
            XCTAssertTrue(note.exists, "Each restored row must open its own data")
            app.navigationBars["Run Details"].buttons.element(boundBy: 0).tap()
        }
    }
}
