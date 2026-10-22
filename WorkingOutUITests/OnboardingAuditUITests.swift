import XCTest

@MainActor
final class OnboardingAuditUITests: XCTestCase {
    override func setUpWithError() throws { continueAfterFailure = false }
    override func record(_ issue: XCTIssue) {
        attach("Failure")
        super.record(issue)
    }
    private func attach(_ name: String) {
        let a = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        a.name = name; a.lifetime = .keepAlways; add(a)
    }
    private func launch() -> XCUIApplication {
        let app = XCUIApplication()
        app.launchEnvironment = ["UITEST_MODE":"1", "UITEST_COACH_DISK":"1", "UITEST_RESET_STATE":"1", "UITEST_SHOW_ONBOARDING":"1", "UITEST_START_TAB":"home"]
        app.launchArguments = ["-ui_testing"]
        app.launch(); return app
    }
    private func reveal(_ element: XCUIElement, in app: XCUIApplication) {
        for _ in 0..<8 {
            if element.exists && element.isHittable { return }
            app.swipeUp()
        }
        XCTAssertTrue(element.exists && element.isHittable, app.debugDescription)
    }
    func testSkipSetupToCompletedManualWorkoutAndReturn() {
        let app = launch(); defer { app.terminate() }
        let skip = app.buttons["Skip Setup"]
        XCTAssertTrue(skip.waitForExistence(timeout: 15), app.debugDescription)
        XCTAssertFalse(app.buttons["Continue"].isEnabled)
        attach("Fresh onboarding allows skip")
        skip.tap()
        let start = app.buttons["home.quickActions.startWorkout"]
        XCTAssertTrue(start.waitForExistence(timeout: 10), app.debugDescription)
        XCTAssertFalse(app.alerts.firstMatch.exists)
        reveal(start, in: app); start.tap()
        let add = app.buttons["Add Exercise"]
        reveal(add, in: app); add.tap()
        let search = app.searchFields.firstMatch
        XCTAssertTrue(search.waitForExistence(timeout: 10), app.debugDescription)
        search.tap(); search.typeText("Bench Press")
        let exercise = app.buttons.containing(.staticText, identifier: "Bench Press").firstMatch
        XCTAssertTrue(exercise.waitForExistence(timeout: 10), app.debugDescription)
        exercise.tap()
        let reps = app.textFields["Reps"]
        XCTAssertTrue(reps.waitForExistence(timeout: 10), app.debugDescription)
        reps.doubleTap(); reps.typeText("8")
        let enteredReps = Int(reps.value as? String ?? "") ?? 0
        XCTAssertEqual(enteredReps, 8)
        app.navigationBars["Edit Set"].buttons["Done"].tap()
        let recorded = app.staticTexts["\(enteredReps) reps @ 0.0 lbs"]
        reveal(recorded, in: app)
        XCTAssertTrue(recorded.exists, app.debugDescription)
        let complete = app.descendants(matching: .any).matching(NSPredicate(format: "label == %@", "Set 1 complete")).firstMatch
        XCTAssertTrue(complete.exists, "Expected a way to mark the manually entered set performed. \(app.debugDescription)")
        let accessibility = XCTAttachment(string: complete.debugDescription)
        accessibility.name = "Manual completion accessibility"
        accessibility.lifetime = .keepAlways
        self.add(accessibility)
        XCTAssertEqual(complete.value as? String, "Off")
        complete.tap()
        XCTAssertEqual(complete.value as? String, "On")
        attach("Manual set explicitly completed")
        let finish = app.buttons["workout.finish"]
        XCTAssertTrue(finish.exists, app.debugDescription); finish.tap()
        XCTAssertTrue(app.staticTexts["Completed"].waitForExistence(timeout: 5), app.debugDescription)
        XCTAssertFalse(app.buttons["Save Partial"].exists)
        attach("First manual workout completed")
        app.navigationBars.buttons["Done"].tap()
        app.terminate()
        app.launchEnvironment["UITEST_RESET_STATE"] = "0"
        app.launchEnvironment.removeValue(forKey: "UITEST_SHOW_ONBOARDING")
        app.launchEnvironment["UITEST_START_TAB"] = "workouts"
        app.launch()
        let session = app.staticTexts["Gym Session"]
        XCTAssertTrue(session.waitForExistence(timeout: 10), app.debugDescription)
        session.tap()
        reveal(recorded, in: app)
        XCTAssertTrue(recorded.exists, app.debugDescription)
        XCTAssertTrue(app.staticTexts["Completed"].exists, app.debugDescription)
        attach("First manual history survives relaunch")
    }
    func testOptionalProfileCanRemainBlankAfterFocusChoice() {
        let app = launch(); defer { app.terminate() }
        let running = app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "Run better")).firstMatch
        XCTAssertTrue(running.waitForExistence(timeout: 15), app.debugDescription)
        running.tap()
        XCTAssertTrue(app.buttons["Continue"].isEnabled)
        app.buttons["Continue"].tap()
        let save = app.buttons["Save & Start"]
        XCTAssertTrue(save.waitForExistence(timeout: 10), app.debugDescription)
        XCTAssertTrue(save.isEnabled, "Blank optional profile must not block start")
        XCTAssertTrue(app.buttons["Do This Later"].exists)
        attach("Optional profile may stay blank")
        save.tap()
        XCTAssertTrue(app.buttons["home.quickActions.startWorkout"].waitForExistence(timeout: 10), app.debugDescription)
        XCTAssertFalse(app.alerts.firstMatch.exists)
        attach("Run focus still lands on general Home")
    }
}
