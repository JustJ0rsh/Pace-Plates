import XCTest

@MainActor
final class WorkingOutUITests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    func testOptimizationDataPaths() {
        let app = launchApp(startTab: "home", fixture: "optimization_checks")
        defer { app.terminate() }
        XCTAssertTrue(app.staticTexts["Optimization checks passed"].waitForExistence(timeout: 60),
                      app.staticTexts["optimization.checks"].label)
    }

    func testInterruptedRunRestoresPausedAfterRelaunch() {
        let app = launchApp(startTab: "home", fixture: nil, recovery: true)
        defer { app.terminate() }
        waitForElement(app.buttons["home.quickActions.startRun"])
        app.buttons["home.quickActions.startRun"].tap()
        waitForElement(app.buttons["Start"])
        app.buttons["Start"].tap()
        waitForElement(app.buttons["Pause"])
        app.buttons["Pause"].tap()
        waitForElement(app.buttons["Resume"])
        app.terminate()
        app.launchEnvironment["UITEST_RESET_STATE"] = "0"
        app.launch()
        let recovered = app.alerts["Recovered unfinished activity"]
        XCTAssertTrue(recovered.waitForExistence(timeout: 10))
        recovered.buttons["OK"].tap()
        waitForElement(app.buttons["home.activeActivity.resume"])
        app.buttons["home.activeActivity.resume"].tap()
        waitForElement(app.buttons["Resume"])
        XCTAssertFalse(app.buttons["Pause"].exists, "Recovered activity must stay paused")
    }

    func testHomeScreenshot() {
        let app = launchApp(startTab: "home")

        waitForElement(app.buttons["home.settings.button"])
        XCTAssertTrue(app.navigationBars["Home"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["Start Workout"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["Start Run"].exists)
        XCTAssertTrue(app.buttons["Log Weight"].exists)
        XCTAssertFalse(app.buttons["Choose Template"].exists)
        XCTAssertFalse(app.buttons["Walk"].exists)
        XCTAssertFalse(app.buttons["Hike"].exists)
        XCTAssertFalse(app.buttons["Cycle"].exists)
        XCTAssertFalse(app.buttons["Row"].exists)
        XCTAssertFalse(app.buttons["home.activeActivity.resume"].exists)

        snapshot("01_home", waitForLoadingIndicator: false)
    }

    func testSettingsNavigationOpensFromHomeToolbar() {
        let app = launchApp(startTab: "home")

        let settingsButton = app.buttons["home.settings.button"]
        waitForElement(settingsButton)
        XCTAssertTrue(app.navigationBars["Home"].waitForExistence(timeout: 5))

        settingsButton.tap()

        XCTAssertTrue(app.navigationBars["Settings"].waitForExistence(timeout: 5))
        waitForAnchor("settings.ready", in: app, timeout: 5)
    }

    func testHomeQuickActionContextMenusStayScopedToPressedButton() {
        let app = launchApp(startTab: "home")

        let startWorkout = app.buttons["home.quickActions.startWorkout"]
        let startRun = app.buttons["home.quickActions.startRun"]
        waitForElement(startWorkout)
        waitForElement(startRun)

        startWorkout.press(forDuration: 1.1)
        XCTAssertTrue(app.buttons["Choose Template"].waitForExistence(timeout: 3))
        XCTAssertFalse(app.buttons["Walk"].exists)

        app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.1)).tap()
        XCTAssertTrue(startRun.waitForExistence(timeout: 3))

        startRun.press(forDuration: 1.1)
        XCTAssertTrue(app.buttons["Walk"].waitForExistence(timeout: 3))
        XCTAssertTrue(app.buttons["Hike"].exists)
        XCTAssertTrue(app.buttons["Cycle"].exists)
        XCTAssertFalse(app.buttons["Choose Template"].exists)
    }

    func testActiveRunKeepsItsActivityTypeAcrossEntryPoints() {
        let app = launchApp(startTab: "home")
        defer { app.terminate() }

        let startRun = app.buttons["home.quickActions.startRun"]
        reveal(startRun, in: app, attempts: 2)
        startRun.tap()

        XCTAssertTrue(app.navigationBars["Tracking Run"].waitForExistence(timeout: 5))
        let start = app.buttons["Start"]
        waitForElement(start)
        start.tap()
        waitForElement(app.buttons["Pause"])

        app.buttons["Done"].tap()
        let resumeActivity = app.buttons["home.activeActivity.resume"]
        waitForElement(resumeActivity)
        XCTAssertTrue(resumeActivity.label.contains("Resume Run"))
        XCTAssertFalse(app.buttons["home.quickActions.startRun"].exists)

        resumeActivity.tap()

        XCTAssertTrue(
            app.navigationBars["Tracking Run"].waitForExistence(timeout: 5),
            "Resuming from Home must preserve the active run type."
        )
        app.buttons["Done"].tap()
        waitForElement(app.buttons["home.activeActivity.resume"])
        snapshot("07_home_resume_after", waitForLoadingIndicator: false)
    }

    func testWorkoutsScreenshot() {
        let app = launchApp(startTab: "workouts")
        waitForAnchor("workouts.ready", in: app)
        XCTAssertTrue(app.navigationBars["Workouts"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["You lifted 38,880 lbs in the last 7 days."].waitForExistence(timeout: 5))

        snapshot("02_workouts", waitForLoadingIndicator: false)
    }

    func testRunsScreenshot() {
        let app = launchApp(startTab: "runs")
        waitForAnchor("runs.ready", in: app)
        XCTAssertTrue(app.navigationBars["Runs"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["Longest activity: 4.1 mi."].waitForExistence(timeout: 5))

        snapshot("03_runs", waitForLoadingIndicator: false)
    }

    func testWeightScreenshot() {
        let app = launchApp(startTab: "weight")
        waitForAnchor("weight.ready", in: app)
        XCTAssertTrue(app.navigationBars["Weight"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["Down 2.0 lbs over 7 days."].waitForExistence(timeout: 5))

        snapshot("04_weight", waitForLoadingIndicator: false)
    }

    func testAppStoreScreenshotSet() {
        let home = launchApp(startTab: "home")
        waitForElement(home.buttons["home.today.plan.start"])
        waitForElement(home.buttons["home.today.plan.options"])
        captureAppStoreScreenshot("01-home")
        home.terminate()

        let workouts = launchApp(startTab: "workouts")
        waitForAnchor("workouts.ready", in: workouts)
        XCTAssertTrue(workouts.navigationBars["Workouts"].waitForExistence(timeout: 5))
        captureAppStoreScreenshot("02-workouts")
        workouts.terminate()

        let coach = launchApp(startTab: "ai")
        XCTAssertTrue(coach.navigationBars["Coach"].waitForExistence(timeout: 5))
        waitForElement(coach.buttons["coach.runningPlans"])
        captureAppStoreScreenshot("03-coach")
        coach.terminate()

        let runs = launchApp(startTab: "runs")
        waitForAnchor("runs.ready", in: runs)
        XCTAssertTrue(runs.navigationBars["Runs"].waitForExistence(timeout: 5))
        captureAppStoreScreenshot("04-runs")
        runs.terminate()

        let weight = launchApp(startTab: "weight")
        waitForAnchor("weight.ready", in: weight)
        XCTAssertTrue(weight.navigationBars["Weight"].waitForExistence(timeout: 5))
        captureAppStoreScreenshot("05-weight")
        weight.terminate()

        let runningAssistant = launchApp(startTab: "ai")
        let runningPlans = runningAssistant.buttons["coach.runningPlans"]
        waitForElement(runningPlans)
        runningPlans.tap()
        XCTAssertTrue(
            runningAssistant.navigationBars["Running Assistant"]
                .waitForExistence(timeout: 5)
        )
        waitForElement(runningAssistant.staticTexts["5K Momentum"])
        captureAppStoreScreenshot("06-running-assistant")
        runningAssistant.terminate()
    }

    func testFindHistoryFiltersEachLogAndOpensWeightDetails() {
        let workouts = launchApp(startTab: "workouts")
        waitForAnchor("workouts.ready", in: workouts)
        let workoutSearch = workouts.textFields["workouts.history.filters.search"]
        reveal(workoutSearch, in: workouts)
        snapshot("09_workout_history_after", waitForLoadingIndicator: false)
        focusAndType("Bench Press", into: workoutSearch, in: workouts)
        XCTAssertTrue(workouts.staticTexts["1 result"].waitForExistence(timeout: 5))
        XCTAssertTrue(workouts.staticTexts["Upper Body Focus"].exists)
        workouts.buttons["workouts.history.filters.clear_filters"].tap()
        XCTAssertTrue(workouts.staticTexts["3 results"].waitForExistence(timeout: 5))

        let thirtyDays = workouts.buttons["workouts.history.filters.range.days30"]
        waitForElement(thirtyDays)
        thirtyDays.tap()
        XCTAssertTrue(workouts.staticTexts["3 results"].waitForExistence(timeout: 5))
        focusAndType("No such workout", into: workoutSearch, in: workouts)
        waitForAnchor("workouts.history.no_results", in: workouts)
        if workouts.keyboards.buttons["Search"].exists {
            workouts.keyboards.buttons["Search"].tap()
            XCTAssertTrue(
                workouts.keyboards.firstMatch.waitForNonExistence(timeout: 2),
                "Submitting workout history search should dismiss the keyboard."
            )
        }
        let clearNoResults = workouts.buttons["workouts.history.no_results.clear_filters"]
        reveal(clearNoResults, in: workouts, attempts: 2)
        clearNoResults.tap()
        XCTAssertTrue(workouts.staticTexts["3 results"].waitForExistence(timeout: 5))
        workouts.terminate()

        let runs = launchApp(startTab: "runs")
        waitForAnchor("runs.ready", in: runs)
        let runSearch = runs.textFields["runs.history.filters.search"]
        reveal(runSearch, in: runs)
        focusAndType("Walk", into: runSearch, in: runs)
        XCTAssertTrue(runs.staticTexts["1 result"].waitForExistence(timeout: 5))
        runs.buttons["runs.history.filters.clear_filters"].tap()
        XCTAssertTrue(runs.staticTexts["3 results"].waitForExistence(timeout: 5))

        if runs.keyboards.buttons["Search"].exists {
            runs.keyboards.buttons["Search"].tap()
            XCTAssertTrue(
                runs.keyboards.firstMatch.waitForNonExistence(timeout: 2),
                "Submitting run history search should dismiss the keyboard."
            )
        }
        let runOptions = runs.scrollViews["runs.history.filters.options"]
        let runningFilter = runs.buttons["runs.history.filters.category.running"]
        for _ in 0..<3 where !runningFilter.isHittable {
            runOptions.swipeLeft()
        }
        waitForElement(runningFilter)
        runningFilter.tap()
        XCTAssertTrue(runs.staticTexts["2 results"].waitForExistence(timeout: 5))
        runs.buttons["runs.history.filters.clear_filters"].tap()
        XCTAssertTrue(runs.staticTexts["3 results"].waitForExistence(timeout: 5))
        runs.terminate()

        let weight = launchApp(startTab: "weight")
        waitForAnchor("weight.ready", in: weight)
        let weightSearch = weight.textFields["weight.history.filters.search"]
        reveal(weightSearch, in: weight)
        focusAndType("184.6", into: weightSearch, in: weight)
        XCTAssertTrue(weight.staticTexts["1 result"].waitForExistence(timeout: 5))

        if weight.keyboards.buttons["Search"].exists {
            weight.keyboards.buttons["Search"].tap()
        }
        let matchingWeight = weight.staticTexts["184.6 lbs"]
        reveal(matchingWeight, in: weight)
        matchingWeight.tap()
        XCTAssertTrue(weight.staticTexts["Weight Entry"].waitForExistence(timeout: 5))
    }

    func testWearableInboxConsolidatesOuraDuplicatesAndKeepsHeartRate() {
        let app = openRepairedWearableInbox(
            fixture: "wearable_inbox_duplicates",
            expectedPendingCount: 1
        )

        XCTAssertTrue(app.staticTexts["132 bpm"].waitForExistence(timeout: 5))
        XCTAssertEqual(
            wearableInboxItems(in: app).count,
            1,
            "Expected duplicate Oura imports to consolidate into one local inbox row."
        )
    }

    func testWearableInboxKeepsSameTimeOuraRowsWithDistinctSyncIdentifiers() {
        let app = openRepairedWearableInbox(
            fixture: "wearable_inbox_distinct_oura_sync_ids",
            expectedPendingCount: 2
        )

        XCTAssertEqual(
            wearableInboxItems(in: app).count,
            2,
            "Different nonempty Health sync identifiers must remain separate workouts."
        )
    }

    func testWearableInboxDoesNotTreatCourageAsOura() {
        let app = openRepairedWearableInbox(
            fixture: "wearable_inbox_courage_source",
            expectedPendingCount: 2
        )

        XCTAssertEqual(
            wearableInboxItems(in: app).count,
            2,
            "A source merely containing the letters 'oura' must not use Oura deduplication."
        )
    }

    func testWearableInboxConsolidatesOuraAndAppleWatchAndKeepsHeartRate() {
        let app = openRepairedWearableInbox(
            fixture: "wearable_inbox_oura_apple_watch",
            expectedPendingCount: 1
        )

        XCTAssertEqual(
            wearableInboxItems(in: app).count,
            1,
            "Near-identical Oura and Apple Watch strength records should share one inbox row."
        )
        XCTAssertTrue(
            app.staticTexts["137 bpm"].waitForExistence(timeout: 5),
            "The consolidated row should retain the available Apple Watch heart rate."
        )
    }

    func testWearableReplacementAcrossBatchesPreservesLinkAndUsesCorrectedMetrics() {
        let app = launchApp(
            startTab: "workouts",
            fixture: "wearable_inbox_replacement_batches"
        )
        waitForAnchor("workouts.ready", in: app)

        let linkedWorkout = app.staticTexts["Replacement Linked Workout"]
        reveal(linkedWorkout, in: app)
        waitForElement(linkedWorkout)
        linkedWorkout.tap()

        XCTAssertTrue(
            app.navigationBars["Replacement Linked Workout"]
                .waitForExistence(timeout: 5)
        )
        XCTAssertTrue(app.staticTexts["137"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["Avg bpm"].exists)
        XCTAssertTrue(app.staticTexts["425"].exists)
        XCTAssertFalse(
            app.staticTexts["111"].exists,
            "A higher-version replacement must not leave stale heart-rate data."
        )
    }

    func testRetiredWearableReplacementDoesNotResurrectAnOlderUUID() {
        let app = launchApp(
            startTab: "workouts",
            fixture: "wearable_inbox_replacement_retirement"
        )
        waitForAnchor("workouts.ready", in: app)

        let localWorkout = app.staticTexts["Replacement Linked Workout"]
        reveal(localWorkout, in: app)
        waitForElement(localWorkout)
        localWorkout.tap()

        XCTAssertTrue(
            app.navigationBars["Replacement Linked Workout"]
                .waitForExistence(timeout: 5)
        )
        XCTAssertFalse(
            app.staticTexts["Avg bpm"].exists,
            "Expiring the replacement tombstone should clear the retired Health link."
        )
        XCTAssertFalse(
            app.staticTexts["137"].exists,
            "The old replacement metrics must not be resurrected through a retired alias."
        )
    }

    func testCardioInboxLinksOuraMetricsToSuggestedWalkWithoutDuplicate() {
        let app = launchApp(
            startTab: "runs",
            fixture: "cardio_inbox_unique_match"
        )
        waitForAnchor("runs.ready", in: app)

        let inbox = app.buttons["runs.cardioInbox"]
        waitForElement(inbox)
        let pendingCount = XCTNSPredicateExpectation(
            predicate: NSPredicate(format: "label CONTAINS %@", "1 pending"),
            object: inbox
        )
        XCTAssertEqual(
            XCTWaiter().wait(for: [pendingCount], timeout: 5),
            .completed
        )

        inbox.tap()
        XCTAssertTrue(app.navigationBars["Cardio Inbox"].waitForExistence(timeout: 5))
        waitForAnchor("cardio.inbox.ready", in: app)
        XCTAssertTrue(app.staticTexts["Oura"].exists)
        XCTAssertTrue(app.staticTexts["112 bpm"].exists)
        XCTAssertTrue(app.staticTexts["Suggested match"].exists)
        snapshot("11_cardio_inbox_after", waitForLoadingIndicator: false)

        let link = app.buttons["Link Suggested Activity"]
        waitForElement(link)
        link.tap()
        waitForAnchor("cardio.inbox.empty", in: app)

        app.navigationBars["Cardio Inbox"].buttons.firstMatch.tap()
        waitForAnchor("runs.ready", in: app)
        XCTAssertTrue(
            app.staticTexts["1 result"].waitForExistence(timeout: 5),
            "Linking Oura metrics must not insert a duplicate walk."
        )

        let linkedWalk = app.staticTexts["2.1 mi • 228 kcal"]
        reveal(linkedWalk, in: app)
        linkedWalk.tap()
        XCTAssertTrue(app.navigationBars["Run Details"].waitForExistence(timeout: 5))
        XCTAssertTrue(
            app.staticTexts["Heart-rate data from Oura"]
                .waitForExistence(timeout: 5)
        )
    }

    func testSettingsScreenshot() {
        let app = launchApp(startTab: "home")

        openSettingsRoot(in: app)
        openSettingsSubpage("Health & Sync", in: app, snapshotName: "05a_settings_health_sync")
        openSettingsSubpage("Backup & Data", in: app, snapshotName: "05c_settings_backup_data")
        openSettingsSubpage("Developer", in: app, snapshotName: "05d_settings_developer")
        for _ in 0..<4 {
            app.swipeDown()
        }

        snapshot("05_settings", waitForLoadingIndicator: false)
    }

    func testEmptyStatePrimaryActions() {
        let workouts = launchApp(startTab: "workouts", fixture: nil)
        waitForAnchor("workouts.ready", in: workouts)
        XCTAssertTrue(workouts.buttons["Start First Workout"].waitForExistence(timeout: 5))
        XCTAssertTrue(workouts.buttons["Choose Template"].exists)
        workouts.terminate()

        let runs = launchApp(startTab: "runs", fixture: nil)
        waitForAnchor("runs.ready", in: runs)
        XCTAssertTrue(runs.buttons["Start First Run"].waitForExistence(timeout: 5))
        XCTAssertTrue(runs.buttons["Log Past Run"].exists)
        XCTAssertTrue(runs.buttons["Check Health Inbox"].exists)
        runs.terminate()

        let weight = launchApp(startTab: "weight", fixture: nil)
        waitForAnchor("weight.ready", in: weight)
        XCTAssertTrue(weight.buttons["Log Weight"].waitForExistence(timeout: 5))
        XCTAssertTrue(weight.buttons["Import from Health"].exists)
        weight.terminate()
    }

    func testCoachSurfaceAndHistoryNavigation() {
        let app = launchApp(startTab: "ai")

        XCTAssertTrue(app.navigationBars["Coach"].waitForExistence(timeout: 5))
        let historyButton = app.buttons["Coach history"]
        waitForElement(historyButton)
        historyButton.tap()
        XCTAssertTrue(app.navigationBars["AI History"].waitForExistence(timeout: 5))
    }

    func testAIAskSupportsGuidedAndFreeFormQuestions() {
        let app = launchApp(startTab: "ai")

        openAIAsk(in: app)
        let questionField = app.textFields["ai.question.field"]
        waitForElement(questionField)
        let promptIDs = [
            "strength-block",
            "endurance-build",
            "hybrid-strength-cardio",
            "health-recovery-audit",
            "muscle-gain-nutrition",
            "running-speed-endurance",
        ]
        waitForElement(app.buttons["ai.quickPrompt.strength-block"])
        snapshot("08_ai_ask_after", waitForLoadingIndicator: false)

        for promptID in promptIDs {
            let identifier = "ai.quickPrompt.\(promptID)"
            for _ in 0..<4 where !app.buttons[identifier].exists {
                app.swipeUp()
            }
            waitForElement(app.buttons[identifier])
            XCTAssertEqual(app.buttons.matching(identifier: identifier).count, 1)
        }

        focusAndType("How should I pace an easy run?", into: questionField, in: app)
        let send = app.buttons["ai.question.send"]
        waitForElement(send)
        send.tap()

        XCTAssertTrue(app.staticTexts["How should I pace an easy run?"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["ai.promptIdeas.menu"].waitForExistence(timeout: 5))
        XCTAssertEqual(questionField.value as? String, "Ask a question…")
    }

    func testAIAskReflowsAtAccessibilityTextSize() {
        let app = launchApp(
            startTab: "ai",
            contentSizeCategory: "UICTContentSizeCategoryAccessibilityL"
        )

        openAIAsk(in: app)
        let strength = app.buttons["ai.quickPrompt.strength-block"]
        let endurance = app.buttons["ai.quickPrompt.endurance-build"]
        waitForElement(strength)
        waitForElement(endurance)

        XCTAssertEqual(strength.frame.minX, endurance.frame.minX, accuracy: 2)
        XCTAssertGreaterThan(endurance.frame.minY, strength.frame.maxY)
        XCTAssertTrue(app.textFields["ai.question.field"].exists)
        snapshot("10_ai_ask_accessibility_after", waitForLoadingIndicator: false)
    }

    func testToolbarActionSheetsAndCoachOwnsRunningPlans() {
        let workouts = launchApp(startTab: "workouts")
        waitForAnchor("workouts.ready", in: workouts)
        workouts.buttons["Add Workout"].tap()
        XCTAssertTrue(workouts.navigationBars["Workout Actions"].waitForExistence(timeout: 5))
        waitForElement(workouts.buttons["workouts.action.start_now"])
        XCTAssertTrue(workouts.buttons["workouts.action.log_past"].exists)
        XCTAssertTrue(workouts.buttons["workouts.action.use_template"].exists)
        workouts.buttons["Cancel"].tap()
        workouts.terminate()

        let runs = launchApp(startTab: "runs")
        waitForAnchor("runs.ready", in: runs)
        runs.buttons["Track Activity"].tap()
        XCTAssertTrue(runs.navigationBars["Activity Actions"].waitForExistence(timeout: 5))
        waitForElement(runs.buttons["runs.action.start_now"])
        XCTAssertTrue(runs.buttons["runs.action.log_past"].exists)
        XCTAssertTrue(runs.buttons["runs.action.import_health"].exists)
        runs.buttons["Cancel"].tap()

        XCTAssertFalse(runs.buttons["Running Assistant"].exists)
        runs.terminate()

        let coach = launchApp(startTab: "ai")
        XCTAssertTrue(coach.navigationBars["Coach"].waitForExistence(timeout: 5))
        let runningPlans = coach.buttons["coach.runningPlans"]
        waitForElement(runningPlans)
        runningPlans.tap()
        XCTAssertTrue(coach.navigationBars["Running Assistant"].waitForExistence(timeout: 5))
        coach.buttons["Close"].tap()
        coach.terminate()

        let weight = launchApp(startTab: "weight")
        waitForAnchor("weight.ready", in: weight)
        weight.buttons["weight.toolbar.actions"].tap()
        XCTAssertTrue(weight.navigationBars["Weight Actions"].waitForExistence(timeout: 5))
        waitForElement(weight.buttons["weight.action.start_now"])
        XCTAssertTrue(weight.buttons["weight.action.import_health"].exists)
        weight.buttons["Cancel"].tap()
        weight.terminate()
    }

    private func launchApp(
        startTab: String,
        fixture: String? = "core_tabs",
        contentSizeCategory: String? = nil,
        recovery: Bool = false
    ) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchEnvironment["UITEST_MODE"] = "1"
        if recovery { app.launchEnvironment["UITEST_RUN_RECOVERY"] = "1" }
        if let fixture {
            app.launchEnvironment["UITEST_FIXTURE"] = fixture
        }
        app.launchEnvironment["UITEST_RESET_STATE"] = "1"
        app.launchEnvironment["UITEST_START_TAB"] = startTab
        if let contentSizeCategory {
            app.launchArguments += [
                "-UIPreferredContentSizeCategoryName",
                contentSizeCategory
            ]
        }
        setupSnapshot(app)
        app.launch()
        XCUIDevice.shared.orientation = .portrait
        return app
    }

    private func openAIAsk(in app: XCUIApplication) {
        XCTAssertTrue(app.navigationBars["Coach"].waitForExistence(timeout: 5))
        let askMode = app.segmentedControls.buttons["Ask"]
        waitForElement(askMode)
        askMode.tap()

        let askAI = app.buttons["Ask AI"]
        waitForElement(askAI)
        askAI.tap()

        XCTAssertTrue(app.navigationBars["AI Assistant"].waitForExistence(timeout: 5))
    }

    private func openRepairedWearableInbox(
        fixture: String,
        expectedPendingCount: Int
    ) -> XCUIApplication {
        let app = launchApp(startTab: "workouts", fixture: fixture)
        waitForAnchor("workouts.ready", in: app)

        let inbox = app.buttons["workouts.wearableInbox"]
        waitForElement(inbox)
        let pendingCount = XCTNSPredicateExpectation(
            predicate: NSPredicate(
                format: "label CONTAINS %@",
                "\(expectedPendingCount) pending"
            ),
            object: inbox
        )
        XCTAssertEqual(
            XCTWaiter().wait(for: [pendingCount], timeout: 5),
            .completed,
            "Expected \(expectedPendingCount) repaired wearable inbox item(s)."
        )

        inbox.tap()
        XCTAssertTrue(app.navigationBars["Workout Inbox"].waitForExistence(timeout: 5))
        waitForElement(wearableInboxItems(in: app).firstMatch)
        return app
    }

    private func wearableInboxItems(in app: XCUIApplication) -> XCUIElementQuery {
        // SwiftUI propagates a container accessibility identifier to several
        // descendants. Count the one title label rendered per inbox row instead.
        app.staticTexts.matching(
            NSPredicate(format: "label == %@", "Strength Training")
        )
    }

    private func waitForAnchor(_ identifier: String, in app: XCUIApplication, timeout: TimeInterval = 10) {
        let anchor = app.descendants(matching: .any).matching(identifier: identifier).firstMatch
        waitForElement(anchor, timeout: timeout)
    }

    private func waitForElement(_ element: XCUIElement, timeout: TimeInterval = 10) {
        XCTAssertTrue(
            element.waitForExistence(timeout: timeout),
            "Expected element to exist: \(element)"
        )
    }

    private func captureAppStoreScreenshot(_ name: String) {
        let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    private func reveal(_ element: XCUIElement, in app: XCUIApplication, attempts: Int = 6) {
        waitForElement(element)
        if waitUntilHittable(element, timeout: 2) {
            return
        }

        for _ in 0..<attempts {
            app.swipeUp()
            if waitUntilHittable(element, timeout: 1) {
                return
            }
        }

        XCTFail("Expected element to become hittable: \(element)")
    }

    private func waitUntilHittable(_ element: XCUIElement, timeout: TimeInterval) -> Bool {
        let hittable = XCTNSPredicateExpectation(
            predicate: NSPredicate(format: "hittable == true"),
            object: element
        )
        return XCTWaiter().wait(for: [hittable], timeout: timeout) == .completed
    }

    private func focusAndType(
        _ text: String,
        into field: XCUIElement,
        in app: XCUIApplication
    ) {
        field.tap()
        if !app.keyboards.firstMatch.waitForExistence(timeout: 2) {
            field.tap()
        }
        XCTAssertTrue(
            app.keyboards.firstMatch.waitForExistence(timeout: 3),
            "Expected the keyboard after focusing: \(field)"
        )
        field.typeText(text)
    }

    private func openSettingsRoot(in app: XCUIApplication) {
        let settingsButton = app.buttons["home.settings.button"]
        waitForElement(settingsButton)
        settingsButton.tap()

        waitForAnchor("settings.ready", in: app)
        XCTAssertTrue(app.navigationBars["Settings"].waitForExistence(timeout: 5))
    }

    private func openSettingsSubpage(
        _ title: String,
        in app: XCUIApplication,
        returnToSettings: Bool = true,
        snapshotName: String? = nil
    ) {
        let button = app.buttons[title]
        for _ in 0..<5 where !button.exists {
            app.swipeUp()
        }
        waitForElement(button)
        button.tap()
        XCTAssertTrue(app.navigationBars[title].waitForExistence(timeout: 5))
        if let snapshotName {
            snapshot(snapshotName, waitForLoadingIndicator: false)
        }
        if returnToSettings {
            app.navigationBars[title].buttons.element(boundBy: 0).tap()
            XCTAssertTrue(app.navigationBars["Settings"].waitForExistence(timeout: 5))
        }
    }
}
