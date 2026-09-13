import Foundation
import SwiftData

extension CoachRepository {
    func nutritionLogs(from start: Date? = nil, through end: Date? = nil) throws -> [CoachNutritionLog] {
        let lower = start.map { Self.civilDate($0) }, upper = end.map { Self.civilDate($0) }
        return try context.fetch(FetchDescriptor<CoachNutritionLog>(sortBy: [SortDescriptor(\.civilDate, order: .reverse)]))
            .filter { (lower == nil || $0.civilDate >= lower!) && (upper == nil || $0.civilDate <= upper!) }
    }

    func recoveryLogs(from start: Date? = nil, through end: Date? = nil) throws -> [CoachRecoveryCheckIn] {
        let lower = start.map { Self.civilDate($0) }, upper = end.map { Self.civilDate($0) }
        return try context.fetch(FetchDescriptor<CoachRecoveryCheckIn>(sortBy: [SortDescriptor(\.civilDate, order: .reverse)]))
            .filter { (lower == nil || $0.civilDate >= lower!) && (upper == nil || $0.civilDate <= upper!) }
    }

    func nutritionTarget(on date: Date) throws -> CoachNutritionTargetPeriod? {
        let key = Self.civilDate(date)
        return try context.fetch(FetchDescriptor<CoachNutritionTargetPeriod>())
            .filter { $0.startCivilDate <= key && ($0.endCivilDate == nil || $0.endCivilDate! > key) }
            .max { $0.createdAt < $1.createdAt }
    }

    @discardableResult
    func saveNutrition(date: Date, calories: Double?, protein: Double?, carbs: Double?, fat: Double?,
                       notes: String? = nil, isFinal: Bool = false, id: UUID? = nil) throws -> UUID {
        for (name, value) in [("calories", calories), ("protein", protein), ("carbohydrate", carbs), ("fat", fat)] { try Self.validate(value, field: name) }
        let target = try nutritionTarget(on: date)
        let targetData = try target.map { try JSONEncoder().encode(CoachNutritionTargets(caloriesKcal: $0.calories.map { Int($0.rounded()) }, proteinGrams: $0.protein, carbohydrateGrams: $0.carbs, fatGrams: $0.fat, notes: $0.notes)) }
        return try transaction { isolated in
            let key = Self.civilDate(date)
            let records = try isolated.fetch(FetchDescriptor<CoachNutritionLog>())
            if let id {
                guard let selected = records.first(where: { $0.id == id }) else { throw CoachRepositoryError.missingRecord }
                guard selected.civilDate == key else { throw CoachRepositoryError.dateCollision }
            }
            let sameDay = records.filter { $0.civilDate == key }
            if id == nil && sameDay.count > 1 { throw CoachRepositoryError.dateCollision }
            let record = id.flatMap { selected in records.first { $0.id == selected } } ?? sameDay.first ?? CoachNutritionLog()
            if record.modelContext == nil { isolated.insert(record); record.civilDate = key; record.timeZoneIdentifier = TimeZone.current.identifier; record.targetSnapshotData = targetData }
            record.calories = calories; record.protein = protein; record.carbs = carbs; record.fat = fat
            record.notes = notes; record.statusRaw = isFinal ? "final" : "draft"; record.updatedAt = Date()
            return record.id
        }
    }

    @discardableResult
    func saveRecovery(date: Date, manualSleepHours: Double?, soreness: Int?, energy: Int?, painScore: Int?,
                      painLocation: String? = nil, notes: String? = nil, id: UUID? = nil) throws -> UUID {
        try Self.validate(manualSleepHours, field: "sleep duration", upper: 48)
        if let soreness, !(0...10).contains(soreness) { throw CoachRepositoryError.invalidValue("soreness from 0 to 10") }
        if let energy, !(1...5).contains(energy) { throw CoachRepositoryError.invalidValue("energy from 1 to 5") }
        if let painScore, !(0...10).contains(painScore) { throw CoachRepositoryError.invalidValue("pain from 0 to 10") }
        return try transaction { isolated in
            let key = Self.civilDate(date)
            let records = try isolated.fetch(FetchDescriptor<CoachRecoveryCheckIn>())
            if let id {
                guard let selected = records.first(where: { $0.id == id }) else { throw CoachRepositoryError.missingRecord }
                guard selected.civilDate == key else { throw CoachRepositoryError.dateCollision }
            }
            let sameDay = records.filter { $0.civilDate == key }
            if id == nil && sameDay.count > 1 { throw CoachRepositoryError.dateCollision }
            let record = id.flatMap { selected in records.first { $0.id == selected } } ?? sameDay.first ?? CoachRecoveryCheckIn()
            if record.modelContext == nil { isolated.insert(record); record.civilDate = key; record.timeZoneIdentifier = TimeZone.current.identifier }
            record.manualSleepHours = manualSleepHours; record.soreness = soreness; record.energy = energy
            record.painScore = painScore; record.painLocation = painLocation; record.notes = notes; record.updatedAt = Date()
            record.sleepSourceRaw = manualSleepHours != nil ? "manual" : (record.healthSleepHours == nil ? "unavailable" : "health")
            return record.id
        }
    }

