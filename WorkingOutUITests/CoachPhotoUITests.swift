import XCTest

/// Add the two images from scripts/make_coach_photo_fixtures.py immediately
/// before running, so they are first in the newest-first system picker. Stock
/// Simulator photos can remain; no library clearing or real photos are needed.
@MainActor
final class CoachPhotoUITests: XCTestCase {
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

    func testCancelPhotoPickerLeavesNoAppCopies() {
        let app = launchBody()
        defer { app.terminate() }
        tap(app.buttons["coach.body.add_photo"], in: app)
        XCTAssertTrue(app.buttons["Cancel"].waitForExistence(timeout: 10), app.debugDescription)
        tap(app.buttons["Cancel"], in: app)
        XCTAssertTrue(app.navigationBars["Body Progress"].waitForExistence(timeout: 5))
        XCTAssertEqual(photoEditors(in: app).count, 0)
        let empty = app.staticTexts["No photos in this range. Measurements work without photos."]
        reveal(empty, in: app)
        XCTAssertTrue(empty.exists)
    }

    func testPhotoImportCompareCorrectAndDeletePreservesLibraryOriginals() {
        let app = launchBody()
        defer { app.terminate() }
        tap(app.buttons["coach.body.add_photo"], in: app)
        selectBothSyntheticPhotos(in: app)
        tap(pickerAddButton(in: app), in: app)
        // Completion feedback is in the first section of the lazy List.
        app.collectionViews.firstMatch.swipeDown()
        app.collectionViews.firstMatch.swipeDown()
        let imported = app.staticTexts["coach.body.saved"]
        let completed = XCTNSPredicateExpectation(predicate: NSPredicate(format: "label == %@", "Imported 2 app-owned photo copies."), object: imported)
        XCTAssertEqual(XCTWaiter.wait(for: [completed], timeout: 30), .completed, app.debugDescription)
        let editors = photoEditors(in: app)
        reveal(editors.firstMatch, in: app)
        for _ in 0..<3 where editors.count < 2 { app.collectionViews.firstMatch.swipeUp() }
        XCTAssertEqual(editors.count, 2)
        let ids = editors.allElementsBoundByIndex.map { String($0.identifier.dropFirst("coach.body.photo.edit.".count)) }
        for id in ids {
            tap(app.buttons["coach.body.photo.compare.\(id)"], in: app)
            XCTAssertFalse(app.navigationBars["Photo Details"].exists, "Compare must not also invoke the row's Edit action")
        }
        let comparison = app.descendants(matching: .any).matching(identifier: "coach.body.photo.comparison").firstMatch
        reveal(comparison, in: app)
        XCTAssertTrue(comparison.exists)
        for id in ids {
            XCTAssertTrue(app.images["coach.body.photo.image.\(id).full"].waitForExistence(timeout: 10), "Both retained images must decode for comparison")
        }
        tap(app.buttons["coach.body.photo.edit.\(ids[0])"], in: app)
        XCTAssertTrue(app.navigationBars["Photo Details"].waitForExistence(timeout: 5))
        let pose = app.textFields["coach.body.photo.pose"]
        reveal(pose, in: app)
        tap(pose, in: app)
        pose.typeText("Synthetic comparison")
        chooseYesterday(in: app)
        tap(app.buttons["coach.body.photo.save"], in: app)
        reveal(app.buttons["coach.body.photo.edit.\(ids[0])"], in: app)
        XCTAssertEqual(photoEditors(in: app).count, 2, "Correcting metadata retains photo identity")
        XCTAssertTrue(app.staticTexts["Synthetic comparison"].firstMatch.exists)
        let civil = DateFormatter(); civil.locale = Locale(identifier: "en_US_POSIX"); civil.calendar = Calendar(identifier: .gregorian); civil.dateFormat = "yyyy-MM-dd"
        XCTAssertTrue(app.staticTexts[civil.string(from: Calendar.current.date(byAdding: .day, value: -1, to: Date())!)].firstMatch.exists)

        // Reopen the saved copy to verify metadata was persisted rather than
        // merely displayed in a local text-field binding.
        tap(app.buttons["coach.body.photo.edit.\(ids[0])"], in: app)
        XCTAssertEqual(app.textFields["coach.body.photo.pose"].value as? String, "Synthetic comparison")
        tap(app.buttons["coach.body.photo.delete"], in: app)
        waitUntilGone(app.buttons["coach.body.photo.edit.\(ids[0])"])
        tap(app.buttons["coach.body.photo.edit.\(ids[1])"], in: app)
        tap(app.buttons["coach.body.photo.delete"], in: app)
        waitUntilGone(app.buttons["coach.body.photo.edit.\(ids[1])"])
        XCTAssertEqual(photoEditors(in: app).count, 0)

        // Both source assets must still be independently selectable after the
        // two app-owned copies have been deleted. Cancel preserves an empty app.
        tap(app.buttons["coach.body.add_photo"], in: app)
        selectBothSyntheticPhotos(in: app)
        tap(app.buttons["Cancel"], in: app)
        XCTAssertTrue(app.navigationBars["Body Progress"].waitForExistence(timeout: 5))
        XCTAssertEqual(photoEditors(in: app).count, 0)
    }

