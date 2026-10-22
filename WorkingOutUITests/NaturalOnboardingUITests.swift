import XCTest

/// Uses real onboarding decisions and Security APIs, but only a UUID-scoped
/// synthetic Keychain service and the app's existing isolated local test store.
@MainActor
final class NaturalOnboardingUITests: XCTestCase {
    override func setUpWithError() throws { continueAfterFailure = false }

    override func record(_ issue: XCTIssue) {
        let screenshot = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        screenshot.name = "Natural onboarding failure"
        screenshot.lifetime = .keepAlways
        add(screenshot)
        super.record(issue)
    }

    private func launch() -> XCUIApplication {
        let app = XCUIApplication()
        app.launchEnvironment = [
            "UITEST_MODE": "1",
            "UITEST_COACH_DISK": "1",
            "UITEST_RESET_STATE": "1",
            "UITEST_NATURAL_PROFILE": "1",
            "UITEST_PROFILE_SCOPE": UUID().uuidString,
            "UITEST_START_TAB": "home"
        ]
        app.launchArguments = ["-ui_testing"]
        app.launch()
        XCTAssertTrue(app.buttons["Skip Setup"].waitForExistence(timeout: 15), app.debugDescription)
        return app
    }

    private func reveal(_ element: XCUIElement, in app: XCUIApplication) {
        for _ in 0..<10 {
            if element.exists && element.isHittable { return }
            app.swipeUp()
        }
        XCTAssertTrue(element.exists && element.isHittable, app.debugDescription)
    }

    private func assertHome(_ app: XCUIApplication) {
        let home = app.buttons["home.quickActions.startWorkout"]
        XCTAssertTrue(home.waitForExistence(timeout: 15), app.debugDescription)
        let noTutorial = NSPredicate(format: "exists == false")
        expectation(for: noTutorial, evaluatedWith: app.buttons["Skip Setup"])
        waitForExpectations(timeout: 5)
        XCTAssertFalse(app.alerts.firstMatch.exists, "Optional integrations must stay inert")
    }

    private func assertProfile(_ expected: String, in app: XCUIApplication) {
        let status = app.staticTexts["readiness.syntheticProfile"]
        XCTAssertTrue(status.waitForExistence(timeout: 10), app.debugDescription)
        XCTAssertEqual(status.label, expected)
        let evidence = XCTAttachment(string: status.label)
        evidence.name = "Synthetic Keychain readback"
        evidence.lifetime = .keepAlways
        add(evidence)
    }

    private var emptyProfile: String {
        "keychain=true;defaultsCleared=true;age=0;height=0.0;target=0.0;sex="
    }

    func testSkippedEmptyProfileNaturallyStaysDismissedAfterRelaunch() {
        let app = launch()
        defer { app.terminate() }
        app.buttons["Skip Setup"].tap()
        assertHome(app)
        assertProfile(emptyProfile, in: app)
        app.terminate()
        app.launchEnvironment["UITEST_RESET_STATE"] = "0"
        app.launch()
        assertHome(app)
        assertProfile(emptyProfile, in: app)
    }

    func testBlankOptionalProfileNaturallyStaysDismissedAfterRelaunch() {
        let app = launch()
        defer { app.terminate() }
        chooseFocus(in: app)
        app.buttons["Save & Start"].tap()
        assertHome(app)
        assertProfile(emptyProfile, in: app)
        app.terminate()
        app.launchEnvironment["UITEST_RESET_STATE"] = "0"
        app.launch()
        assertHome(app)
        assertProfile(emptyProfile, in: app)
    }

    func testEnteredProfileSurvivesKeychainRelaunchAndSuppressesOnboardingWithoutFlags() {
        let app = launch()
        defer { app.terminate() }
        chooseFocus(in: app)

        let age = app.textFields["Age, optional"]
        reveal(age, in: app)
        age.tap()
        age.typeText("37")
        XCTAssertEqual(age.value as? String, "37")
        app.buttons["Done"].firstMatch.tap()

        let height = app.descendants(matching: .any)
            .matching(NSPredicate(format: "label == %@", "Height, optional")).firstMatch
        reveal(height, in: app)
        height.tap()
        let saveHeight = app.navigationBars["Height"].buttons["Save"]
        XCTAssertTrue(saveHeight.waitForExistence(timeout: 5), app.debugDescription)
        // Choosing the visible 5 ft 8 in default is an explicit profile entry.
        saveHeight.tap()

        let goal = app.textFields["Goal weight, optional"]
        reveal(goal, in: app)
        goal.tap()
        goal.typeText("165")
        XCTAssertEqual(goal.value as? String, "165")
        app.buttons["Done"].firstMatch.tap()
        app.buttons["Save & Start"].tap()

        assertHome(app)
        let expected = "keychain=true;defaultsCleared=true;age=37;height=68.0;target=165.0;sex="
        assertProfile(expected, in: app)
        app.terminate()
        // Reset only this disposable app's defaults/store, retaining this test's
        // synthetic Keychain item. A fresh profile read must drive onboarding.
        app.launchEnvironment["UITEST_RESET_STATE"] = "1"
        app.launch()
        assertHome(app)
        assertProfile(expected, in: app)
    }

    private func chooseFocus(in app: XCUIApplication) {
        let focus = app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "Build strength")).firstMatch
        XCTAssertTrue(focus.waitForExistence(timeout: 10), app.debugDescription)
        focus.tap()
        app.buttons["Continue"].tap()
        XCTAssertTrue(app.buttons["Save & Start"].waitForExistence(timeout: 10), app.debugDescription)
    }
}
