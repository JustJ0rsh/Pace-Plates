import Foundation
import SwiftData

enum CoachPlanStatus: String, Codable, CaseIterable { case draft, active, paused, finished, archived }
enum CoachOccurrenceStatus: String, Codable, CaseIterable { case pending, inProgress = "in_progress", completed, partial, skipped }
enum CoachExecutionStatus: String, Codable, CaseIterable { case inProgress = "in_progress", completed, partial, canceled, legacyRecorded = "legacy_recorded" }

/// Personal Coach record. Register only in the protected local container.
@Model
final class CoachPlanRevision {
    var id: UUID = UUID()
    var planID: UUID = UUID()
    @Attribute(.externalStorage) var documentData: Data = Data()
    var fingerprint: String = ""
    var sourceProgramID: String = ""
    var sourceRevision: Int = 1
    var schemaVersion: Int = 1
    var provenance: String = "import"
    var exerciseMappingsData: Data? = nil
    var createdAt: Date = Date()

    init(id: UUID = UUID()) { self.id = id }
}

/// Personal Coach record. Register only in the protected local container.
@Model
final class CoachSessionExecution {
    var id: UUID = UUID()
    var plannedSessionID: UUID? = nil
    var workoutSessionID: UUID? = nil
    var runSessionID: UUID? = nil
    var startedAt: Date = Date()
    var endedAt: Date? = nil
    var statusRaw: String = "in_progress"
    var prescriptionRevisionID: UUID? = nil
    @Attribute(.externalStorage) var prescriptionData: Data? = nil
    @Attribute(.externalStorage) var snapshotData: Data? = nil
    var provenance: String = "recorded"
    var effortScale: String? = nil
    var effort: Double? = nil
    var notes: String? = nil
    var updatedAt: Date = Date()

    init(id: UUID = UUID()) { self.id = id }
}

/// Personal Coach record. Register only in the protected local container.
@Model
final class CoachProgressionSuggestion {
    var id: UUID = UUID()
    var planID: UUID = UUID()
    var ruleID: String = ""
    var exerciseID: String? = nil
    var sourceTemplateID: String = ""
    var evidenceIDsData: Data = Data()
    var evidenceFingerprint: String = ""
    @Attribute(.externalStorage) var proposedPrescriptionData: Data = Data()
    var reason: String = ""
    var statusRaw: String = "pending"
    var selectedOccurrenceIDsData: Data? = nil
    var createdAt: Date = Date()
    var decidedAt: Date? = nil

    init(id: UUID = UUID()) { self.id = id }
}

/// Personal Coach record. Register only in the protected local container.
@Model
final class CoachNutritionTargetPeriod {
    var id: UUID = UUID()
    var planID: UUID? = nil
    var phaseID: String? = nil
    var startCivilDate: String = ""
    var endCivilDate: String? = nil
    var timeZoneIdentifier: String = ""
    var calories: Double? = nil
    var protein: Double? = nil
    var carbs: Double? = nil
    var fat: Double? = nil
    var notes: String? = nil
    var revisionID: UUID? = nil
    var createdAt: Date = Date()

    init(id: UUID = UUID()) { self.id = id }
}

/// Personal Coach record. Register only in the protected local container.
@Model
final class CoachNutritionLog {
    var id: UUID = UUID()
    var civilDate: String = ""
    var timeZoneIdentifier: String = ""
    var calories: Double? = nil
    var protein: Double? = nil
    var carbs: Double? = nil
    var fat: Double? = nil
    var targetSnapshotData: Data? = nil
    var statusRaw: String = "draft"
    var notes: String? = nil
    var createdAt: Date = Date()
    var updatedAt: Date = Date()

    init(id: UUID = UUID()) { self.id = id }
}

/// Personal Coach record. Register only in the protected local container.
@Model
final class CoachRecoveryCheckIn {
    var id: UUID = UUID()
    var civilDate: String = ""
    var timeZoneIdentifier: String = ""
    var manualSleepHours: Double? = nil
    var healthSleepHours: Double? = nil
    var healthSleepSource: String? = nil
    var healthSleepEndDate: Date? = nil
    @Attribute(.externalStorage) var healthSampleCoverageData: Data? = nil
    var sleepSourceRaw: String = "unavailable"
    var soreness: Int? = nil
    var energy: Int? = nil
    var painScore: Int? = nil
    var painLocation: String? = nil
    var notes: String? = nil
    var createdAt: Date = Date()
    var updatedAt: Date = Date()

    init(id: UUID = UUID()) { self.id = id }
}

/// Personal Coach record. Register only in the protected local container.
@Model
final class CoachWaistMeasurement {
    var id: UUID = UUID()
    var observedAt: Date = Date()
    var civilDate: String = ""
    var timeZoneIdentifier: String = ""
    var value: Double = 0
    var unit: String = "cm"
    var notes: String? = nil

    init(id: UUID = UUID()) { self.id = id }
}

/// Personal Coach record. Register only in the protected local container.
@Model
final class CoachProgressPhoto {
    var id: UUID = UUID()
    var observedAt: Date = Date()
    var civilDate: String = ""
    var timeZoneIdentifier: String = ""
    var pose: String? = nil
    var assetKey: String = ""
    var pixelWidth: Int = 0
    var pixelHeight: Int = 0
    var contentType: String = "image/jpeg"
    var digest: String = ""
    var byteCount: Int = 0
    var importState: String = "ready"
    var createdAt: Date = Date()

    init(id: UUID = UUID()) { self.id = id }
}

/// Personal Coach record. Register only in the protected local container.
@Model
final class CoachPhaseReview {
    var id: UUID = UUID()
    var planID: UUID = UUID()
    var phaseID: String = ""
    var revisionID: UUID? = nil
    var statusRaw: String = "awaiting_review"
    var notes: String? = nil
    var reviewedAt: Date? = nil

    init(id: UUID = UUID()) { self.id = id }
}

/// Personal Coach record. Register only in the protected local container.
@Model
final class CoachCalendarMapping {
    var id: UUID = UUID()
    var plannedSessionID: UUID = UUID()
    var calendarID: String = ""
    var eventID: String = ""
    var requestedStartDate: Date? = nil
    var exportedScheduleRevision: Int = 0
    var pendingProjection: Bool = false

    init(id: UUID = UUID()) { self.id = id }
}

extension CoachRecoveryCheckIn {
    var displayedSleepHours: Double? { manualSleepHours ?? healthSleepHours }
    var displayedSleepSource: String { manualSleepHours != nil ? "Manual" : (healthSleepHours != nil ? (healthSleepSource ?? "Health") : "Not available") }
}
