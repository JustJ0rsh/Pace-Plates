import XCTest

@MainActor
final class CoachReadinessUITests: XCTestCase {
    override func setUpWithError() throws { continueAfterFailure = false }

    override func record(_ issue: XCTIssue) {
        let screenshot = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        screenshot.name = "Coach readiness failure"
        screenshot.lifetime = .keepAlways
        add(screenshot)
        super.record(issue)
    }

    func testSavedDraftRequiresExplicitStartAndPhaseReviewBeforeCheckOff() {
        let app = XCUIApplication()
        app.launchEnvironment["UITEST_MODE"] = "1"
        app.launchEnvironment["UITEST_RESET_STATE"] = "1"
        app.launchEnvironment["UITEST_START_TAB"] = "ai"
        app.launchArguments += ["-AppleLanguages", "(en)", "-AppleLocale", "en_US"]
        app.launch()
        XCUIDevice.shared.orientation = .portrait
        defer { app.terminate() }

        tap(app.buttons["coach.add_plan"], in: app)
        tap(app.buttons["coach.add_plan.paste"], in: app)
        let input = app.textViews["coach.import.paste"]
        XCTAssertTrue(input.waitForExistence(timeout: 10))
        input.tap()
        input.typeText(Self.program)
        tap(app.buttons["coach.import.review"], in: app)
        XCTAssertTrue(app.navigationBars["Review Program"].waitForExistence(timeout: 10))

        let readiness = app.switches["I have reviewed the first phase and am ready to start it"]
        reveal(readiness, in: app)
        XCTAssertEqual(readiness.value as? String, "0")
        reveal(app.buttons["coach.plan.activate"], in: app)
        XCTAssertFalse(app.buttons["coach.plan.activate"].isEnabled,
                       "Import must not activate a review-required phase without acknowledgement")
        tap(app.buttons["coach.plan.save_draft"], in: app)
        tap(app.buttons["coach.plan.open_saved"], in: app)
        XCTAssertTrue(app.navigationBars["Your Plan"].waitForExistence(timeout: 10))

        returnToDashboard(app)
        XCTAssertTrue(app.staticTexts["Your plan is saved"].waitForExistence(timeout: 10),
                      "A saved draft must remain discoverable on the dashboard")
        tap(app.buttons["coach.plan.saved"], in: app)
        let session = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "coach.today.session.")).firstMatch
        reveal(session, in: app)
        let occurrenceIdentifier = session.identifier
        tap(session, in: app)
        XCTAssertTrue(app.navigationBars["Session"].waitForExistence(timeout: 10))
        XCTAssertFalse(app.buttons["coach.session.start"].exists)
        XCTAssertFalse(app.buttons["coach.session.mark_done"].exists)
        tap(app.buttons["coach.session.review_plan"], in: app)

        tap(app.buttons["coach.plan.start"], in: app)
        tap(app.buttons["Start with These Dates"], in: app)
        let activeStatus = app.staticTexts.matching(NSPredicate(format: "label BEGINSWITH %@", "Active · ")).firstMatch
        XCTAssertTrue(activeStatus.waitForExistence(timeout: 10))
        back(from: "Your Plan", in: app)

        let phaseReview = app.buttons["coach.session.review_phase"]
        XCTAssertTrue(phaseReview.waitForExistence(timeout: 10),
                      "Starting the plan must leave its unreviewed phase gated")
        XCTAssertFalse(app.buttons["coach.session.start"].exists)
        tap(phaseReview, in: app)
        tap(app.buttons["Phase reviews"], in: app)
        tap(app.buttons["I reviewed this phase and am ready"], in: app)
        XCTAssertTrue(app.staticTexts["Readiness confirmed"].waitForExistence(timeout: 10))
        back(from: "Your Plan", in: app)

        let start = app.buttons["coach.session.start"]
        XCTAssertTrue(start.waitForExistence(timeout: 10))
        XCTAssertEqual(start.label, "Mark as Done")
        XCTAssertFalse(phaseReview.exists)
        tap(start, in: app)
        let completion = app.alerts["Record Completion"]
        XCTAssertTrue(completion.waitForExistence(timeout: 5))
        XCTAssertFalse(completion.buttons["Record"].isEnabled)
        completion.textFields.firstMatch.tap()
        completion.textFields.firstMatch.typeText("Completed the reviewed gentle mobility session")
        completion.buttons["Record"].tap()
        XCTAssertTrue(app.staticTexts["Completed"].waitForExistence(timeout: 10))
        XCTAssertFalse(start.exists)
        XCTAssertFalse(app.buttons["coach.session.skip"].exists)
        XCTAssertFalse(app.alerts["Coach"].exists)

        returnToDashboard(app)
        let completedOccurrence = app.buttons[occurrenceIdentifier]
        reveal(completedOccurrence, in: app)
        XCTAssertTrue(completedOccurrence.label.contains("Done"),
                      "The same planned occurrence must show its check-off on the dashboard")
        XCTAssertEqual(app.buttons.matching(identifier: occurrenceIdentifier).count, 1)
    }

    private func back(from title: String, in app: XCUIApplication) {
        let bar = app.navigationBars[title]
        XCTAssertTrue(bar.waitForExistence(timeout: 5))
        bar.buttons.element(boundBy: 0).tap()
    }

    private func returnToDashboard(_ app: XCUIApplication) {
        for _ in 0..<8 {
            if app.buttons["coach.plans.open"].exists { return }
            let back = app.navigationBars.buttons.element(boundBy: 0)
            XCTAssertTrue(back.waitForExistence(timeout: 5))
            back.tap()
        }
        XCTFail("The Coach dashboard was not reachable.\n\(app.debugDescription)")
    }

    private func tap(_ element: XCUIElement, in app: XCUIApplication) {
        reveal(element, in: app)
        element.tap()
    }

    private func reveal(_ element: XCUIElement, in app: XCUIApplication) {
        if !element.exists { _ = element.waitForExistence(timeout: 3) }
        for attempt in 0...8 {
            if element.exists && element.isHittable { return }
            guard attempt < 8 else { break }
            let scrollers = app.collectionViews.allElementsBoundByIndex + app.scrollViews.allElementsBoundByIndex
            guard let scroller = scrollers.last(where: { $0.frame.width > 0 && $0.frame.height > 0 && $0.frame.intersects(app.frame) }) else { continue }
            let frame = scroller.frame
            let keyboard = app.keyboards.firstMatch
            let keyboardTop = keyboard.exists && keyboard.frame.height > 0 ? keyboard.frame.minY : app.frame.maxY
            let tabTop = app.tabBars.allElementsBoundByIndex.filter { $0.frame.minY > app.frame.midY && $0.frame.height > 0 }.map { $0.frame.minY }.min() ?? app.frame.maxY
            let top = max(frame.minY, app.frame.minY) + 40
            let pinnedTop = app.descendants(matching: .any).matching(NSPredicate(format: "identifier IN %@", ["coach.plan.activate", "coach.plan.save_draft", "coach.plan.next_step", "coach.import.review", "coach.prompt.paste_reply", "coach.prompt.copy"])).allElementsBoundByIndex
                .filter { $0.frame.minY > app.frame.midY && $0.frame.intersects(app.frame) }.map { $0.frame.minY }.min() ?? app.frame.maxY
            let bottom = min(frame.maxY, keyboardTop, tabTop, pinnedTop, app.frame.maxY) - 24
            guard bottom > top + 30 else { break }
            let towardTop = element.exists && element.frame.maxY <= top
            let origin = scroller.coordinate(withNormalizedOffset: .zero)
            let start = origin.withOffset(CGVector(dx: 35, dy: (towardTop ? top : bottom) - frame.minY))
            let end = origin.withOffset(CGVector(dx: 35, dy: (towardTop ? bottom : top) - frame.minY))
            start.press(forDuration: 0.05, thenDragTo: end)
        }
        XCTFail("Expected readiness control to become visible: \(element)\n\(app.debugDescription)")
    }

    private static let program = """
    {"format":"pace-and-plates.coach-program","schemaVersion":1,"programId":"ui-readiness","revision":1,"title":"Readiness Review Program","goal":"Follow an explicitly reviewed recovery session","preferredUnits":{"weight":"kg","distance":"km"},"phases":[{"id":"phase","title":"Reviewed Recovery","overview":"Review the gentle mobility instructions before starting this phase.","advanceMode":"reviewRequired"}],"sessionTemplates":[{"kind":"recovery","id":"mobility","title":"Reviewed Mobility","durationSeconds":300,"instructions":"Complete gentle mobility at a comfortable range."}],"weekPatterns":[{"id":"pattern","title":"Recovery week","slots":[{"id":"first","dayOffset":0,"sessionTemplateId":"mobility"}]}],"weeks":[{"id":"week","phaseId":"phase","weekPatternId":"pattern"}]}
    """
}
