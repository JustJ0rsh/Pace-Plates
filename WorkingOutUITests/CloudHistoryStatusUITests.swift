import XCTest

@MainActor
final class CloudHistoryStatusUITests: XCTestCase {
    override func setUpWithError() throws { continueAfterFailure = false }

    private func launch(state: String) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchEnvironment["UITEST_MODE"] = "1"
        app.launchEnvironment["UITEST_RESET_STATE"] = "1"
        app.launchEnvironment["UITEST_START_TAB"] = "home"
        app.launchEnvironment["UITEST_CLOUD_HISTORY_STATE"] = state
        app.launch()
        return app
    }

    func testOfflineHistoryIsVisibleAndAccountCheckDoesNotClaimSync() {
        let app = launch(state: "offline")
        defer { app.terminate() }
        let banner = app.buttons["cloud.history.banner"]
        XCTAssertTrue(banner.waitForExistence(timeout: 15))
        XCTAssertTrue(banner.label.contains("History is open without iCloud sync"))
        let settings = app.buttons["home.settings.button"]
        XCTAssertTrue(settings.isHittable)
        XCTAssertFalse(banner.frame.intersects(settings.frame), "History status must not cover the Settings toolbar button")
        banner.tap()
        let title = app.staticTexts["cloud.history.title"]
        XCTAssertTrue(title.waitForExistence(timeout: 5))
        app.buttons["cloud.history.accountCheck"].tap()
        XCTAssertTrue(app.staticTexts["Your iCloud account is available."].waitForExistence(timeout: 5))
        XCTAssertEqual(title.label, "History is open without iCloud sync", "Account availability alone cannot reopen or confirm synchronization")
        app.buttons["Done"].tap()
        XCTAssertTrue(settings.waitForExistence(timeout: 5)); settings.tap()
        let status = app.buttons["cloud.history.settings"]
        XCTAssertTrue(status.waitForExistence(timeout: 5)); status.tap()
        XCTAssertTrue(title.waitForExistence(timeout: 5))
        XCTAssertEqual(title.label, "History is open without iCloud sync")
    }

    func testFreshDownloadRemainsPendingAfterAccountCheck() {
        let app = launch(state: "waiting")
        defer { app.terminate() }
        let banner = app.buttons["cloud.history.banner"]
        XCTAssertTrue(banner.waitForExistence(timeout: 15)); banner.tap()
        let title = app.staticTexts["cloud.history.title"]
        XCTAssertTrue(title.waitForExistence(timeout: 5))
        XCTAssertEqual(title.label, "Waiting for iCloud download")
        app.buttons["cloud.history.accountCheck"].tap()
        XCTAssertTrue(app.staticTexts["Your iCloud account is available."].waitForExistence(timeout: 5))
        XCTAssertEqual(title.label, "Waiting for iCloud download", "A fresh empty store must not claim restored history")
    }

    func testMissingRecordRestoreRequiresReviewAndCanBeCanceled() {
        let app = launch(state: "review")
        defer { app.terminate() }
        let banner = app.buttons["cloud.history.banner"]
        XCTAssertTrue(banner.waitForExistence(timeout: 15)); banner.tap()
        let review = app.staticTexts["cloud.history.review"]
        reveal(review, in: app)
        XCTAssertTrue(review.exists)
        let schedule = app.buttons["cloud.history.scheduleRestore"]
        reveal(schedule, in: app)
        schedule.tap()
        let dialog = app.alerts.firstMatch
        XCTAssertTrue(dialog.waitForExistence(timeout: 5))
        let confirmation = dialog.buttons["Schedule Restore of 3 Records"].firstMatch
        XCTAssertTrue(confirmation.waitForExistence(timeout: 5))
        XCTAssertTrue(dialog.staticTexts.matching(NSPredicate(format: "label CONTAINS %@", "intentionally deleted on another device")).firstMatch.exists)
        dialog.buttons["Keep Records Local"].firstMatch.tap()
        XCTAssertFalse(app.staticTexts["cloud.history.restoreScheduled"].exists)
        reveal(schedule, in: app); schedule.tap()
        XCTAssertTrue(confirmation.waitForExistence(timeout: 5)); confirmation.tap()
        let scheduled = app.staticTexts["cloud.history.restoreScheduled"]
        XCTAssertTrue(scheduled.waitForExistence(timeout: 5))
        let cancel = app.buttons["cloud.history.cancelRestore"]
        reveal(cancel, in: app); cancel.tap()
        XCTAssertFalse(scheduled.exists)
        XCTAssertTrue(schedule.waitForExistence(timeout: 5))
    }

    private func reveal(_ control: XCUIElement, in app: XCUIApplication) {
        for _ in 0..<8 {
            if control.exists && control.isHittable { return }
            app.swipeUp()
        }
        XCTFail("Recovery control was unreachable: \(control)")
    }
}
