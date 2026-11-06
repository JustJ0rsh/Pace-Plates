import Foundation
import CloudKit
import Darwin

struct CloudHistoryRestoreReview: Codable, Equatable, Sendable {
    let id: UUID
    let recordCount: Int
    let entityCounts: [String: Int]
    let earliestDate: Date?
    let latestDate: Date?
    let createdAt: Date
}

struct CloudHistoryRestorePlan: Codable, Sendable {
    struct RecordIdentity: Codable, Hashable, Sendable {
        let owner: String
        let zone: String
        let name: String
        init(_ id: CKRecord.ID) { owner = id.zoneID.ownerName; zone = id.zoneID.zoneName; name = id.recordName }
        var recordID: CKRecord.ID { .init(recordName: name, zoneID: .init(zoneName: zone, ownerName: owner)) }
    }
    let version: Int
    let review: CloudHistoryRestoreReview
    let storeIdentifier: String
    let accountFingerprint: String
    let records: [RecordIdentity]
    let payloadFingerprint: String

    func reviewForDisplay(storeIdentifier: String?, authorization: CloudHistoryRestoreAuthorization?) -> CloudHistoryRestoreReview? {
        guard self.storeIdentifier == storeIdentifier else { return nil }
        if let authorization, authorization.reviewID == review.id,
           [.consumed, .rejected].contains(authorization.state) { return nil }
        return review
    }

    func validate() throws {
        guard version == 1, review.recordCount > 0, review.recordCount == records.count,
              Set(records).count == records.count, UUID(uuidString: storeIdentifier) != nil,
              accountFingerprint.count == 64, payloadFingerprint.count == 64,
              accountFingerprint.allSatisfy(\.isHexDigit), payloadFingerprint.allSatisfy(\.isHexDigit),
              records.allSatisfy({ !$0.owner.isEmpty && !$0.zone.isEmpty && !$0.name.isEmpty }),
              review.entityCounts.values.allSatisfy({ $0 > 0 && $0 <= records.count }) else {
            throw CloudHistoryRestoreError.invalidReview
        }
        var total = 0
        for count in review.entityCounts.values {
            guard total <= records.count - count else { throw CloudHistoryRestoreError.invalidReview }
            total += count
        }
        guard total == records.count else { throw CloudHistoryRestoreError.invalidReview }
    }
}

struct CloudHistoryRestoreAuthorization: Codable, Sendable {
    enum State: String, Codable { case pending, consumed, canceled, rejected }
    let version: Int
    let reviewID: UUID
    let state: State
    let updatedAt: Date
}

enum CloudHistoryRestoreError: String, Error, LocalizedError {
    case invalidReview, reviewUnavailable, accountOrStoreChanged, snapshotChanged
    case authorizationUnavailable, receiptUnavailable, incompleteResponse
    var errorDescription: String? {
        switch self {
        case .invalidReview, .reviewUnavailable: return "This review is no longer available. Reopen the app to inspect retained history again."
        case .accountOrStoreChanged: return "The account or history store changed. Review the retained records again before restoring."
        case .snapshotChanged: return "Retained records changed since the review. Reopen the app to create a new review."
        case .authorizationUnavailable: return "Restore permission could not be verified. No new restoration was started."
        case .receiptUnavailable: return "The recovery request could not be saved safely. No new restoration was started."
        case .incompleteResponse: return "iCloud returned an incomplete result. Reopen the app to review what still needs restoration."
        }
    }
}

@MainActor
protocol CloudHistoryRestorePlanStoring {
    func plan() throws -> CloudHistoryRestorePlan?
    func authorization() throws -> CloudHistoryRestoreAuthorization?
    func save(_ plan: CloudHistoryRestorePlan) throws
    func consume(reviewID: UUID) throws
    func reject(reviewID: UUID) throws
    func clearReview() throws
    func finishInspection() throws
}

/// Plans contain private record identities, so they stay in protected,
/// backup-excluded app storage. Authorization is one use, persisted before saves.
@MainActor
final class CloudHistoryRestorePlanStore: CloudHistoryRestorePlanStoring {
    static var directory: URL {
        // The startup owner prepares this backup-excluded, protected parent.
        CoachLocalOwnership.root.appendingPathComponent("CloudHistoryRepair", isDirectory: true)
    }
    let directory: URL
    init(directory: URL? = nil) { self.directory = directory ?? Self.directory }
    private var planURL: URL { directory.appendingPathComponent("restore-review.json") }
    private var authorizationURL: URL { directory.appendingPathComponent("restore-authorization.json") }
    private var inspectionURL: URL { directory.appendingPathComponent("inspect-on-launch.json") }