    /// A Health refresh replaces its selected-source snapshot. It does not add
    /// sleep to a manual duration, clear manual entries, or infer permission.
    func saveHealthSleep(date: Date, hours: Double?, source: String?, endDate: Date?, coverageData: Data?) throws {
        try Self.validate(hours, field: "Health sleep duration", upper: 48)
        try transaction { isolated in
            let key = Self.civilDate(date)
            let rows = try isolated.fetch(FetchDescriptor<CoachRecoveryCheckIn>()).filter { $0.civilDate == key }
            guard rows.count <= 1 else { throw CoachRepositoryError.dateCollision }
            let row = rows.first ?? CoachRecoveryCheckIn()
            if row.modelContext == nil { isolated.insert(row); row.civilDate = key; row.timeZoneIdentifier = TimeZone.current.identifier }
            row.healthSleepHours = hours; row.healthSleepSource = source; row.healthSleepEndDate = endDate; row.healthSampleCoverageData = coverageData
            row.sleepSourceRaw = row.manualSleepHours != nil ? "manual" : (hours == nil ? "unavailable" : "health"); row.updatedAt = Date()
        }
    }

    func waistMeasurements() throws -> [CoachWaistMeasurement] {
        try context.fetch(FetchDescriptor<CoachWaistMeasurement>(sortBy: [SortDescriptor(\.observedAt, order: .reverse)]))
    }

    @discardableResult
    func saveWaist(date: Date, value: Double, unit: String, notes: String? = nil, id: UUID? = nil) throws -> UUID {
        guard value.isFinite && value > 0, ["cm", "in"].contains(unit) else { throw CoachRepositoryError.invalidValue("waist measurement and unit") }
        return try transaction { isolated in
            let rows = try isolated.fetch(FetchDescriptor<CoachWaistMeasurement>())
            if let id, !rows.contains(where: { $0.id == id }) { throw CoachRepositoryError.missingRecord }
            let record = id.flatMap { selected in rows.first { $0.id == selected } } ?? CoachWaistMeasurement()
            if record.modelContext == nil { isolated.insert(record) }
            record.observedAt = date; record.civilDate = Self.civilDate(date); record.timeZoneIdentifier = TimeZone.current.identifier
            record.value = value; record.unit = unit; record.notes = notes
            return record.id
        }
    }

    /// Weight and Coach both use the original WeightEntry identity source.
    @discardableResult
    func saveWeight(date: Date, value: Double, unit: String, id: UUID? = nil) throws -> UUID {
        guard value.isFinite && value > 0, ["kg", "lb", "lbs"].contains(unit) else { throw CoachRepositoryError.invalidValue("weight and unit") }
        return try transaction { isolated in
            let records = try isolated.fetch(FetchDescriptor<WeightEntry>())
            if let id, !records.contains(where: { $0.id == id }) { throw CoachRepositoryError.missingRecord }
            let record = id.flatMap { selected in records.first { $0.id == selected } } ?? WeightEntry(date: date, weight: value, weightUnit: unit == "lb" ? "lbs" : unit)
            if record.modelContext == nil { isolated.insert(record) }
            record.date = date; record.weight = value; record.weightUnit = unit == "lb" ? "lbs" : unit
            record.provenance = record.sourceHealthSampleID == nil ? "manual" : "manual_override"
            return record.id
        }
    }

    func weights() throws -> [WeightEntry] { try context.fetch(FetchDescriptor<WeightEntry>(sortBy: [SortDescriptor(\.date, order: .reverse)])) }

    func deleteNutrition(id: UUID) throws { try transaction { context in if let row = try context.fetch(FetchDescriptor<CoachNutritionLog>()).first(where: { $0.id == id }) { context.delete(row) } } }
    func deleteRecovery(id: UUID) throws { try transaction { context in if let row = try context.fetch(FetchDescriptor<CoachRecoveryCheckIn>()).first(where: { $0.id == id }) { context.delete(row) } } }
    func deleteWaist(id: UUID) throws { try transaction { context in if let row = try context.fetch(FetchDescriptor<CoachWaistMeasurement>()).first(where: { $0.id == id }) { context.delete(row) } } }

    private static func validate(_ value: Double?, field: String, upper: Double = 1_000_000) throws {
        if let value, !value.isFinite || value < 0 || value > upper { throw CoachRepositoryError.invalidValue(field) }
    }
}

extension CoachRepository {
    /// New targets take effect on a reviewed civil date; earlier periods and
    /// target snapshots already attached to logged days remain unchanged.
    @discardableResult
    func saveNutritionTarget(date: Date, calories: Double?, protein: Double?, carbs: Double?, fat: Double?, notes: String? = nil) throws -> UUID {
        for (name, value) in [("calories", calories), ("protein", protein), ("carbohydrate", carbs), ("fat", fat)] { try Self.validate(value, field: name) }
        if let calories, calories.rounded() != calories { throw CoachRepositoryError.invalidValue("whole-number target calories") }
        let key = Self.civilDate(date)
        guard key >= Self.civilDate(Date()) else { throw CoachRepositoryError.invalidValue("target effective date today or later") }
        return try transaction { isolated in
            let periods = try isolated.fetch(FetchDescriptor<CoachNutritionTargetPeriod>())
            for period in periods where period.endCivilDate == nil || period.endCivilDate! > key {
                if period.startCivilDate < key { period.endCivilDate = key } else { isolated.delete(period) }
            }
            let row = CoachNutritionTargetPeriod(); row.startCivilDate = key; row.timeZoneIdentifier = TimeZone.current.identifier
            row.calories = calories; row.protein = protein; row.carbs = carbs; row.fat = fat; row.notes = notes
            isolated.insert(row); return row.id
        }
    }
}

extension CoachRepository {
    @discardableResult
    func saveNutritionTarget(effectiveDate: Date, calories: Double?, protein: Double?, carbs: Double?, fat: Double?, notes: String? = nil) throws -> UUID {
        try saveNutritionTarget(date: effectiveDate, calories: calories, protein: protein, carbs: carbs, fat: fat, notes: notes)
    }
}
