#if DEBUG
import Foundation
import SwiftData
import UIKit

@MainActor
enum CoachSavedBackupRegressionChecks {
    /// Exercise the public export/import pipeline with synthetic models and a
    /// generated image. The saved copy is separate from the transient export;
    /// this does not stand in for the system Files picker or physical storage.
    static func run() async throws -> Int {
        precondition(AppLaunchConfiguration.current.isUITest)
        let files = FileManager.default
        let root = files.temporaryDirectory.appendingPathComponent("CoachSavedBackupChecks-\(UUID())", isDirectory: true)
        try CoachLocalOwnership.prepareDirectory(root)
        defer { try? files.removeItem(at: root) }
        func store(_ name: String) throws -> ModelContainer {
            let schema = PersistenceController.coachSchema
            return try ModelContainer(for: schema, configurations: [ModelConfiguration(CoachPersistence.configurationName,
                schema: schema, url: root.appendingPathComponent(name), cloudKitDatabase: .none)])
        }
        var count = 0
        func require(_ value: Bool, _ message: String) throws {
            count += 1
            if !value { throw CoachRepositoryError.invalidValue("saved backup regression: " + message) }
        }
        let source = try store("source.store")
        let context = source.mainContext
        let repository = CoachRepository(context: context)
        let date = Date()
        let exercise = CoachStrengthExercise(id: "press", exercise: .init(key: "press", name: "Synthetic Backup Press", equipment: ["dumbbell"]),
            prescriptionBasis: .perSide, loadBasis: .perImplement,
            sets: [.init(id: "work", role: .working, target: .reps(min: 6, max: 10))])
        let document = CoachPlanDocument(programId: "saved_backup_\(UUID())", title: "Synthetic saved backup", goal: "General fitness",
            nutritionTargets: .init(caloriesKcal: 2100, proteinGrams: 120),
            phases: [.init(id: "phase", title: "Phase", advanceMode: .scheduled)],
            sessionTemplates: [.strength(.init(id: "lift", title: "Synthetic lift", exercises: [exercise]))],
            weekPatterns: [.init(id: "pattern", title: "Week", slots: [.init(id: "slot", dayOffset: 0, sessionTemplateId: "lift")])],
            weeks: [.init(id: "week", phaseId: "phase", weekPatternId: "pattern")])
        let planID = try await repository.importPlan(document: document, startDate: date, activate: true, allowCreatingExercises: true)
        guard let occurrence = try repository.occurrences(planID: planID).first else {
            throw CoachRepositoryError.invalidValue("synthetic saved-backup occurrence")
        }
        let execution = try CoachExecutionCoordinator.startStrength(occurrence, context: context)
        var actual = CoachExecutionSnapshot()
        actual.setResults = [.init(id: "press/work", exerciseID: "press", setID: "work", performedExerciseID: "press", performedExerciseName: "Synthetic Backup Press",
            equipment: "dumbbell", reps: 8, load: 12.5, loadUnit: "kg", loadBasis: "perImplement", repCounting: "perSide", effortScale: "rir", effort: 2, state: .completed)]
        try CoachExecutionCoordinator.finish(execution, snapshot: actual, status: .completed, explanation: nil, context: context)
        let nutritionID = try repository.saveNutrition(date: date, calories: 0, protein: nil, carbs: 50, fat: nil, isFinal: true)
        let recoveryID = try repository.saveRecovery(date: date, manualSleepHours: 7.5, soreness: 0, energy: nil, painScore: 0)
        let weightID = try repository.saveWeight(date: date, value: 80, unit: "kg")
        let waistID = try repository.saveWaist(date: date, value: 90, unit: "cm")
        let renderer = UIGraphicsImageRenderer(size: CGSize(width: 16, height: 16))
        let image = renderer.image { rendererContext in
            UIColor.systemTeal.setFill()
            rendererContext.fill(CGRect(x: 0, y: 0, width: 16, height: 16))
        }
        guard let jpeg = image.jpegData(compressionQuality: 0.9) else {
            throw CoachRepositoryError.invalidValue("synthetic saved-backup JPEG")
        }
        let photoID = try await repository.importPhoto(data: jpeg, observedAt: date, pose: "synthetic")
        let photoKey = "\(photoID.uuidString).jpg"
        let photoURL = try CoachPhotoStore.assetURL(for: photoKey)
        let thumbnailURL = CoachPhotoStore.directory.appendingPathComponent("\(photoID.uuidString).thumbnail.jpg")
        defer {
            try? files.removeItem(at: photoURL)
            try? files.removeItem(at: thumbnailURL)
            try? files.removeItem(at: CoachPhotoStore.journalURL(photoID))
        }
        let photoBytes = try Data(contentsOf: photoURL)
        let expectedDigest = try CoachLocalOwnership.snapshotDigest(context)
        let expectedGraph = try DataBackupService.capture(context: context).coach
        try require(expectedGraph?.revisions.count == 1 && expectedGraph?.executions.count == 1 && expectedGraph?.targets.count == 1,
                    "fixture includes revision, execution and target identities")

        let transientExport = try await DataBackupService.exportAll(context: context, includePhotos: true)
        defer { try? files.removeItem(at: transientExport) }
        let savedDirectory = root.appendingPathComponent("SavedOutsideExport", isDirectory: true)
        try files.createDirectory(at: savedDirectory, withIntermediateDirectories: true)
        let savedURL = savedDirectory.appendingPathComponent("deliberate-recovery.pacebackup")
        try files.copyItem(at: transientExport, to: savedURL)
        let savedBytes = try Data(contentsOf: savedURL)
        try require(savedBytes == Data(contentsOf: transientExport), "saved copy has the exact exported archive bytes")
        try files.removeItem(at: transientExport)
        try require(!files.fileExists(atPath: transientExport.path) && files.fileExists(atPath: savedURL.path),
                    "saved archive remains after the transient export is gone")
        // Remove only the image this fixture just created: restore must recover
        // image bytes from the saved archive, not reuse the source asset.
        try files.removeItem(at: photoURL)
        try? files.removeItem(at: thumbnailURL)
        try require(!files.fileExists(atPath: photoURL.path), "source image is absent before fresh-store restore")

        let restored = try store("restored.store")
        try require(try restored.mainContext.fetchCount(FetchDescriptor<TrainingPlan>()) == 0,
                    "restore starts with an empty on-disk Coach store")
        try await DataBackupService.import(from: savedURL, context: restored.mainContext)
        try require(try CoachLocalOwnership.snapshotDigest(restored.mainContext) == expectedDigest,
                    "public restore preserves the complete model graph exactly")
        try require(try Data(contentsOf: photoURL) == photoBytes, "public restore recovers the exact synthetic image bytes")
        let restoredGraph = try DataBackupService.capture(context: restored.mainContext).coach
        try require(restoredGraph?.plannedSessions.first?.id == occurrence.id && restoredGraph?.executions.first?.id == execution.id,
                    "canonical occurrence and execution identities survive")
        try require(restoredGraph?.targets == expectedGraph?.targets && restoredGraph?.photos == expectedGraph?.photos,
                    "target and photo snapshots retain their identities and values")
        try require(restoredGraph?.nutrition.first?.id == nutritionID && restoredGraph?.recovery.first?.id == recoveryID
                    && restoredGraph?.waist.first?.id == waistID
                    && (try restored.mainContext.fetch(FetchDescriptor<WeightEntry>()).first?.id) == weightID,
                    "daily, weight and waist identities survive")
        let restoredExecution = try restored.mainContext.fetch(FetchDescriptor<CoachSessionExecution>()).first!
        try require(try CoachExecutionCoordinator.snapshot(restoredExecution).setResults == actual.setResults,
                    "entered actuals survive the saved-file pipeline")

        let reopened = try store("restored.store")
        try require(try CoachLocalOwnership.snapshotDigest(reopened.mainContext) == expectedDigest,
                    "restored graph survives a disk reopen")
        try await DataBackupService.import(from: savedURL, context: reopened.mainContext)
        try require(try CoachLocalOwnership.snapshotDigest(reopened.mainContext) == expectedDigest,
                    "reimport after reopen creates no duplicate or altered history")
        var corruptedBytes = savedBytes
        corruptedBytes[corruptedBytes.count - 1] ^= 1
        let corruptURL = savedDirectory.appendingPathComponent("damaged.pacebackup")
        try corruptedBytes.write(to: corruptURL)
        do {
            try await DataBackupService.import(from: corruptURL, context: reopened.mainContext)
            throw CoachRepositoryError.invalidValue("corrupted saved backup was accepted")
        } catch is CoachHistoryArchive.ArchiveError { count += 1 }
        try require(try CoachLocalOwnership.snapshotDigest(reopened.mainContext) == expectedDigest,
                    "rejected corruption leaves all stored history unchanged")
        try require(try Data(contentsOf: photoURL) == photoBytes, "rejected corruption preserves the restored image")
        try require(try Data(contentsOf: savedURL) == savedBytes, "repeated and rejected imports never change the saved original")
        return count
    }
}
#endif