    func plan() throws -> CloudHistoryRestorePlan? {
        let value: CloudHistoryRestorePlan? = try read(planURL)
        try value?.validate()
        return value
    }
    func authorization() throws -> CloudHistoryRestoreAuthorization? {
        let value: CloudHistoryRestoreAuthorization? = try read(authorizationURL)
        guard value?.version == nil || value?.version == 1 else { throw CloudHistoryRestoreError.authorizationUnavailable }
        return value
    }
    func save(_ plan: CloudHistoryRestorePlan) throws { try plan.validate(); try write(plan, to: planURL) }
    func authorize(reviewID: UUID) throws {
        guard try plan()?.review.id == reviewID else { throw CloudHistoryRestoreError.reviewUnavailable }
        if let previous = try authorization(), previous.reviewID == reviewID,
           [.consumed, .rejected].contains(previous.state) { throw CloudHistoryRestoreError.reviewUnavailable }
        try write(CloudHistoryRestoreAuthorization(version: 1, reviewID: reviewID, state: .pending, updatedAt: Date()), to: authorizationURL)
    }
    func consume(reviewID: UUID) throws {
        guard let current = try authorization(), current.reviewID == reviewID, current.state == .pending else {
            throw CloudHistoryRestoreError.authorizationUnavailable
        }
        try write(CloudHistoryRestoreAuthorization(version: 1, reviewID: reviewID, state: .consumed, updatedAt: Date()), to: authorizationURL)
    }
    func reject(reviewID: UUID) throws {
        guard let current = try authorization(), current.reviewID == reviewID, current.state == .pending else { return }
        try write(CloudHistoryRestoreAuthorization(version: 1, reviewID: reviewID, state: .rejected, updatedAt: Date()), to: authorizationURL)
    }
    func cancel() throws {
        guard let current = try authorization(), current.state == .pending else { return }
        try write(CloudHistoryRestoreAuthorization(version: 1, reviewID: current.reviewID, state: .canceled, updatedAt: Date()), to: authorizationURL)
    }
    func requestInspection() throws { try write(["version": 1], to: inspectionURL) }
    func inspectionIsRequested() throws -> Bool {
        let request: [String: Int]? = try read(inspectionURL)
        guard request == nil || request?["version"] == 1 else { throw CloudHistoryRestoreError.receiptUnavailable }
        return request != nil
    }
    func hasPendingWork() throws -> Bool {
        try inspectionIsRequested() || plan() != nil || authorization()?.state == .pending
    }
    func preflightIsRequested() throws -> Bool {
        try inspectionIsRequested() || authorization()?.state == .pending
    }
    func clearReview() throws {
        try remove(planURL); try remove(authorizationURL)
    }
    func finishInspection() throws { try remove(inspectionURL) }

    private func read<T: Decodable>(_ url: URL) throws -> T? {
        try withDirectory(create: false, missing: nil) { directoryFD in
            let descriptor = openat(directoryFD, url.lastPathComponent, O_RDONLY | O_NOFOLLOW)
            if descriptor < 0, errno == ENOENT { return nil }
            guard descriptor >= 0 else { throw CloudHistoryRestoreError.receiptUnavailable }
            defer { Darwin.close(descriptor) }
            var attributes = stat()
            let limit = 32 * 1_024 * 1_024
            guard fstat(descriptor, &attributes) == 0, attributes.st_mode & S_IFMT == S_IFREG, attributes.st_nlink == 1,
                  attributes.st_size >= 0, attributes.st_size <= limit else { throw CloudHistoryRestoreError.receiptUnavailable }
            let handle = FileHandle(fileDescriptor: descriptor, closeOnDealloc: false)
            var data = Data()
            while true {
                let chunk = try handle.read(upToCount: min(1_048_576, limit - data.count + 1)) ?? Data()
                if chunk.isEmpty { break }
                guard data.count + chunk.count <= limit else { throw CloudHistoryRestoreError.receiptUnavailable }
                data.append(chunk)
            }
            return try JSONDecoder().decode(T.self, from: data)
        }
    }
    private func write<T: Encodable>(_ value: T, to url: URL) throws {
        try withDirectory(create: true, missing: ()) { directoryFD in
            try checkFile(url.lastPathComponent, in: directoryFD)
            let temporary = ".receipt-\(UUID().uuidString).tmp"
            let descriptor = openat(directoryFD, temporary, O_WRONLY | O_CREAT | O_EXCL | O_NOFOLLOW, 0o600)
            guard descriptor >= 0 else { throw CloudHistoryRestoreError.receiptUnavailable }
            defer { Darwin.close(descriptor); unlinkat(directoryFD, temporary, 0) }
            let handle = FileHandle(fileDescriptor: descriptor, closeOnDealloc: false)
            try handle.write(contentsOf: JSONEncoder().encode(value))
            try handle.synchronize()
            guard renameat(directoryFD, temporary, directoryFD, url.lastPathComponent) == 0,
                  fsync(directoryFD) == 0 else { throw CloudHistoryRestoreError.receiptUnavailable }
        }
    }
    private func remove(_ url: URL) throws {
        try withDirectory(create: false, missing: ()) { directoryFD in
            try checkFile(url.lastPathComponent, in: directoryFD)
            if unlinkat(directoryFD, url.lastPathComponent, 0) != 0 {
                guard errno == ENOENT else { throw CloudHistoryRestoreError.receiptUnavailable }
            } else if fsync(directoryFD) != 0 { throw CloudHistoryRestoreError.receiptUnavailable }
        }
    }

