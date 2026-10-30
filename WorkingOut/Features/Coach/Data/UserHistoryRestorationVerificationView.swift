#if DEBUG
import SwiftUI
import SwiftData

/// Restores only the explicitly staged copy, with every CloudKit connection disabled.
struct UserHistoryRestorationVerificationView: View {
    @State private var status = "Verifying the staged history copy…"
    @State private var started = false

    var body: some View {
        VStack(spacing: 20) {
            Text("History restoration verification").font(.title2.bold())
            Text(status).accessibilityIdentifier("user-history-restoration.result")
        }
        .padding()
        .task {
            guard !started else { return }
            started = true
            guard AppLaunchConfiguration.current.isUITest,
                  AppLaunchConfiguration.current.fixtureName == "user_history_restore_checks" else {
                status = "FAIL: This check requires the explicit isolated UI-test fixture."
                return
            }
            let receipt = UserHistoryRestorationVerification.run()
            status = receipt.result == "passed"
                ? "PASS: All \(receipt.beforeCounts.count) model counts preserved (\(receipt.totalBefore) → \(receipt.totalAfter) rows)."
                : "FAIL: \(receipt.message)"
            do {
                let encoder = JSONEncoder()
                encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
                try encoder.encode(receipt).write(
                    to: UserHistoryRestorationVerification.root.appendingPathComponent("result.json"),
                    options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication]
                )
            } catch {
                status = "FAIL: Could not save the verification receipt."
            }
        }
    }
}

@MainActor
private enum UserHistoryRestorationVerification {
    static var root: URL {
        FileManager.default.temporaryDirectory.appendingPathComponent("UserHistoryRestore", isDirectory: true)
    }

    struct Receipt: Encodable {
        var result = "failed"
        let suite = "user_history_restore_checks"
        let scope = "Staged copy only; CloudKit disabled"
        let countPolicy = "After count must be at least the selected source count for each model; ambiguous older selections retain original rows."
        let graphVerification = "Production restoration verifies copied attributes and relationships before installation."
        let startedAt = ISO8601DateFormatter().string(from: Date())
        var beforeCounts: [String: Int] = [:]
        var afterCounts: [String: Int] = [:]
        var totalBefore = 0
        var totalAfter = 0
        var message = "Verification did not finish."
        var errorType: String?
        var errorDomain: String?
        var errorCode: Int?
    }

    private enum VerificationError: String, Error {
        case unauthorized = "This check requires the explicit isolated UI-test fixture."
        case missingCopy = "The staged history copy is missing or is an unsupported link."
        case missingSelection = "The staged local history selection is missing."
        case emptyCopy = "The staged source contains no history rows."
        case countMismatch = "One or more model counts decreased during restoration."
    }

    static func run() -> Receipt {
        var receipt = Receipt()
        do {
            let launch = AppLaunchConfiguration.current
            guard launch.isUITest, launch.fixtureName == "user_history_restore_checks" else {
                throw VerificationError.unauthorized
            }
            let ownershipRoot = root.appendingPathComponent("ownership", isDirectory: true)
            let legacyURL = root.appendingPathComponent("default.store")
            try requireStagedItem(root, directory: true)
            try requireStagedItem(ownershipRoot, directory: true)
            try requireStagedItem(legacyURL, directory: false)
            guard let selectedURL = try CoachLocalOwnership.selectedStoreURL(root: ownershipRoot) else {
                throw VerificationError.missingSelection
            }
            try requireStagedItem(selectedURL, directory: false)

            // Release the source container before the production restoration opens its copies.
            receipt.beforeCounts = try autoreleasepool {
                let schema = PersistenceController.coachSchema
                let source = try ModelContainer(for: schema, configurations: [
                    ModelConfiguration(CoachPersistence.configurationName, schema: schema,
                                       url: selectedURL, cloudKitDatabase: .none)
                ])
                return try counts(in: source.mainContext)
            }
            receipt.totalBefore = receipt.beforeCounts.values.reduce(0, +)
            guard receipt.totalBefore > 0 else { throw VerificationError.emptyCopy }

            let coachURL = try CloudSyncRestoration.prepare(legacyURL: legacyURL, ownershipRoot: ownershipRoot)
            receipt.afterCounts = try autoreleasepool {
                let restored = try CloudSyncRestoration.makeContainer(
                    legacyURL: legacyURL, coachURL: coachURL, cloudKitMode: .none
                )
                return try counts(in: restored.mainContext)
            }
            receipt.totalAfter = receipt.afterCounts.values.reduce(0, +)
            guard receipt.beforeCounts.allSatisfy({ name, count in
                (receipt.afterCounts[name] ?? -1) >= count
            }) else { throw VerificationError.countMismatch }
            receipt.result = "passed"
            receipt.message = "Production restoration completed and every model count was preserved."
        } catch {
            // Core Data errors can embed personal record values in their descriptions.
            if let verificationError = error as? VerificationError {
                receipt.message = verificationError.rawValue
            } else if case let CoachLocalOwnership.OwnershipError.unavailable(message) = error {
                receipt.message = message
            } else {
                receipt.message = "Production restoration failed."
            }
            receipt.errorType = String(reflecting: type(of: error))
            receipt.errorDomain = (error as NSError).domain
            receipt.errorCode = (error as NSError).code
        }
        return receipt
    }

    private static func requireStagedItem(_ url: URL, directory: Bool) throws {
        guard FileManager.default.fileExists(atPath: url.path) else { throw VerificationError.missingCopy }
        let values = try url.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey])
        guard values.isDirectory == directory, values.isSymbolicLink != true else {
            throw VerificationError.missingCopy
        }
    }

    private static func counts(in context: ModelContext) throws -> [String: Int] {
        var result: [String: Int] = [:]
        for model in PersistenceController.legacyModelTypes + CoachPersistence.modelTypes {
            result[String(describing: model)] = try count(model, in: context)
        }
        return result
    }

    private static func count<Model: PersistentModel>(_ model: Model.Type, in context: ModelContext) throws -> Int {
        try context.fetchCount(FetchDescriptor<Model>())
    }
}
#endif
