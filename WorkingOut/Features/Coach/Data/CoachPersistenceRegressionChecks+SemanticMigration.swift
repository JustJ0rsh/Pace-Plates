#if DEBUG
import Foundation
import SwiftData
import SQLite3

extension CoachPersistenceRegressionChecks {
    @MainActor static func runSemanticMigrationCases(root: URL) throws -> Int {
        let directory = root.appendingPathComponent("semantic-migration", isDirectory: true)
        try CoachLocalOwnership.prepareDirectory(directory)
        let sourceURL = directory.appendingPathComponent("source.store")
        let copyURL = directory.appendingPathComponent("copy.store")
        let legacySchema = Schema(PersistenceController.legacyModelTypes)
        let source = try ModelContainer(for: legacySchema, configurations: [ModelConfiguration("LegacyFixture", schema: legacySchema, url: sourceURL, cloudKitDatabase: .none)])
        source.mainContext.autosaveEnabled = false
        let first = ExerciseDefinition(name: "Synthetic A", muscleGroup: "Chest", isUserDefined: true)
        let second = ExerciseDefinition(name: "Synthetic B", muscleGroup: "Chest", isUserDefined: true)
        let workout = WorkoutSession(date: Date(timeIntervalSince1970: 50), notes: "Keep this note", title: "Semantic preservation")
        let log = ExerciseLog(reps: 3, weight: 20, weightUnit: "kg", setNumber: 1, exerciseName: first.name, isCompleted: false)
        log.exerciseDefinition = first; log.workoutSession = workout
        source.mainContext.insert(first); source.mainContext.insert(second); source.mainContext.insert(workout); source.mainContext.insert(log)
        try source.mainContext.save()
        let original = try CoachLocalOwnership.rawCheckpoint(sourceURL)
        try CoachLocalOwnership.copyStore(from: sourceURL, to: copyURL)
        try CoachLocalOwnership.copyAuxiliaryFiles(from: sourceURL, to: copyURL)
        let full = PersistenceController.coachSchema
        let copy = try ModelContainer(for: full, configurations: [ModelConfiguration(CoachPersistence.configurationName, schema: full, url: copyURL, cloudKitDatabase: .none)])
        copy.mainContext.autosaveEnabled = false
        var checks = 0
        func require(_ condition: Bool, _ reason: String) throws {
            checks += 1
            guard condition else { throw CoachRepositoryError.invalidValue("semantic migration regression: " + reason) }
        }
        func verify() throws {
            try CoachLocalOwnership.verifyRetainedColumns(original, at: copyURL, allowedNewTables: PersistenceController.addedLocalSchemaTables)
        }
        func reject(_ reason: String) throws {
            var rejected = false
            do { try verify() } catch { rejected = true }
            try require(rejected, reason)
        }
        func mutate(_ sql: String) throws {
            var database: OpaquePointer?
            guard sqlite3_open_v2(CoachLocalOwnership.canonicalSQLiteURL(copyURL).path, &database, SQLITE_OPEN_READWRITE, nil) == SQLITE_OK,
                  let database else {
                if let database { sqlite3_close(database) }
                throw CoachRepositoryError.invalidValue("synthetic copy mutation could not open")
            }
            defer { sqlite3_close(database) }
            sqlite3_busy_timeout(database, 5_000)
            guard sqlite3_exec(database, sql, nil, nil, nil) == SQLITE_OK else {
                throw CoachRepositoryError.invalidValue("synthetic copy mutation failed: " + String(cString: sqlite3_errmsg(database)))
            }
        }
        func scalar(_ sql: String) throws -> Int64 {
            var database: OpaquePointer?
            guard sqlite3_open_v2(CoachLocalOwnership.canonicalSQLiteURL(copyURL).path, &database, SQLITE_OPEN_READONLY, nil) == SQLITE_OK,
                  let database else {
                if let database { sqlite3_close(database) }
                throw CoachRepositoryError.invalidValue("synthetic copy query could not open")
            }
            defer { sqlite3_close(database) }
            var query: OpaquePointer?
            let prepared = sqlite3_prepare_v2(database, sql, -1, &query, nil)
            guard prepared == SQLITE_OK, let query else {
                if let query { sqlite3_finalize(query) }
                throw CoachRepositoryError.invalidValue("synthetic copy query could not prepare")
            }
            defer { sqlite3_finalize(query) }
            guard sqlite3_step(query) == SQLITE_ROW else { throw CoachRepositoryError.invalidValue("synthetic copy query returned no result") }
            return sqlite3_column_int64(query, 0)
        }
        try verify()
        try require(true, "full-schema bookkeeping and stable entity meaning preserve app records")
        try require(try CoachLocalOwnership.rawCheckpoint(copyURL).digest != original.digest,
                    "literal raw checksum still observes schema and metadata changes")

        // Mutations below target only this disposable copy, never the source.
        // A new numeric entity ID with the same stable name is equivalent.
        try require(try scalar("SELECT count(*) FROM Z_PRIMARYKEY WHERE Z_NAME IN ('ExerciseDefinition','WorkoutSession')") == 2,
                    "entity-meaning fixture uses two distinct valid mapped classes")
        try mutate("UPDATE Z_PRIMARYKEY SET Z_ENT=100001 WHERE Z_NAME='ExerciseDefinition'; UPDATE ZEXERCISEDEFINITION SET Z_ENT=100001")
        try require(try scalar("SELECT count(*) FROM Z_PRIMARYKEY WHERE Z_ENT=100001 AND Z_NAME='ExerciseDefinition'") == 1,
                    "stable-name renumbering actually changes the entity map")
        try verify()
        try require(true, "numeric entity renumbering with identical stable names is accepted")
        try mutate("UPDATE ZEXERCISEDEFINITION SET Z_ENT=(SELECT Z_ENT FROM Z_PRIMARYKEY WHERE Z_NAME='WorkoutSession')")
        try reject("changing a row's stable entity meaning is rejected")
        try mutate("UPDATE ZEXERCISEDEFINITION SET Z_ENT=100001")
        try mutate("UPDATE ZEXERCISEDEFINITION SET ZNAME='Tampered' WHERE ZNAME='Synthetic A'")
        try reject("changing an app field is rejected")
        try mutate("UPDATE ZEXERCISEDEFINITION SET ZNAME='Synthetic A' WHERE ZNAME='Tampered'")
        try mutate("UPDATE ZEXERCISELOG SET ZEXERCISEDEFINITION=(SELECT Z_PK FROM ZEXERCISEDEFINITION WHERE ZNAME='Synthetic B')")
        try reject("changing a relationship foreign key is rejected")
        try mutate("UPDATE ZEXERCISELOG SET ZEXERCISEDEFINITION=(SELECT Z_PK FROM ZEXERCISEDEFINITION WHERE ZNAME='Synthetic A')")
        try mutate("CREATE TABLE ZZUNEXPECTED (VALUE INTEGER); INSERT INTO ZZUNEXPECTED VALUES (1)")
        try reject("an unknown destination table is rejected")
        try mutate("DROP TABLE ZZUNEXPECTED")
        try mutate("UPDATE Z_PRIMARYKEY SET Z_NAME='WrongEntityMeaning' WHERE Z_ENT=100001")
        try reject("changing the entity-name map is rejected")
        try mutate("UPDATE Z_PRIMARYKEY SET Z_NAME='ExerciseDefinition' WHERE Z_ENT=100001")
        try verify()
        try require(true, "restoring the exact application state restores verification")
        try mutate("ALTER TABLE ZEXERCISEDEFINITION ADD COLUMN ZUNRECOGNIZED TEXT")
        try reject("an unknown destination column is rejected")
        try require(try CoachLocalOwnership.rawCheckpoint(sourceURL).identity == original.identity,
                    "all semantic tampering leaves the original store unchanged")
        withExtendedLifetime(copy) { }
        return checks
    }
}
#endif
