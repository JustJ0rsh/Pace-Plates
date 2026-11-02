import Foundation
import SwiftData

/// Coach's additional models stay local while the legacy history uses iCloud.
enum CoachPersistence {
    static let configurationName = "CoachLocal"

    static var modelTypes: [any PersistentModel.Type] {
        [CoachPlanRevision.self, CoachSessionExecution.self, CoachProgressionSuggestion.self,
         CoachNutritionTargetPeriod.self, CoachNutritionLog.self, CoachRecoveryCheckIn.self,
         CoachWaistMeasurement.self, CoachProgressPhoto.self, CoachPhaseReview.self,
         CoachCalendarMapping.self]
    }

    static var directory: URL {
        if let continued = LocalHistoryContinuation.activeDirectory {
            return continued.appendingPathComponent("CoachLocal", isDirectory: true)
        }
        return FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
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
        let coachNames = Set(modelTypes.map { String(describing: $0) })
        let configurations = context.container.configurations
        // An isolated full-schema fixture is also a valid Coach destination.
        if configurations.allSatisfy(\.isStoredInMemoryOnly) {
            return coachNames.isSubset(of: Set(context.container.schema.entities.map(\.name)))
        }
        return configurations.contains { configuration in
            guard configuration.name == configurationName else { return false }
            let names = configuration.schema?.entities.map(\.name) ?? []
            guard coachNames.isSubset(of: Set(names)) else { return false }
            return configuration.cloudKitContainerIdentifier == nil
        }
    }
}
