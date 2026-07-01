import Foundation
import SwiftData

@Model
final class RunningPlan {
    var id: UUID = UUID()
    var name: String = ""
    var source: String = "built_in" // built_in | ai
    var style: String = "hybrid"
    var targetDistanceMeters: Double = 0
    var primaryGoal: String = "hybrid"
    var durationWeeks: Int = 0
    var daysPerWeek: Int = 4
    var startDate: Date = Date()
    var isActive: Bool = false
    var isArchived: Bool = false
    var createdAt: Date = Date()
    var updatedAt: Date = Date()
    var profileSnapshotJSON: String? = nil
    var aiPrompt: String? = nil

    @Relationship(deleteRule: .cascade)
    var sessions: [RunningPlanSession]? = nil

    init(
        id: UUID = UUID(),
        name: String,
        source: String = "built_in",
        style: String,
        targetDistanceMeters: Double,
        primaryGoal: String,
        durationWeeks: Int,
        daysPerWeek: Int,
        startDate: Date,
        isActive: Bool = false,
        isArchived: Bool = false,
        createdAt: Date = Date(),
        updatedAt: Date = Date(),
        profileSnapshotJSON: String? = nil,
        aiPrompt: String? = nil
    ) {
        self.id = id
        self.name = name
        self.source = source
        self.style = style
        self.targetDistanceMeters = targetDistanceMeters
        self.primaryGoal = primaryGoal
        self.durationWeeks = durationWeeks
        self.daysPerWeek = daysPerWeek
        self.startDate = startDate
        self.isActive = isActive
        self.isArchived = isArchived
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.profileSnapshotJSON = profileSnapshotJSON
        self.aiPrompt = aiPrompt
    }
}
