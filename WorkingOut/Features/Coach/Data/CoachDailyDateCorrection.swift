import Foundation
import SwiftData

struct CoachNutritionMovePreview {
    let source: CoachNutritionLog
    let destination: CoachNutritionLog?
    let target: CoachNutritionTargetPeriod?
}
struct CoachRecoveryMovePreview {
    let source: CoachRecoveryCheckIn
    let destination: CoachRecoveryCheckIn?
}

extension CoachRepository {
    func nutritionMovePreview(id: UUID, to date: Date) throws -> CoachNutritionMovePreview {
        let rows = try nutritionLogs()
        guard let source = rows.first(where: { $0.id == id }) else { throw CoachRepositoryError.missingRecord }
        let destinations = rows.filter { $0.civilDate == Self.civilDate(date) && $0.id != id }
        guard destinations.count <= 1 else { throw CoachRepositoryError.dateCollision }
        return .init(source: source, destination: destinations.first, target: try nutritionTarget(on: date))
    }

    func recoveryMovePreview(id: UUID, to date: Date) throws -> CoachRecoveryMovePreview {
        let rows = try recoveryLogs()
        guard let source = rows.first(where: { $0.id == id }) else { throw CoachRepositoryError.missingRecord }
        let destinations = rows.filter { $0.civilDate == Self.civilDate(date) && $0.id != id }
        guard destinations.count <= 1 else { throw CoachRepositoryError.dateCollision }
        return .init(source: source, destination: destinations.first)
    }

    /// Merged values are supplied by the review screen, never added. The exact
    /// destination observed during review must still exist and be unchanged.
    @discardableResult
    func moveNutrition(id: UUID, to date: Date, mergedCalories: Double?, mergedProtein: Double?, mergedCarbs: Double?, mergedFat: Double?, mergedNotes: String?, isFinal: Bool,
                       expectedDestinationID: UUID? = nil, expectedSourceUpdatedAt: Date? = nil, expectedDestinationUpdatedAt: Date? = nil) throws -> UUID {
        for (field, value) in [("calories", mergedCalories), ("protein", mergedProtein), ("carbohydrate", mergedCarbs), ("fat", mergedFat)] {
            if let value, !value.isFinite || value < 0 || value > 1_000_000 { throw CoachRepositoryError.invalidValue(field) }
        }
        let target = try nutritionTarget(on: date)
        let snapshot = try target.map { try JSONEncoder().encode(CoachNutritionTargets(caloriesKcal: $0.calories.map { Int($0.rounded()) }, proteinGrams: $0.protein, carbohydrateGrams: $0.carbs, fatGrams: $0.fat, notes: $0.notes)) }
        return try transaction { isolated in
            let rows = try isolated.fetch(FetchDescriptor<CoachNutritionLog>())
            guard let source = rows.first(where: { $0.id == id }) else { throw CoachRepositoryError.missingRecord }
            if let expectedSourceUpdatedAt, source.updatedAt != expectedSourceUpdatedAt { throw CoachRepositoryError.dateCollision }
            let key = Self.civilDate(date), matches = rows.filter { $0.civilDate == Self.civilDate(date) && $0.id != id }
            guard matches.count <= 1, matches.first?.id == expectedDestinationID else { throw CoachRepositoryError.dateCollision }
            if let expectedDestinationUpdatedAt, matches.first?.updatedAt != expectedDestinationUpdatedAt { throw CoachRepositoryError.dateCollision }
            let destination = matches.first ?? source
            destination.calories = mergedCalories; destination.protein = mergedProtein; destination.carbs = mergedCarbs; destination.fat = mergedFat
            destination.notes = mergedNotes; destination.statusRaw = isFinal ? "final" : "draft"; destination.updatedAt = Date()
            if destination.id == source.id {
                destination.civilDate = key; destination.timeZoneIdentifier = TimeZone.current.identifier; destination.targetSnapshotData = snapshot
            } else { isolated.delete(source) }
            return destination.id
        }
    }

    @discardableResult
    func moveRecovery(id: UUID, to date: Date, manualSleepHours: Double?, soreness: Int?, energy: Int?, painScore: Int?, painLocation: String?, notes: String?,
                      expectedDestinationID: UUID? = nil, expectedSourceUpdatedAt: Date? = nil, expectedDestinationUpdatedAt: Date? = nil) throws -> UUID {
        if let manualSleepHours, !manualSleepHours.isFinite || !(0...48).contains(manualSleepHours) { throw CoachRepositoryError.invalidValue("sleep duration") }
        if let soreness, !(0...10).contains(soreness) { throw CoachRepositoryError.invalidValue("soreness") }
        if let energy, !(1...5).contains(energy) { throw CoachRepositoryError.invalidValue("energy") }
        if let painScore, !(0...10).contains(painScore) { throw CoachRepositoryError.invalidValue("pain") }
        return try transaction { isolated in
            let rows = try isolated.fetch(FetchDescriptor<CoachRecoveryCheckIn>())
            guard let source = rows.first(where: { $0.id == id }) else { throw CoachRepositoryError.missingRecord }
            if let expectedSourceUpdatedAt, source.updatedAt != expectedSourceUpdatedAt { throw CoachRepositoryError.dateCollision }
            let key = Self.civilDate(date), matches = rows.filter { $0.civilDate == Self.civilDate(date) && $0.id != id }
            guard matches.count <= 1, matches.first?.id == expectedDestinationID else { throw CoachRepositoryError.dateCollision }
            if let expectedDestinationUpdatedAt, matches.first?.updatedAt != expectedDestinationUpdatedAt { throw CoachRepositoryError.dateCollision }
            let retainsSourceSleep = source.civilDate != key && (source.healthSleepHours != nil || source.healthSleepSource != nil || source.healthSleepEndDate != nil || source.healthSampleCoverageData != nil)
            let destination: CoachRecoveryCheckIn
            if let existing = matches.first { destination = existing }
            else if retainsSourceSleep {
                destination = CoachRecoveryCheckIn(); destination.civilDate = key
                destination.timeZoneIdentifier = TimeZone.current.identifier; destination.createdAt = source.createdAt
                isolated.insert(destination)
            } else { destination = source }
            destination.manualSleepHours = manualSleepHours; destination.soreness = soreness; destination.energy = energy
            destination.painScore = painScore; destination.painLocation = painLocation; destination.notes = notes; destination.updatedAt = Date()
            if destination.id == source.id { destination.civilDate = key; destination.timeZoneIdentifier = TimeZone.current.identifier }
            else if retainsSourceSleep {
                // Health coverage remains on its measured day. Only the reviewed
                // manual check-in fields move to the selected destination.
                source.manualSleepHours = nil; source.soreness = nil; source.energy = nil
                source.painScore = nil; source.painLocation = nil; source.notes = nil
                source.sleepSourceRaw = source.healthSleepHours == nil ? "unavailable" : "health"; source.updatedAt = Date()
            } else { isolated.delete(source) }
            destination.sleepSourceRaw = manualSleepHours != nil ? "manual" : (destination.healthSleepHours != nil ? "health" : "unavailable")
            return destination.id
        }
    }
}
