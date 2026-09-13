import Foundation
import SwiftData

extension CoachRepository {
    func photos() throws -> [CoachProgressPhoto] {
        try context.fetch(FetchDescriptor<CoachProgressPhoto>(sortBy: [SortDescriptor(\.observedAt, order: .reverse)]))
    }

    func assetURL(for photo: CoachProgressPhoto, thumbnail: Bool = false) throws -> URL {
        let original = try CoachPhotoStore.assetURL(for: photo.assetKey)
        let thumb = CoachPhotoStore.directory.appendingPathComponent("\(photo.id.uuidString).thumbnail.jpg")
        return thumbnail && FileManager.default.fileExists(atPath: thumb.path) ? thumb : original
    }

    @discardableResult
    func importPhoto(data: Data, observedAt: Date, pose: String? = nil) async throws -> UUID {
        try requireLocal()
        let generation = WearableWorkoutInboxService.localDataPurgeGeneration
        let prepared = try await Task.detached(priority: .userInitiated) { try CoachPhotoStore.prepare(data: data) }.value
        do {
            try Task.checkCancellation()
            guard WearableWorkoutInboxService.isCurrentLocalDataPurgeGeneration(generation) else { throw CancellationError() }
            // Finalizing before the database save ensures a committed metadata row
            // never references a file that was not durably written.
            try CoachPhotoStore.writeJournal(id: prepared.id, key: prepared.assetKey, operation: "import")
            try CoachPhotoStore.finalize(prepared)
            let savedID: UUID = try transaction { isolated in
                let photo = CoachProgressPhoto(id: prepared.id); photo.observedAt = observedAt
                photo.civilDate = Self.civilDate(observedAt); photo.timeZoneIdentifier = TimeZone.current.identifier; photo.pose = pose
                photo.assetKey = prepared.assetKey; photo.pixelWidth = prepared.width; photo.pixelHeight = prepared.height
                photo.digest = prepared.digest; photo.byteCount = prepared.byteCount; isolated.insert(photo)
                return photo.id
            }
            try? FileManager.default.removeItem(at: CoachPhotoStore.journalURL(prepared.id))
            return savedID
        } catch {
            CoachPhotoStore.cleanup(prepared, removeFinal: true)
            try? FileManager.default.removeItem(at: CoachPhotoStore.journalURL(prepared.id))
            throw error
        }
    }

    func deletePhoto(id: UUID) throws {
        try requireLocal()
        guard let current = try photos().first(where: { $0.id == id }) else { return }
        try CoachPhotoStore.writeJournal(id: id, key: current.assetKey, operation: "delete")
        let key: String? = try transaction { isolated in
            guard let photo = try isolated.fetch(FetchDescriptor<CoachProgressPhoto>()).first(where: { $0.id == id }) else { return nil }
            let key = photo.assetKey; isolated.delete(photo); return key
        }
        if let key {
            let asset = try CoachPhotoStore.assetURL(for: key)
            if FileManager.default.fileExists(atPath: asset.path) { try FileManager.default.removeItem(at: asset) }
        }
        try? FileManager.default.removeItem(at: CoachPhotoStore.directory.appendingPathComponent("\(id.uuidString).thumbnail.jpg"))
        try? FileManager.default.removeItem(at: CoachPhotoStore.journalURL(id))
    }

