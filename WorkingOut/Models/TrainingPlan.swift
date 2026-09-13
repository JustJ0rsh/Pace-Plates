import Foundation
import SwiftData

/// A shared plan envelope used by Coach, regardless of whether the source is
/// an AI-generated mixed plan or the dedicated running-plan builder.
@Model
final class TrainingPlan {
    var id: UUID = UUID()

    var sourceProgramID: String? = nil
    var sourceRevision: Int = 0
    var fingerprint: String? = nil
    var currentRevisionID: UUID? = nil
    var startCivilDate: String? = nil
    var timeZoneIdentifier: String = ""
    var durationWeeks: Int = 0
    var activatedAt: Date? = nil
    var pausedAt: Date? = nil

    var title: String = ""
    var goal: String = ""
    var overview: String? = nil
    var guidance: String? = nil
    var source: String = "coach" // coach_ai | running_assistant | manual
    var status: String = "active" // draft | active | archived
    var startDate: Date = Date()
    var createdAt: Date = Date()
    var updatedAt: Date = Date()

    // Stable links back to the source feature. Keeping identifiers here avoids
    // coupling the shared Coach lifecycle to either source model's delete rules.
    var sourceAIConversationID: UUID? = nil
    var sourceRunningPlanID: UUID? = nil

    @Relationship(deleteRule: .cascade, inverse: \PlannedSession.plan)
    var sessions: [PlannedSession]? = nil

    init(
        id: UUID = UUID(),
        title: String,
        goal: String,
        overview: String? = nil,
        guidance: String? = nil,
        source: String,
        status: String = "active",
        startDate: Date,
        createdAt: Date = Date(),
        updatedAt: Date = Date(),
        sourceAIConversationID: UUID? = nil,
        sourceRunningPlanID: UUID? = nil
    ) {
        self.id = id
        self.title = title
        self.goal = goal
        self.overview = overview
        self.guidance = guidance
        self.source = source
        self.status = status
        self.startDate = startDate
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.sourceAIConversationID = sourceAIConversationID
        self.sourceRunningPlanID = sourceRunningPlanID
    }
}