    private func checkFile(_ name: String, in directoryFD: Int32) throws {
        var attributes = stat()
        if fstatat(directoryFD, name, &attributes, AT_SYMLINK_NOFOLLOW) == 0 {
            guard attributes.st_mode & S_IFMT == S_IFREG, attributes.st_nlink == 1 else { throw CloudHistoryRestoreError.receiptUnavailable }
        } else if errno != ENOENT { throw CloudHistoryRestoreError.receiptUnavailable }
    }

    /// Walk every directory without following links; all subsequent operations
    /// stay relative to that descriptor. Only Apple's fixed /var and /tmp
    /// aliases are normalized, rather than resolving arbitrary caller links.
    /// The app container is opened directly because the sandbox rejects an
    /// O_NOFOLLOW walk through the system directories above it.
    private func withDirectory<T>(create: Bool, missing: T, _ operation: (Int32) throws -> T) throws -> T {
        guard directory.isFileURL, directory.path.hasPrefix("/") else { throw CloudHistoryRestoreError.receiptUnavailable }
        var path = directory.standardizedFileURL.path
        if path == "/var" || path.hasPrefix("/var/") { path = "/private" + path }
        if path == "/tmp" || path.hasPrefix("/tmp/") { path = "/private" + path }
        let components = path.split(separator: "/").map(String.init)
        guard !components.isEmpty else { throw CloudHistoryRestoreError.receiptUnavailable }
        // Links inside the container are still rejected. The container root
        // itself is opened normally so Apple's own directory aliases work.
        let containerIndex = components.lastIndex(of: "Library") ?? components.lastIndex(of: "tmp")
        let head: String
        let tail: ArraySlice<String>
        if let containerIndex, containerIndex > 0 {
            head = "/" + components[..<containerIndex].joined(separator: "/")
            tail = components[containerIndex...]
        } else {
            head = "/"
            tail = components[...]
        }
        var descriptor = Darwin.open(head, O_RDONLY | O_DIRECTORY)
        guard descriptor >= 0 else { throw CloudHistoryRestoreError.receiptUnavailable }
        defer { Darwin.close(descriptor) }
        do {
            for (index, component) in tail.enumerated() {
                let next = openat(descriptor, component, O_RDONLY | O_DIRECTORY | O_NOFOLLOW)
                let openError = errno
                if next < 0, openError == ENOENT, index == tail.count - 1 {
                    if !create { return missing }
                    guard mkdirat(descriptor, component, 0o700) == 0 || errno == EEXIST else { throw CloudHistoryRestoreError.receiptUnavailable }
                    let created = openat(descriptor, component, O_RDONLY | O_DIRECTORY | O_NOFOLLOW)
                    guard created >= 0 else { throw CloudHistoryRestoreError.receiptUnavailable }
                    Darwin.close(descriptor)
                    descriptor = created
                    continue
                }
                guard next >= 0 else { throw CloudHistoryRestoreError.receiptUnavailable }
                Darwin.close(descriptor)
                descriptor = next
            }
            return try operation(descriptor)
        } catch { throw CloudHistoryRestoreError.receiptUnavailable }
    }
}
