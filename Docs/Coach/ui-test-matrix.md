# Simulator UI test matrix

All 48 defined UI test cases have passing results across the audit runs below. The complete 32-case baseline preceded the audit fixes; later focused runs rechecked changed behavior. This is a cross-run matrix, not a claim that all 48 ran in one final invocation. See [simulator-audit.md](simulator-audit.md) for fixes and limits.

| Test case | Passing Simulator run | Runtime |
| --- | --- | --- |
| `WorkingOutUITests.testAIAskReflowsAtAccessibilityTextSize` | `.tmp/coach-audit-baseline.xcresult` | iPhone / iOS 26.5 |
| `WorkingOutUITests.testAIAskSupportsGuidedAndFreeFormQuestions` | `.tmp/coach-audit-baseline.xcresult` | iPhone / iOS 26.5 |
| `WorkingOutUITests.testActiveRunKeepsItsActivityTypeAcrossEntryPoints` | `.tmp/coach-audit-legacy-final.xcresult` | iPhone / iOS 27 beta |
| `WorkingOutUITests.testAppStoreScreenshotSet` | `.tmp/coach-audit-baseline.xcresult` | iPhone / iOS 26.5 |
| `WorkingOutUITests.testBackupConfirmationsCanBeCanceledWithoutChangingHistory` | `.tmp/coach-audit-legacy-final.xcresult` | iPhone / iOS 27 beta |
| `WorkingOutUITests.testBackupDeduplicateShowsCompletionAndPreservesDistinctWorkouts` | `.tmp/coach-audit-legacy-final.xcresult` | iPhone / iOS 27 beta |
| `WorkingOutUITests.testBackupDeleteRemovesOnlyIsolatedFixtureHistory` | `.tmp/coach-audit-legacy-final.xcresult` | iPhone / iOS 27 beta |
| `WorkingOutUITests.testBackupExportOpensShareSheetAndCancellationDoesNotClaimSuccess` | `.tmp/coach-audit-legacy-final.xcresult` | iPhone / iOS 27 beta |
| `WorkingOutUITests.testBackupImportOpensDocumentPickerAndCanBeCanceled` | `.tmp/coach-audit-legacy-final.xcresult` | iPhone / iOS 27 beta |
| `CoachPhotoUITests.testCancelPhotoPickerLeavesNoAppCopies` | `.tmp/coach-audit-phone-pass4.xcresult` | iPhone / iOS 26.5 |
| `WorkingOutUITests.testCardioInboxLinksOuraMetricsToSuggestedWalkWithoutDuplicate` | `.tmp/coach-audit-baseline.xcresult` | iPhone / iOS 26.5 |
| `WorkingOutUITests.testCoachCalendarExportRetryAndRemoval` | `.tmp/coach-audit-phone-pass4.xcresult` | iPhone / iOS 26.5 |
| `WorkingOutUITests.testCoachCanonicalRunRestoresPausedAndSavesPartial` | `.tmp/coach-audit-phone-pass4.xcresult` | iPhone / iOS 26.5 |
| `WorkingOutUITests.testCoachDailyEntriesRetainUnknownFields` | `.tmp/coach-audit-ios27-smoke.xcresult` | iPhone / iOS 27 beta |
| `WorkingOutUITests.testCoachDraftDuplicateLifecycleSkipAndAttestation` | `.tmp/coach-audit-phone-retest.xcresult` | iPhone / iOS 26.5 |
| `WorkingOutUITests.testCoachImportReviewTrackingAndCheckIn` | `.tmp/coach-audit-ios27-smoke.xcresult` | iPhone / iOS 27 beta |
| `WorkingOutUITests.testCoachInvalidImportPreservesTextAndCanBeCorrected` | `.tmp/coach-audit-ios27-smoke.xcresult` | iPhone / iOS 27 beta |
| `WorkingOutUITests.testCoachPersistenceAndExecutionRegressions` | `.tmp/coach-audit-phone-pass4.xcresult` | iPhone / iOS 26.5 |
| `WorkingOutUITests.testCoachPromptPreviewCanBeCopied` | `.tmp/coach-audit-ios27-smoke.xcresult` | iPhone / iOS 27 beta |
| `WorkingOutUITests.testCoachStrengthRestoresRecordedSetAfterProcessRelaunch` | `.tmp/coach-audit-ios27-smoke.xcresult` | iPhone / iOS 27 beta |
| `WorkingOutUITests.testCoachSurfaceAndHistoryNavigation` | `.tmp/coach-audit-baseline.xcresult` | iPhone / iOS 26.5 |
| `WorkingOutUITests.testCoachUnrecordedStrengthFinishesPartialAndReopens` | `.tmp/coach-audit-phone-pass4.xcresult` | iPhone / iOS 26.5 |
| `CoachEditingUITests.testCoachWeightEditAndDeleteAreSharedWithWeightTab` | `.tmp/coach-audit-ipad-pass4.xcresult` | iPad / iOS 26.5 |
| `WorkingOutUITests.testEmptyStatePrimaryActions` | `.tmp/coach-audit-baseline.xcresult` | iPhone / iOS 26.5 |
| `WorkingOutUITests.testFindHistoryFiltersEachLogAndOpensWeightDetails` | `.tmp/coach-audit-baseline.xcresult` | iPhone / iOS 26.5 |
| `WorkingOutUITests.testHomeQuickActionContextMenusStayScopedToPressedButton` | `.tmp/coach-audit-baseline.xcresult` | iPhone / iOS 26.5 |
| `WorkingOutUITests.testHomeScreenshot` | `.tmp/coach-audit-baseline.xcresult` | iPhone / iOS 26.5 |
| `WorkingOutUITests.testInterruptedRunRestoresPausedAfterRelaunch` | `.tmp/coach-audit-legacy-final.xcresult` | iPhone / iOS 27 beta |
| `CoachEditingUITests.testLargestTypeBuilderCanReviewWhileKeyboardIsOpen` | `.tmp/coach-audit-ipad-pass5.xcresult` | iPad / iOS 26.5 |
| `CoachEditingUITests.testManualProgramDuplicatesPhaseAndSavesDraftWithoutActivity` | `.tmp/coach-audit-ipad-pass5.xcresult` | iPad / iOS 26.5 |
| `CoachEditingUITests.testNutritionReplacesTotalsAndKeepsBlankDistinctFromZero` | `.tmp/coach-audit-ipad-daily-pass5.xcresult` | iPad / iOS 26.5 |
| `WorkingOutUITests.testOptimizationDataPaths` | `.tmp/coach-audit-baseline.xcresult` | iPhone / iOS 26.5 |
| `CoachPhotoUITests.testPhotoImportCompareCorrectAndDeletePreservesLibraryOriginals` | `.tmp/coach-audit-photo-pass10.xcresult` | iPhone / iOS 26.5 |
| `CoachEditingUITests.testRecoveryRejectsInvalidEnergyAndRetainsZeroAndUnknownOnEdit` | `.tmp/coach-audit-ipad-daily-pass7.xcresult` | iPad / iOS 26.5 |
| `WorkingOutUITests.testRetiredWearableReplacementDoesNotResurrectAnOlderUUID` | `.tmp/coach-audit-baseline.xcresult` | iPhone / iOS 26.5 |
| `WorkingOutUITests.testRunsScreenshot` | `.tmp/coach-audit-baseline.xcresult` | iPhone / iOS 26.5 |
| `WorkingOutUITests.testSettingsNavigationOpensFromHomeToolbar` | `.tmp/coach-audit-baseline.xcresult` | iPhone / iOS 26.5 |
| `WorkingOutUITests.testSettingsScreenshot` | `.tmp/coach-audit-baseline.xcresult` | iPhone / iOS 26.5 |
| `CoachEditingUITests.testTargetEditingPreservesUnsavedTotalsAndSavedTargetSnapshot` | `.tmp/coach-audit-ipad-daily-pass7.xcresult` | iPad / iOS 26.5 |
| `WorkingOutUITests.testToolbarActionSheetsAndCoachOwnsRunningPlans` | `.tmp/coach-audit-baseline.xcresult` | iPhone / iOS 26.5 |
| `CoachEditingUITests.testWaistAllowsMultipleObservationsAndEditsOnlySelectedRecord` | `.tmp/coach-audit-ipad-pass4.xcresult` | iPad / iOS 26.5 |
| `WorkingOutUITests.testWearableInboxConsolidatesOuraAndAppleWatchAndKeepsHeartRate` | `.tmp/coach-audit-baseline.xcresult` | iPhone / iOS 26.5 |
| `WorkingOutUITests.testWearableInboxConsolidatesOuraDuplicatesAndKeepsHeartRate` | `.tmp/coach-audit-baseline.xcresult` | iPhone / iOS 26.5 |
| `WorkingOutUITests.testWearableInboxDoesNotTreatCourageAsOura` | `.tmp/coach-audit-baseline.xcresult` | iPhone / iOS 26.5 |
| `WorkingOutUITests.testWearableInboxKeepsSameTimeOuraRowsWithDistinctSyncIdentifiers` | `.tmp/coach-audit-baseline.xcresult` | iPhone / iOS 26.5 |
| `WorkingOutUITests.testWearableReplacementAcrossBatchesPreservesLinkAndUsesCorrectedMetrics` | `.tmp/coach-audit-baseline.xcresult` | iPhone / iOS 26.5 |
| `WorkingOutUITests.testWeightScreenshot` | `.tmp/coach-audit-baseline.xcresult` | iPhone / iOS 26.5 |
| `WorkingOutUITests.testWorkoutsScreenshot` | `.tmp/coach-audit-baseline.xcresult` | iPhone / iOS 26.5 |
