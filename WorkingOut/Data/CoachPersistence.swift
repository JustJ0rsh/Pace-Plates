import Foundation
import SwiftData

/// Storage utilities; activation and the reviewed legacy-store copy are owned by
/// PersistenceController. These helpers never open or change a cloud store.
enum CoachPersistence {
    static let configurationName = "CoachLocal"

    static var modelTypes: [any PersistentModel.Type] {
        [CoachPlanRevision.self, CoachSessionExecution.self, CoachProgressionSuggestion.self,
         CoachNutritionTargetPeriod.self, CoachNutritionLog.self, CoachRecoveryCheckIn.self,
         CoachWaistMeasurement.self, CoachProgressPhoto.self, CoachPhaseReview.self,
         CoachCalendarMapping.self]
    }

    static var directory: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("CoachLocal", isDirectory: true)
    }

    static func protect(_ url: URL, isDirectory: Bool = false) throws {
        if isDirectory {
            try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        }
        var excludedURL = url
        var values = URLResourceValues()
        values.isExcludedFromBackup = true
        try excludedURL.setResourceValues(values)
        #if os(iOS)
        try FileManager.default.setAttributes([.protectionKey: FileProtectionType.completeUntilFirstUserAuthentication], ofItemAtPath: url.path)
        #endif
    }

    @MainActor
    static func isLocal(_ context: ModelContext) -> Bool {
        context.container.configurations.allSatisfy { $0.name == configurationName || $0.isStoredInMemoryOnly }
            && context.container.schema.entities.contains { $0.name == "CoachNutritionLog" }
    }
}