    /// Run once before presenting Coach after launch. Only assets named by an
    /// interrupted operation journal are considered; ordinary photos are never swept.
    func recoverPhotoImports() throws {
        try requireLocal()
        let directory = CoachPhotoStore.stagingDirectory
        guard FileManager.default.fileExists(atPath: directory.path) else { return }
        let existing = try photos()
        for url in try FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: [.isRegularFileKey, .isSymbolicLinkKey]) where url.lastPathComponent.hasSuffix(".photoimport.json") {
            let values = try url.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey, .fileSizeKey])
            guard values.isRegularFile == true, values.isSymbolicLink != true, (values.fileSize ?? Int.max) < 4096 else { throw CoachRepositoryError.invalidValue("photo recovery journal") }
            let journal = try JSONDecoder().decode(CoachPhotoStore.Journal.self, from: Data(contentsOf: url))
            guard CoachPhotoStore.isSafeAssetKey(journal.assetKey), journal.assetKey == "\(journal.id.uuidString).jpg" else { throw CoachRepositoryError.invalidValue("photo recovery identity") }
            if !existing.contains(where: { $0.id == journal.id }) {
                let final = try CoachPhotoStore.assetURL(for: journal.assetKey)
                if FileManager.default.fileExists(atPath: final.path) { try FileManager.default.removeItem(at: final) }
                try? FileManager.default.removeItem(at: CoachPhotoStore.directory.appendingPathComponent("\(journal.id.uuidString).thumbnail.jpg"))
            }
            try? FileManager.default.removeItem(at: directory.appendingPathComponent(journal.assetKey))
            try? FileManager.default.removeItem(at: directory.appendingPathComponent("\(journal.id.uuidString).thumbnail.jpg"))
            try FileManager.default.removeItem(at: url)
        }
        // Preparation may be interrupted before its commit journal is written.
        // Only old UUID-named files in this dedicated staging directory qualify.
        let cutoff = Date().addingTimeInterval(-3600)
        let referencedIDs = Set(existing.map(\.id))
        for url in try FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: [.creationDateKey, .isRegularFileKey, .isSymbolicLinkKey]) {
            let values = try url.resourceValues(forKeys: [.creationDateKey, .isRegularFileKey, .isSymbolicLinkKey])
            guard values.isRegularFile == true, values.isSymbolicLink != true, let created = values.creationDate, created < cutoff else { continue }
            let name = url.lastPathComponent
            let suffix = [".thumbnail.jpg", ".source", ".jpg"].first { name.hasSuffix($0) }
            guard let suffix, let id = UUID(uuidString: String(name.dropLast(suffix.count))), !referencedIDs.contains(id),
                  !FileManager.default.fileExists(atPath: CoachPhotoStore.journalURL(id).path) else { continue }
            try FileManager.default.removeItem(at: url)
        }
    }
}

extension CoachRepository {
    func updatePhoto(id: UUID, observedAt: Date, pose: String?) throws {
        try transaction { isolated in
            guard let row = try isolated.fetch(FetchDescriptor<CoachProgressPhoto>()).first(where: { $0.id == id }) else { throw CoachRepositoryError.missingRecord }
            row.observedAt = observedAt; row.civilDate = Self.civilDate(observedAt); row.timeZoneIdentifier = TimeZone.current.identifier; row.pose = pose
        }
    }

    @discardableResult
    func importPhoto(fileURL: URL, observedAt: Date, pose: String? = nil) async throws -> UUID {
        try requireLocal()
        let generation = WearableWorkoutInboxService.localDataPurgeGeneration
        let data = try await Task.detached(priority: .userInitiated) {
            let accessed = fileURL.startAccessingSecurityScopedResource()
            defer { if accessed { fileURL.stopAccessingSecurityScopedResource() } }
            let values = try fileURL.resourceValues(forKeys: [.fileSizeKey, .isRegularFileKey, .isSymbolicLinkKey])
            guard values.isRegularFile == true, values.isSymbolicLink != true,
                  let size = values.fileSize, size > 0, size <= CoachPhotoStore.maxSourceBytes else { throw CoachRepositoryError.invalidValue("photo smaller than 25 MiB") }
            let handle = try FileHandle(forReadingFrom: fileURL); defer { try? handle.close() }
            var data = Data()
            while true {
                try Task.checkCancellation()
                let chunk = try handle.read(upToCount: min(1_048_576, CoachPhotoStore.maxSourceBytes - data.count + 1)) ?? Data()
                if chunk.isEmpty { break }
                guard data.count + chunk.count <= CoachPhotoStore.maxSourceBytes else { throw CoachRepositoryError.invalidValue("photo smaller than 25 MiB") }
                data.append(chunk)
            }
            return data
        }.value
        guard WearableWorkoutInboxService.isCurrentLocalDataPurgeGeneration(generation) else { throw CancellationError() }
        return try await importPhoto(data: data, observedAt: observedAt, pose: pose)
    }
}
