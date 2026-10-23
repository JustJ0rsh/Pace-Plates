import XCTest

@MainActor
final class CoachImportGuidanceUITests: XCTestCase {
    override func setUpWithError() throws { continueAfterFailure = false }
    override func record(_ issue: XCTIssue) {
        let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        attachment.name = "Import guidance issue \(Date().timeIntervalSince1970)"
        attachment.lifetime = .keepAlways
        add(attachment)
        super.record(issue)
    }

    func testAddPlanSeparatesPasteAndFileWithoutTitleOverlap() {
        let app = launch()
        defer { app.terminate() }
        tap(app.buttons["coach.add_plan"], in: app)
        let title = app.navigationBars["Add Plan"]
        let paste = app.buttons["coach.add_plan.paste"]
        reveal(paste, in: app)
        XCTAssertGreaterThanOrEqual(paste.frame.minY, title.frame.maxY, "The first import choice must be below the navigation title.")
        XCTAssertEqual(paste.label, "Paste Program JSON")
        XCTAssertTrue(app.buttons["coach.add_plan.file"].exists)
        paste.tap()
        XCTAssertTrue(app.navigationBars["Paste Program JSON"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.textViews["coach.import.paste"].exists)
        XCTAssertFalse(app.buttons["coach.import.review"].isEnabled)
        app.navigationBars["Paste Program JSON"].buttons.element(boundBy: 0).tap()
        tap(app.buttons["coach.add_plan.file"], in: app)
        XCTAssertTrue(app.navigationBars["Import JSON File"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["coach.import.choose_file"].exists)
        XCTAssertFalse(app.textViews["coach.import.paste"].exists, "The file route should begin with the file chooser, not an empty paste editor.")
    }

    func testPromptContainsExecutablePrescriptionsAndAnExplicitReturnStep() {
        let app = launch()
        defer { app.terminate() }
        tap(app.buttons["coach.add_plan"], in: app)
        tap(app.buttons["coach.add_plan.prompt"], in: app)
        tap(app.buttons["coach.prompt.preview"], in: app)
        let content = app.staticTexts["coach.prompt.content"]
        reveal(content, in: app, requiresHitTarget: false)
        XCTAssertTrue(content.exists)
        let prompt = content.label
        XCTAssertTrue(prompt.contains("EVERY set"))
        XCTAssertTrue(prompt.contains("sessionTemplates alone do not schedule anything"))
        XCTAssertTrue(prompt.contains("120 and 60 seconds"))
        XCTAssertTrue(prompt.contains("COMPLETE JSON SCHEMA"))
        XCTAssertTrue(prompt.contains("pace-and-plates.coach-program"))
        XCTAssertFalse(prompt.contains("PERSONAL CONTEXT I CHOSE TO INCLUDE"), "Personal context is opt-in.")
        XCTAssertFalse(prompt.contains("proposed implementation specification"), "Copy instructions should target program generation, not app implementation.")
        app.buttons["coach.prompt.copy"].tap()
        XCTAssertEqual(app.buttons["coach.prompt.copy"].label, "Copied")
        tap(app.buttons["coach.prompt.paste_reply"], in: app)
        XCTAssertTrue(app.navigationBars["Paste Program JSON"].waitForExistence(timeout: 5))
    }

    /// Prerequisite: copy scripts/fixtures/Coach Import Test.json into the isolated
    /// Simulator's Files > On My iPhone/iPad. This test uses the actual system picker.
    /// It reports a skip if the fixture is not present; a skip is not import coverage.
    func testNativeJSONFileProducesReviewedStrengthAndRunSchedule() throws {
        let app = launch()
        defer { app.terminate() }
        tap(app.buttons["coach.add_plan"], in: app)
        tap(app.buttons["coach.add_plan.file"], in: app)
        tap(app.buttons["coach.import.choose_file"], in: app)
        let filename = ProcessInfo.processInfo.environment["COACH_IMPORT_FIXTURE_FILENAME"] ?? "Coach Import Test.json"
        let stem = (filename as NSString).deletingPathExtension
        let predicate = NSPredicate(format: "label == %@ OR label == %@ OR label BEGINSWITH %@ OR label BEGINSWITH %@", filename, stem, filename + ",", stem + ",")
        func file() -> XCUIElement {
            let fileView = app.collectionViews["File View"]
            let cells = fileView.exists ? fileView.cells : app.cells
            return cells.matching(predicate).firstMatch
        }
        if !file().waitForExistence(timeout: 4) {
            let browseTab = app.tabBars.buttons["Browse"]
            let browse = browseTab.exists ? browseTab : app.buttons["Browse"].firstMatch
            XCTAssertTrue(browse.waitForExistence(timeout: 5), "The native Files picker must open before looking for its fixture.\n\(app.debugDescription)")
            browse.tap()
            if !file().waitForExistence(timeout: 2) {
                let phone = app.buttons["On My iPhone"].firstMatch
                let pad = app.buttons["On My iPad"].firstMatch
                let location = phone.exists ? phone : pad
                if location.waitForExistence(timeout: 3) { location.tap() }
                else {
                    let locationText = app.staticTexts.matching(NSPredicate(format: "label IN %@", ["On My iPhone", "On My iPad"] as NSArray)).firstMatch
                    if locationText.waitForExistence(timeout: 2) { locationText.tap() }
                }
            }
        }
        guard file().waitForExistence(timeout: 5) else {
            if app.staticTexts.matching(predicate).firstMatch.exists {
                XCTFail("The seeded fixture is visible but its selectable document cell was not found.\n\(app.debugDescription)")
                return
            }
            throw XCTSkip("Seed \(filename) in the isolated Simulator's On My iPhone/iPad Files storage to run native file-import coverage.")
        }
        let documentCell = file()
        XCTAssertTrue(documentCell.isEnabled, "The JSON document must be enabled by the importer's allowed file types.")
        XCTAssertTrue(documentCell.isHittable, "The selected document cell must be reachable in the system picker.")
        let icon = documentCell.images.firstMatch
        if icon.exists, icon.frame.width > 0, icon.frame.height > 0, documentCell.frame.intersects(icon.frame) {
            icon.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
        } else {
            documentCell.tap()
        }
        XCTAssertTrue(app.navigationBars["Review Program"].waitForExistence(timeout: 15), "Selecting a valid file must validate it and open review without a paste action.\n\(app.debugDescription)")
        XCTAssertTrue(app.staticTexts["File Import Test Plan"].exists)
        reveal(app.staticTexts["1 planned strength workout"], in: app)
        XCTAssertTrue(app.staticTexts["1 planned strength workout"].exists)
        XCTAssertTrue(app.staticTexts["1 planned run"].exists)
        XCTAssertFalse(app.buttons["coach.plan.activate"].isEnabled, "An unknown exercise still requires explicit mapping review.")
        let custom = app.switches["Create the reviewed custom exercises"]
        reveal(custom, in: app)
        custom.coordinate(withNormalizedOffset: CGVector(dx: 0.9, dy: 0.5)).tap()
        XCTAssertEqual(custom.value as? String, "1", "Creating custom exercises must be explicitly enabled before activation")
        let start = app.buttons["coach.plan.activate"]
        let enabled = XCTNSPredicateExpectation(predicate: NSPredicate(format: "enabled == true"), object: start)
        XCTAssertEqual(XCTWaiter.wait(for: [enabled], timeout: 5), .completed)
        start.tap()
        XCTAssertTrue(app.navigationBars["Program Saved"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.staticTexts["1 planned strength workout"].exists)
        XCTAssertTrue(app.staticTexts["1 planned run"].exists)
        tap(app.buttons["coach.plan.open_saved"], in: app)
        XCTAssertTrue(app.navigationBars["Your Plan"].waitForExistence(timeout: 5))
        let lift = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@ AND label CONTAINS %@", "coach.today.session.", "Import Test Lift")).firstMatch
        let run = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@ AND label CONTAINS %@", "coach.today.session.", "Import Test Run")).firstMatch
        reveal(lift, in: app)
        XCTAssertTrue(lift.exists)
        let liftID = String(lift.identifier.dropFirst("coach.today.session.".count))
        reveal(run, in: app)
        XCTAssertTrue(run.exists, "The file must produce separate, navigable workout and run occurrences.")
        let runID = String(run.identifier.dropFirst("coach.today.session.".count))
        XCTAssertNotNil(UUID(uuidString: liftID)); XCTAssertNotNil(UUID(uuidString: runID))
        XCTAssertNotEqual(liftID, runID)
        selectTab("Workouts", in: app)
        reveal(app.buttons["workouts.planned.session.\(liftID)"], in: app)
        tap(app.buttons["workouts.planned.all"], in: app)
        XCTAssertTrue(app.buttons["workouts.planned.session.\(liftID)"].waitForExistence(timeout: 5))
        selectTab("Runs", in: app)
        reveal(app.buttons["runs.planned.session.\(runID)"], in: app)
        tap(app.buttons["runs.planned.all"], in: app)
        XCTAssertTrue(app.buttons["runs.planned.session.\(runID)"].waitForExistence(timeout: 5), "Both tabs must reuse the exact imported occurrence IDs, including their full lists.")
        selectTab("Coach", in: app)
        tap(app.buttons["Plan options"], in: app)
        tap(app.buttons["Delete Program"], in: app)
        let sheet = app.sheets.firstMatch
        let popover = app.popovers.firstMatch
        if sheet.waitForExistence(timeout: 2) { sheet.buttons["Delete Program"].tap() }
        else {
            XCTAssertTrue(popover.waitForExistence(timeout: 3))
            popover.buttons["Delete Program"].tap()
        }
        XCTAssertTrue(app.navigationBars["Program Saved"].waitForExistence(timeout: 8))
        XCTAssertTrue(app.descendants(matching: .any).matching(identifier: "coach.plan.saved_unavailable").firstMatch.waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["coach.plan.open_saved"].exists, "Returning after deletion must not retain a stale link to the deleted model.")
    }

    private func launch() -> XCUIApplication {
        let app = XCUIApplication()
        app.launchEnvironment["UITEST_MODE"] = "1"
        app.launchEnvironment["UITEST_RESET_STATE"] = "1"
        app.launchEnvironment["UITEST_START_TAB"] = "ai"
        app.launch()
        return app
    }
    private func tap(_ element: XCUIElement, in app: XCUIApplication) {
        reveal(element, in: app); element.tap()
    }
    private func selectTab(_ title: String, in app: XCUIApplication) {
        let bottom = app.tabBars.buttons[title]
        let tab = bottom.exists ? bottom : app.buttons[title].firstMatch
        XCTAssertTrue(tab.waitForExistence(timeout: 5)); tab.tap()
    }
    private func reveal(_ element: XCUIElement, in app: XCUIApplication, requiresHitTarget: Bool = true) {
        if !element.exists { _ = element.waitForExistence(timeout: 3) }
        for _ in 0..<12 {
            let window = app.windows.firstMatch.exists ? app.windows.firstMatch.frame : app.frame
            let pinnedTop = app.descendants(matching: .any).matching(NSPredicate(format: "identifier IN %@", ["coach.plan.activate", "coach.plan.save_draft", "coach.plan.next_step", "coach.import.review", "coach.prompt.copy"])).allElementsBoundByIndex
                .filter { $0.frame.minY > window.midY && $0.frame.intersects(window) }.map { $0.frame.minY }.min() ?? window.maxY
            let navigationBottom = app.navigationBars.firstMatch.exists ? app.navigationBars.firstMatch.frame.maxY : window.minY
            // SwiftUI may report a switch as hittable while its thumb is covered by the footer.
            let switchVisible = !element.exists || element.elementType != .switch || (element.frame.midY > navigationBottom + 12 && element.frame.midY < pinnedTop - 12)
            if element.exists, !requiresHitTarget || (element.isHittable && element.frame.intersects(window) && switchVisible) { return }
            let collection = app.collectionViews.firstMatch
            let scroller = collection.exists ? collection : app.scrollViews.firstMatch
            guard scroller.exists else { break }
            let bounds = scroller.frame.intersection(window)
            // The central part of the visible form avoids system window edges and pinned actions.
            let origin = scroller.coordinate(withNormalizedOffset: .zero)
            let x = bounds.minX + 32 - scroller.frame.minX
            let top = bounds.minY + 36 - scroller.frame.minY
            let bottom = min(bounds.minY + bounds.height * 0.65, pinnedTop - 24) - scroller.frame.minY
            guard bottom > top + 30 else { break }
            let towardTop = element.exists && element.frame.maxY < bounds.minY
            origin.withOffset(CGVector(dx: x, dy: towardTop ? top : bottom))
                .press(forDuration: 0.05, thenDragTo: origin.withOffset(CGVector(dx: x, dy: towardTop ? bottom : top)))
        }
        XCTFail("Expected reachable import control: \(element)\n\(app.debugDescription)")
    }
}
