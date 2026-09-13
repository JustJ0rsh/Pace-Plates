import XCTest

@MainActor
final class CoachEditingUITests: XCTestCase {
    private var capturedFailure = false
    override func setUpWithError() throws { continueAfterFailure = false; capturedFailure = false }
    override func record(_ issue: XCTIssue) {
        capturedFailure = true
        let screenshot = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        screenshot.name = "Issue screen - \(Date().timeIntervalSince1970) - " + name
        screenshot.lifetime = .keepAlways
        add(screenshot)
        super.record(issue)
    }
    override func tearDownWithError() throws {
        if testRun?.hasSucceeded == false && !capturedFailure {
            let screenshot = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
            screenshot.name = "Failure teardown - " + name; screenshot.lifetime = .keepAlways
            add(screenshot)
        }
        try super.tearDownWithError()
    }

    func testManualProgramDuplicatesPhaseAndSavesDraftWithoutActivity() {
        let app = launch()
        defer { app.terminate() }
        openBuilder(app)
        enter("Manual Review Program", into: control("coach.builder.title", in: app), in: app)
        enter("Follow a reviewed practice schedule", into: control("coach.builder.goal", in: app), in: app)
        let addTemplate = app.buttons["coach.builder.add_template"]
        tap(addTemplate, in: app)
        let running = app.buttons["Running"]
        if !running.waitForExistence(timeout: 2) {
            addTemplate.coordinate(withNormalizedOffset: CGVector(dx: 0.1, dy: 0.5)).tap()
        }
        XCTAssertTrue(running.waitForExistence(timeout: 5), "The template menu must open without scrolling for an absent menu item.\n\(app.debugDescription)")
        running.tap()
        tap(app.buttons["Week pattern 1"], in: app)
        tap(app.buttons["coach.builder.day.0.add_session"], in: app)
        back(from: "Weekly Schedule", in: app)
        let duplicate = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "coach.builder.duplicate_phase.")).firstMatch
        tap(duplicate, in: app)
        tap(app.buttons["coach.builder.review_toolbar"], in: app)
        tap(app.buttons["coach.builder.open_review"], in: app)
        XCTAssertTrue(app.navigationBars["Review Program"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.staticTexts["2 weeks · 2 phases · 1 templates"].exists)
        tap(app.buttons["coach.plan.save_draft"], in: app)
        tap(app.buttons["coach.plan.open_saved"], in: app)
        XCTAssertTrue(app.staticTexts.matching(NSPredicate(format: "label BEGINSWITH %@", "Draft · ")).firstMatch.waitForExistence(timeout: 10))
        selectTab("Workouts", in: app)
        XCTAssertTrue(app.staticTexts["No workouts yet"].waitForExistence(timeout: 10), "Saving a program draft must not create an actual workout")
        selectTab("Runs", in: app)
        XCTAssertFalse(app.buttons["Pause"].exists, "Authoring must not start a run")
    }

    func testNutritionReplacesTotalsAndKeepsBlankDistinctFromZero() {
        let app = launch()
        defer { app.terminate() }
        openNutrition(app)
        enter("1800", into: app.textFields["Calories"], in: app)
        saveCheckIn("coach.nutrition.save", in: app)
        tap(app.buttons["Done"], in: app)
        openNutrition(app)
        XCTAssertEqual(app.textFields["Calories"].value as? String, "1800.0")
        XCTAssertEqual(app.textFields["Protein"].value as? String, "Not entered")
        enter("1950", into: app.textFields["Calories"], in: app, replacing: true)
        enter("0", into: app.textFields["Protein"], in: app)
        saveCheckIn("coach.nutrition.finish", in: app)
        tap(app.buttons["Done"], in: app)
        openNutrition(app)
        XCTAssertEqual(app.textFields["Calories"].value as? String, "1950.0", "An edit replaces the total rather than adding to it")
        XCTAssertEqual(app.textFields["Protein"].value as? String, "0.0")
        XCTAssertEqual(app.textFields["Fat"].value as? String, "Not entered")
        XCTAssertTrue(app.staticTexts["Daily totals · Finished"].exists)
    }

    func testTargetEditingPreservesUnsavedTotalsAndSavedTargetSnapshot() {
        let app = launch()
        defer { app.terminate() }
        openNutrition(app)
        enter("2000", into: app.textFields["Calories"], in: app)
        openTargets(in: app)
        XCTAssertTrue(app.navigationBars["Nutrition Targets"].waitForExistence(timeout: 5))
        enter("2200", into: frontTextField("Calories", in: app), in: app)
        tap(app.navigationBars["Nutrition Targets"].buttons["Save"], in: app)
        XCTAssertTrue(app.navigationBars["Nutrition"].waitForExistence(timeout: 5))
        reveal(app.textFields["Calories"], in: app)
        XCTAssertEqual(app.textFields["Calories"].value as? String, "2000", "Returning from target editing must preserve unsaved totals")
        saveCheckIn("coach.nutrition.save", in: app)
        openTargets(in: app)
        enter("2300", into: frontTextField("Calories", in: app), in: app, replacing: true)
        tap(app.navigationBars["Nutrition Targets"].buttons["Save"], in: app)
        let savedTarget = app.staticTexts["2200 kcal"]
        reveal(savedTarget, in: app)
        XCTAssertTrue(savedTarget.exists, "A target change must not relabel an already logged day")
        tap(app.buttons["Done"], in: app)
        openNutrition(app)
        XCTAssertEqual(app.textFields["Calories"].value as? String, "2000.0")
        reveal(savedTarget, in: app)
        XCTAssertTrue(savedTarget.exists)
    }

    func testRecoveryRejectsInvalidEnergyAndRetainsZeroAndUnknownOnEdit() {
        let app = launch()
        defer { app.terminate() }
        openRecovery(app)
        enter("0", into: app.textFields["Soreness"], in: app)
        enter("0", into: app.textFields["Energy"], in: app)
        tap(app.buttons["coach.recovery.save"], in: app)
        let error = app.staticTexts["coach.checkin.error"]
        reveal(error, in: app)
        XCTAssertTrue(error.label.localizedCaseInsensitiveContains("energy"))
        enter("3", into: app.textFields["Energy"], in: app, replacing: true)
        saveCheckIn("coach.recovery.save", in: app)
        tap(app.buttons["Done"], in: app)
        openRecovery(app)
        reveal(app.textFields["Soreness"], in: app)
        XCTAssertEqual(app.textFields["Soreness"].value as? String, "0")
        XCTAssertEqual(app.textFields["Energy"].value as? String, "3")
        XCTAssertEqual(app.textFields["Pain"].value as? String, "Not entered")
        enter("", into: app.textFields["Energy"], in: app, replacing: true)
        saveCheckIn("coach.recovery.save", in: app)
        tap(app.buttons["Done"], in: app)
        openRecovery(app)
        reveal(app.textFields["Energy"], in: app)
        XCTAssertEqual(app.textFields["Energy"].value as? String, "Not entered")
        XCTAssertEqual(app.textFields["Soreness"].value as? String, "0")
        tap(app.buttons["Delete This Check-in"], in: app)
        tap(app.buttons["Done"], in: app)
        openRecovery(app)
        reveal(app.textFields["Soreness"], in: app)
        XCTAssertEqual(app.textFields["Soreness"].value as? String, "Not entered")
    }

    func testCoachWeightEditAndDeleteAreSharedWithWeightTab() {
        let app = launch()
        defer { app.terminate() }
        openBody(app)
        tap(app.buttons["coach.body.add_weight"], in: app)
        enter("80.25", into: app.textFields["Weight"], in: app)
        tap(app.buttons["coach.body.measurement.save"], in: app)
        tap(app.buttons["Edit weight observations"], in: app)
        let rows = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "coach.body.weight.observation."))
        reveal(rows.firstMatch, in: app)
        XCTAssertEqual(rows.count, 1)
        let id = rows.firstMatch.identifier
        tap(app.buttons[id], in: app)
        enter("79.75", into: app.textFields["Weight"], in: app, replacing: true)
        tap(app.buttons["coach.body.measurement.save"], in: app)
        reveal(app.buttons[id], in: app)
        XCTAssertEqual(rows.count, 1, "Editing must retain the observation identity")
        XCTAssertTrue(app.buttons[id].label.contains("79.75"))
        selectTab("Weight", in: app)
        XCTAssertTrue(app.staticTexts["Body Weight"].waitForExistence(timeout: 10), "The Weight tab must display the same saved record")
        XCTAssertFalse(app.staticTexts["No Weight Logged"].exists)
        selectTab("Coach", in: app)
        tap(app.buttons[id], in: app)
        tap(app.buttons["coach.body.measurement.delete"], in: app)
        XCTAssertTrue(waitForDisappearance(app.buttons[id]), "Wait for deletion and sheet dismissal to refresh the observation list")
        selectTab("Weight", in: app)
        XCTAssertTrue(app.staticTexts["No Weight Logged"].waitForExistence(timeout: 10), "Deleting the shared record must update both tabs")
    }

    func testWaistAllowsMultipleObservationsAndEditsOnlySelectedRecord() {
        let app = launch()
        defer { app.terminate() }
        openBody(app)
        for value in ["83.2", "82.7"] {
            tap(app.buttons["coach.body.add_waist"], in: app)
            enter(value, into: app.textFields["Waist"], in: app)
            tap(app.buttons["coach.body.measurement.save"], in: app)
        }
        tap(app.buttons["Edit waist observations"], in: app)
        let rows = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "coach.body.waist.observation."))
        reveal(rows.firstMatch, in: app)
        XCTAssertEqual(rows.count, 2, "Same-day waist observations must remain separate")
        let selectedID = rows.element(boundBy: 0).identifier
        let otherID = rows.element(boundBy: 1).identifier
        tap(app.buttons[selectedID], in: app)
        enter("84", into: app.textFields["Waist"], in: app, replacing: true)
        tap(app.buttons["coach.body.measurement.save"], in: app)
        reveal(app.buttons[selectedID], in: app)
        XCTAssertEqual(rows.count, 2)
        XCTAssertTrue(app.buttons[selectedID].label.contains("84"))
        XCTAssertTrue(app.buttons[otherID].label.contains("83.2"))
        tap(app.buttons[otherID], in: app)
        tap(app.buttons["coach.body.measurement.delete"], in: app)
        reveal(app.buttons[selectedID], in: app)
        XCTAssertEqual(rows.count, 1)
        XCTAssertTrue(app.buttons[selectedID].exists)
    }

    func testLargestTypeBuilderCanReviewWhileKeyboardIsOpen() {
        let app = launch(contentSize: "UICTContentSizeCategoryAccessibilityXXXL")
        defer { app.terminate() }
        openBuilder(app)
        enter("Large Type Program", into: control("coach.builder.title", in: app), in: app)
        enter("Review authored sessions at the largest text size", into: control("coach.builder.goal", in: app), in: app)
        var review = app.buttons["coach.builder.review_toolbar"]
        if !review.exists {
            let more = app.navigationBars["Build Program"].buttons["More"]
            XCTAssertTrue(waitForStableControl(more, in: app), "Toolbar overflow must remain reachable above the keyboard\n\(app.debugDescription)")
            more.tap()
            if !review.waitForExistence(timeout: 2) { review = app.buttons["Review"] }
        }
        XCTAssertTrue(waitForStableControl(review, in: app), "Review must remain reachable above the keyboard\n\(app.debugDescription)")
        review.tap()
        let error = app.staticTexts["coach.builder.error"]
        reveal(error, in: app, attempts: 12)
        XCTAssertTrue(error.label.contains("sessionTemplates"), "An incomplete draft should report the missing session template")
        XCTAssertFalse(app.buttons["coach.builder.open_review"].exists)
    }

    private func launch(contentSize: String? = nil) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchEnvironment["UITEST_MODE"] = "1"
        app.launchEnvironment["UITEST_RESET_STATE"] = "1"
        app.launchEnvironment["UITEST_START_TAB"] = "ai"
        app.launchArguments += ["-AppleLanguages", "(en)", "-AppleLocale", "en_US"]
        if let contentSize { app.launchArguments += ["-UIPreferredContentSizeCategoryName", contentSize] }
        app.launch()
        XCUIDevice.shared.orientation = .portrait
        XCTAssertTrue(app.navigationBars["Coach"].waitForExistence(timeout: 10))
        return app
    }

    private func openBuilder(_ app: XCUIApplication) {
        tap(app.buttons["coach.add_plan"], in: app)
        tap(app.buttons["Build Manually"], in: app)
        XCTAssertTrue(app.navigationBars["Build Program"].waitForExistence(timeout: 5))
    }
    private func openNutrition(_ app: XCUIApplication) {
        tap(app.buttons["coach.nutrition.open"], in: app)
        XCTAssertTrue(app.navigationBars["Nutrition"].waitForExistence(timeout: 5))
    }
    private func openRecovery(_ app: XCUIApplication) {
        tap(app.buttons["coach.recovery.open"], in: app)
        XCTAssertTrue(app.navigationBars["Recovery"].waitForExistence(timeout: 5))
    }
    private func openBody(_ app: XCUIApplication) {
        tap(app.buttons["Weight, waist and photos"], in: app)
        XCTAssertTrue(app.navigationBars["Body Progress"].waitForExistence(timeout: 5))
    }
    private func selectTab(_ title: String, in app: XCUIApplication) {
        let bottomTab = app.tabBars.buttons[title]
        let tab = bottomTab.exists ? bottomTab : app.buttons[title].firstMatch
        XCTAssertTrue(tab.waitForExistence(timeout: 5))
        XCTAssertTrue(tab.isHittable)
        tab.tap()
    }
    private func control(_ identifier: String, in app: XCUIApplication) -> XCUIElement {
        app.descendants(matching: .any).matching(identifier: identifier).firstMatch
    }
    private func back(from title: String, in app: XCUIApplication) {
        tap(app.navigationBars[title].buttons.element(boundBy: 0), in: app)
    }
    private func openTargets(in app: XCUIApplication) {
        let button = app.buttons["Edit Targets from an Effective Date"]
        tap(button, in: app)
        let editor = app.navigationBars["Nutrition Targets"]
        if !editor.waitForExistence(timeout: 2) {
            reveal(button, in: app)
            button.coordinate(withNormalizedOffset: CGVector(dx: 0.1, dy: 0.5)).tap()
        }
        XCTAssertTrue(editor.waitForExistence(timeout: 5), app.debugDescription)
    }
    private func saveCheckIn(_ identifier: String, in app: XCUIApplication) {
        dismissKeyboard(in: app)
        let button = app.buttons[identifier]
        reveal(button, in: app)
        XCTAssertTrue(waitForStableControl(button, in: app))
        button.coordinate(withNormalizedOffset: CGVector(dx: 0.1, dy: 0.5)).tap()
        let saved = app.staticTexts["coach.checkin.saved"]
        reveal(saved, in: app, searchAbove: true)
        XCTAssertTrue(saved.exists)
    }
    private func frontTextField(_ title: String, in app: XCUIApplication) -> XCUIElement {
        let matches = app.textFields.matching(identifier: title)
        return matches.allElementsBoundByIndex.last ?? matches.firstMatch
    }
    private func enter(_ text: String, into field: XCUIElement, in app: XCUIApplication, replacing: Bool = false) {
        reveal(field, in: app)
        XCTAssertTrue(waitForStableControl(field, in: app))
        field.coordinate(withNormalizedOffset: CGVector(dx: 0.95, dy: 0.5)).tap()
        if replacing, let old = field.value as? String, !old.isEmpty, old != field.placeholderValue {
            for _ in old { field.typeKey(.rightArrow, modifierFlags: []) }
            field.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: old.count))
        }
        if !text.isEmpty { field.typeText(text) }
        let entered = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
            let value = field.value as? String
            return value == text || (text.isEmpty && (value == nil || value == field.placeholderValue))
        }, object: nil)
        XCTAssertEqual(XCTWaiter.wait(for: [entered], timeout: 5), .completed, "The field must retain the entered value whether input uses a software or hardware keyboard.\n\(field)")
    }
    private func dismissKeyboard(in app: XCUIApplication) {
        let hideKeyboard = app.keyboards.buttons["Hide keyboard"]
        if hideKeyboard.exists && hideKeyboard.isHittable {
            hideKeyboard.tap()
            let hidden = XCTNSPredicateExpectation(predicate: NSPredicate(format: "exists == false"), object: app.keyboards.firstMatch)
            _ = XCTWaiter.wait(for: [hidden], timeout: 3)
        }
        guard app.keyboards.firstMatch.exists else { return }
        let bounds = viewport(in: app)
        guard let scroller = app.collectionViews.allElementsBoundByIndex.last(where: { $0.frame.intersects(bounds) && $0.frame.height > 100 }) else { return }
        let frame = scroller.frame
        let bottom = min(frame.maxY - 40, bounds.minY + bounds.height * 0.5)
        let top = max(frame.minY + 35, bottom - 120)
        guard bottom > top + 40 else { return }
        let origin = scroller.coordinate(withNormalizedOffset: .zero)
        origin.withOffset(CGVector(dx: 35, dy: bottom - frame.minY)).press(forDuration: 0.05, thenDragTo: origin.withOffset(CGVector(dx: 35, dy: top - frame.minY)))
    }
    private func tap(_ element: XCUIElement, in app: XCUIApplication) {
        dismissKeyboard(in: app)
        reveal(element, in: app)
        XCTAssertTrue(waitForStableControl(element, in: app), "Control did not settle before tapping: \(element)")
        element.tap()
    }
    private func waitForDisappearance(_ element: XCUIElement) -> Bool {
        let expectation = XCTNSPredicateExpectation(predicate: NSPredicate(format: "exists == false"), object: element)
        return XCTWaiter.wait(for: [expectation], timeout: 8) == .completed
    }
    private func waitForStableControl(_ element: XCUIElement, in app: XCUIApplication) -> Bool {
        var previous: CGRect?
        var stableSince: Date?
        let predicate = NSPredicate { _, _ in
            guard self.visible(element, in: app) else { previous = nil; stableSince = nil; return false }
            let frame = element.frame
            if previous != frame { previous = frame; stableSince = Date(); return false }
            return Date().timeIntervalSince(stableSince ?? Date()) >= 0.35
        }
        return XCTWaiter.wait(for: [XCTNSPredicateExpectation(predicate: predicate, object: nil)], timeout: 6) == .completed
    }
    private func viewport(in app: XCUIApplication) -> CGRect {
        let window = app.windows.firstMatch
        return window.exists ? window.frame : app.frame
    }
    private func bottomTabTop(in app: XCUIApplication, bounds: CGRect) -> CGFloat {
        app.tabBars.allElementsBoundByIndex.map(\.frame)
            .filter { $0.height > 0 && $0.minY > bounds.midY && $0.intersects(bounds) }
            .map(\.minY).min() ?? bounds.maxY
    }
    private func visible(_ element: XCUIElement, in app: XCUIApplication) -> Bool {
        guard element.exists, element.isHittable else { return false }
        let frame = element.frame
        let bounds = viewport(in: app)
        guard frame.width > 0, frame.height > 0, bounds.contains(CGPoint(x: frame.midX, y: frame.midY)) else { return false }
        let keyboard = app.keyboards.firstMatch
        let keyboardTop = keyboard.exists && keyboard.frame.height > 0 ? keyboard.frame.minY : bounds.maxY
        return frame.midY < min(keyboardTop, bottomTabTop(in: app, bounds: bounds))
    }
    private func reveal(_ element: XCUIElement, in app: XCUIApplication, attempts: Int = 8, searchAbove: Bool = false) {
        if !element.exists { _ = element.waitForExistence(timeout: 2) }
        for attempt in 0...attempts {
            if visible(element, in: app) { return }
            guard attempt < attempts else { break }
            let bounds = viewport(in: app)
            let collections = app.collectionViews.allElementsBoundByIndex.filter { $0.frame.intersects(bounds) && $0.frame.width > 50 && $0.frame.height > 50 }
            let scrollViews = app.scrollViews.allElementsBoundByIndex.filter { $0.frame.intersects(bounds) && $0.frame.width > 50 && $0.frame.height > 50 }
            guard let scroller = collections.last ?? scrollViews.last else { _ = element.waitForExistence(timeout: 2); continue }
            let frame = scroller.frame
            let keyboard = app.keyboards.firstMatch
            let keyboardTop = keyboard.exists && keyboard.frame.height > 0 ? keyboard.frame.minY : bounds.maxY
            let top = max(frame.minY, bounds.minY) + 45
            let bottom = min(frame.maxY, keyboardTop, bottomTabTop(in: app, bounds: bounds), bounds.maxY) - 25
            guard bottom > top + 30 else { XCTFail("No visible form area to scroll: window \(bounds), scroller \(frame), keyboard top \(keyboardTop)"); return }
            let towardTop = searchAbove || (element.exists && element.frame.maxY <= top)
            let origin = scroller.coordinate(withNormalizedOffset: .zero)
            let x = min(frame.maxX - 25, frame.minX + 35)
            let inset = (bottom - top) * 0.2
            let dragTop = top + inset
            let dragBottom = bottom - inset
            let start = origin.withOffset(CGVector(dx: x - frame.minX, dy: (towardTop ? dragTop : dragBottom) - frame.minY))
            let end = origin.withOffset(CGVector(dx: x - frame.minX, dy: (towardTop ? dragBottom : dragTop) - frame.minY))
            start.press(forDuration: 0.05, thenDragTo: end)
        }
        XCTFail("Expected reachable Coach control: \(element)\n\(app.debugDescription)")
    }
}