    private func launchBody() -> XCUIApplication {
        let app = XCUIApplication()
        app.launchEnvironment["UITEST_MODE"] = "1"
        app.launchEnvironment["UITEST_RESET_STATE"] = "1"
        app.launchEnvironment["UITEST_START_TAB"] = "ai"
        app.launchArguments += ["-AppleLanguages", "(en)", "-AppleLocale", "en_US"]
        app.launch()
        XCUIDevice.shared.orientation = .portrait
        XCTAssertTrue(app.navigationBars["Coach"].waitForExistence(timeout: 10))
        tap(app.buttons["Weight, waist and photos"], in: app)
        XCTAssertTrue(app.navigationBars["Body Progress"].waitForExistence(timeout: 5))
        return app
    }
    private func photoEditors(in app: XCUIApplication) -> XCUIElementQuery {
        app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "coach.body.photo.edit."))
    }
    private func pickerAddButton(in app: XCUIApplication) -> XCUIElement {
        let done = app.navigationBars["Photos"].buttons["Done"]
        if done.exists { return done }
        return app.buttons.matching(NSPredicate(format: "label == 'Add' OR label BEGINSWITH 'Add (' OR label BEGINSWITH 'Add '")).firstMatch
    }
    private func pickerAssets(in app: XCUIApplication) -> [XCUIElement] {
        // The remote Photos grid exposes image frames but reports them as
        // non-hittable. Match the metadata on our two disposable fixtures.
        app.images.matching(NSPredicate(format: "identifier == 'PXGGridLayout-Info' AND label CONTAINS %@", "Synthetic Coach UI test image; no personal content"))
            .allElementsBoundByIndex.filter { $0.exists && $0.frame.width > 40 && $0.frame.height > 40 && app.frame.contains(CGPoint(x: $0.frame.midX, y: $0.frame.midY)) }
    }
    private func selectBothSyntheticPhotos(in app: XCUIApplication) {
        XCTAssertTrue(app.buttons["Cancel"].waitForExistence(timeout: 10), "Expected the system Photos picker")
        let available = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in self.pickerAssets(in: app).count >= 2 }, object: nil)
        XCTAssertEqual(XCTWaiter.wait(for: [available], timeout: 15), .completed, "Add the two synthetic PNG fixtures as the newest images before running. Stock Simulator photos may remain.\n\(app.debugDescription)")
        let assets = Array(pickerAssets(in: app).prefix(2))
        guard assets.count == 2 else { return }
        for asset in assets {
            asset.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
        }
        let ready = XCTNSPredicateExpectation(predicate: NSPredicate(format: "enabled == true"), object: pickerAddButton(in: app))
        XCTAssertEqual(XCTWaiter.wait(for: [ready], timeout: 5), .completed)
        // The import assertion below verifies that both selections arrived;
        // Photos' remote grid does not consistently expose isSelected.
    }
    private func chooseYesterday(in app: XCUIApplication) {
        let picker = app.datePickers["coach.body.photo.observed_date"]
        tap(picker, in: app)
        let calendar = Calendar.current
        let yesterday = calendar.date(byAdding: .day, value: -1, to: Date())!
        if calendar.component(.month, from: yesterday) != calendar.component(.month, from: Date()) {
            tap(app.buttons.matching(NSPredicate(format: "label CONTAINS[c] 'previous month'")).firstMatch, in: app)
        }
        let month = DateFormatter(); month.locale = Locale(identifier: "en_US"); month.dateFormat = "MMMM"
        let day = calendar.component(.day, from: yesterday)
        let pattern = ".*\\b" + month.string(from: yesterday) + "\\s+" + String(day) + "\\b.*"
        let full = app.buttons.matching(NSPredicate(format: "label MATCHES[c] %@", pattern)).firstMatch
        tap(full.exists ? full : app.buttons[String(day)].firstMatch, in: app)
        // A compact calendar stays open after selection and intercepts outside
        // touches. Dismiss it explicitly before interacting with the editor.
        let navigation = app.navigationBars["Photo Details"]
        XCTAssertTrue(navigation.exists)
        navigation.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
        XCTAssertTrue(app.buttons["coach.body.photo.save"].waitForExistence(timeout: 5))
    }
    private func waitUntilGone(_ element: XCUIElement) {
        let gone = XCTNSPredicateExpectation(predicate: NSPredicate(format: "exists == false"), object: element)
        XCTAssertEqual(XCTWaiter.wait(for: [gone], timeout: 8), .completed)
    }
    private func visible(_ element: XCUIElement, in app: XCUIApplication) -> Bool {
        guard element.exists, element.isHittable, element.frame.height > 0 else { return false }
        let center = CGPoint(x: element.frame.midX, y: element.frame.midY)
        guard app.frame.contains(center) else { return false }
        let keyboard = app.keyboards.firstMatch
        return !keyboard.exists || keyboard.frame.height == 0 || center.y < keyboard.frame.minY
    }
    private func tap(_ element: XCUIElement, in app: XCUIApplication) {
        let hideKeyboard = app.keyboards.buttons["Hide keyboard"]
        if hideKeyboard.exists && hideKeyboard.isHittable {
            hideKeyboard.tap()
            let hidden = XCTNSPredicateExpectation(predicate: NSPredicate(format: "exists == false"), object: app.keyboards.firstMatch)
            _ = XCTWaiter.wait(for: [hidden], timeout: 3)
        }
        reveal(element, in: app)
        var previous: CGRect?
        var stableSince: Date?
        let settled = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
            guard self.visible(element, in: app) else { previous = nil; stableSince = nil; return false }
            if previous != element.frame { previous = element.frame; stableSince = Date(); return false }
            return Date().timeIntervalSince(stableSince ?? Date()) >= 0.35
        }, object: nil)
        XCTAssertEqual(XCTWaiter.wait(for: [settled], timeout: 6), .completed)
        element.tap()
    }
    private func reveal(_ element: XCUIElement, in app: XCUIApplication) {
        if !element.exists { _ = element.waitForExistence(timeout: 2) }
        for _ in 0..<10 {
            if visible(element, in: app) { return }
            let collections = app.collectionViews.allElementsBoundByIndex.filter { $0.frame.intersects(app.frame) && $0.frame.width > 50 && $0.frame.height > 50 }
            let scrollViews = app.scrollViews.allElementsBoundByIndex.filter { $0.frame.intersects(app.frame) && $0.frame.width > 50 && $0.frame.height > 50 }
            guard let scroller = collections.last ?? scrollViews.last else { _ = element.waitForExistence(timeout: 1); continue }
            let frame = scroller.frame
            let keyboard = app.keyboards.firstMatch
            let keyboardTop = keyboard.exists && keyboard.frame.height > 0 ? keyboard.frame.minY : app.frame.maxY
            let tabTop = app.tabBars.allElementsBoundByIndex.filter { $0.frame.minY > app.frame.midY && $0.frame.height > 0 }.map { $0.frame.minY }.min() ?? app.frame.maxY
            let top = max(frame.minY, app.frame.minY) + 45
            let bottom = min(frame.maxY, keyboardTop, tabTop, app.frame.maxY) - 25
            guard bottom > top + 30 else { break }
            let up = element.exists && element.frame.maxY <= top
            let origin = scroller.coordinate(withNormalizedOffset: .zero)
            let x = min(frame.maxX - 25, frame.minX + 35)
            origin.withOffset(CGVector(dx: x - frame.minX, dy: (up ? top : bottom) - frame.minY)).press(forDuration: 0.05, thenDragTo: origin.withOffset(CGVector(dx: x - frame.minX, dy: (up ? bottom : top) - frame.minY)))
        }
        XCTFail("Expected reachable photo control: \(element)\n\(app.debugDescription)")
    }
}
