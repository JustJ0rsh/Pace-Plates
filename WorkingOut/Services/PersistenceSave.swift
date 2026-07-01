import Foundation
import SwiftData
import os

enum PersistenceSave {
    private static let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "app.paceandplates", category: "persistence")

    @discardableResult
    static func commit(
        _ context: ModelContext,
        action: String,
        userMessage: String = "Couldn’t save your changes. Please try again.",
        onFailure: ((String) -> Void)? = nil
    ) -> Bool {
        do {
            try context.save()
            return true
        } catch {
            let nsError = error as NSError
            logger.error(
                "SwiftData save failed action=\(action, privacy: .public) domain=\(nsError.domain, privacy: .public) code=\(nsError.code)"
            )
            onFailure?(userMessage)
            return false
        }
    }
}
