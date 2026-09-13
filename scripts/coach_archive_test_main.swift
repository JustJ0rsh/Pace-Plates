// Compile with the real CoachHistoryArchive.swift and CoachPhotoStore.swift.
// Minimal model/storage adapters isolate file-boundary tests from SwiftData/UI.
import Foundation
import CryptoKit
import ImageIO
import UniformTypeIdentifiers

enum CoachRepositoryError: Error { case invalidValue(String) }
enum CoachPersistence {
    static let directory = FileManager.default.temporaryDirectory.appendingPathComponent("coach-archive-tests-\(UUID().uuidString)", isDirectory: true)
    static func protect(_ url: URL, isDirectory: Bool = false) throws {
        if isDirectory { try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true) }
        var copy = url; var values = URLResourceValues(); values.isExcludedFromBackup = true; try copy.setResourceValues(values)
    }
}
struct CoachBackupGraph: Codable, Sendable {
    struct Photo: Codable, Sendable {
        var id: UUID; var assetKey: String; var digest: String; var byteCount: Int
    }
    var photos: [Photo]
    func validate() throws {
        guard Set(photos.map(\.id)).count == photos.count else { throw CoachHistoryArchive.ArchiveError.invalid("Duplicate identity") }
    }
}
struct BackupFile: Codable, Sendable { var formatVersion: Int = 5; var coach: CoachBackupGraph?; var marker: String }

@main struct CoachArchiveTests {
    static func main() throws {
        defer { try? FileManager.default.removeItem(at: CoachPersistence.directory) }
        try CoachPersistence.protect(CoachPhotoStore.directory, isDirectory: true)
        var checks = 0
        func check(_ condition: @autoclosure () throws -> Bool, _ message: String) throws {
            guard try condition() else { fatalError(message) }; checks += 1
        }
        func reject(_ message: String, _ operation: () throws -> Void) throws {
            do { try operation(); fatalError("Expected rejection: \(message)") } catch { checks += 1 }
        }
        let id = UUID(); let key = "\(id.uuidString).jpg"
        var noise = [UInt8](repeating: 255, count: 1200 * 1200 * 4)
        var randomState: UInt64 = 42
        for index in noise.indices where index % 4 != 3 {
            randomState = randomState &* 6364136223846793005 &+ 1442695040888963407
            noise[index] = UInt8(truncatingIfNeeded: randomState >> 32)
        }
        let provider = CGDataProvider(data: Data(noise) as CFData)!
        let noiseImage = CGImage(width: 1200, height: 1200, bitsPerComponent: 8, bitsPerPixel: 32, bytesPerRow: 1200 * 4,
            space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue), provider: provider, decode: nil, shouldInterpolate: false, intent: .defaultIntent)!
        let jpegData = NSMutableData()
        let encoder = CGImageDestinationCreateWithData(jpegData, UTType.jpeg.identifier as CFString, 1, nil)!
        CGImageDestinationAddImage(encoder, noiseImage, [kCGImageDestinationLossyCompressionQuality: 1.0] as CFDictionary)
        precondition(CGImageDestinationFinalize(encoder))
        let bytes = jpegData as Data
        let original = try CoachPhotoStore.assetURL(for: key); try bytes.write(to: original)
        let file = BackupFile(coach: CoachBackupGraph(photos: [.init(id: id, assetKey: key, digest: CoachPhotoStore.digest(bytes), byteCount: bytes.count)]), marker: "exact dates, IDs and zero versus missing")
        let archive = try CoachHistoryArchive.export(file, includePhotos: true)
        defer { try? FileManager.default.removeItem(at: archive) }
        let prepared = try CoachHistoryArchive.prepareImport(from: archive)
        try check(prepared.file.marker == file.marker, "Record round trip")
        try check(prepared.manifest?.photosIncluded == true, "Photos-included marker")
        try check(prepared.manifest?.assets.count == 1, "Asset count")
        try check(try Data(contentsOf: prepared.directory!.appendingPathComponent(key)) == bytes, "Streamed asset bytes")
        try FileManager.default.removeItem(at: original)
        try prepared.installAssets()
        try check(try Data(contentsOf: original) == bytes, "Asset install")
        try prepared.installAssets()
        try check(try CoachHistoryArchive.pendingRestores().count == 1, "Interruption journal replay")
        try check(try CoachHistoryArchive.pendingRestores()[0].rollbackOnly, "Interrupted precommit restore chooses deterministic rollback")
        prepared.discard()
        try check(try CoachHistoryArchive.pendingRestores().isEmpty, "Committed restore cleanup")
        let interruptedCopy = try CoachHistoryArchive.prepareImport(from: archive)
        let partial = interruptedCopy.installationURL(for: key)!
        try Data(bytes.prefix(128)).write(to: partial)
        try interruptedCopy.rollbackAssets(keeping: [key])
        try check(!FileManager.default.fileExists(atPath: partial.path), "Interrupted partial installation is removed even when committed image is retained")
        try check(try Data(contentsOf: original) == bytes, "Rollback preserves a committed referenced image")
        interruptedCopy.discard()
        let collisionCopy = try CoachHistoryArchive.prepareImport(from: archive)
        let otherBytes = Data("pre-existing unrelated collision".utf8)
        try otherBytes.write(to: original)
        try reject("different existing image") { try collisionCopy.installAssets() }
        try collisionCopy.rollbackAssets(keeping: [])
        try check(try Data(contentsOf: original) == otherBytes, "Failed restore rollback does not remove pre-existing different content")
        try FileManager.default.removeItem(at: original)
        try collisionCopy.installAssets()
        try check(try Data(contentsOf: original) == bytes, "Resolved collision can retry the same validated restore")
        collisionCopy.discard()
        let damagedStage = try CoachHistoryArchive.prepareImport(from: archive)
        try FileManager.default.removeItem(at: original)
        try Data(bytes.prefix(128)).write(to: damagedStage.directory!.appendingPathComponent(key))
        try reject("truncated staged image") { try damagedStage.installAssets() }
        try check(!FileManager.default.fileExists(atPath: original.path) && !FileManager.default.fileExists(atPath: damagedStage.installationURL(for: key)!.path), "Invalid stage creates neither final nor partial output")
        damagedStage.discard()
        let retryCopy = try CoachHistoryArchive.prepareImport(from: archive)
        try retryCopy.installAssets()
        try check(try Data(contentsOf: original) == bytes, "Clean retry succeeds after interrupted staging")
        try retryCopy.rollbackAssets(keeping: [])
        try check(!FileManager.default.fileExists(atPath: original.path), "Precommit rollback removes only its unreferenced complete image")
        try retryCopy.installAssets()
        retryCopy.discard()
        var corrupt = try Data(contentsOf: archive); corrupt[corrupt.count - 1] ^= 1
        let corruptedURL = CoachPersistence.directory.appendingPathComponent("corrupt.pacebackup"); try corrupt.write(to: corruptedURL)
        try reject("photo digest") { _ = try CoachHistoryArchive.prepareImport(from: corruptedURL) }
        try Data(corrupt.prefix(45)).write(to: corruptedURL)
        try reject("truncated manifest") { _ = try CoachHistoryArchive.prepareImport(from: corruptedURL) }
        var trailing = try Data(contentsOf: archive); trailing.append(1); try trailing.write(to: corruptedURL)
        try reject("trailing data") { _ = try CoachHistoryArchive.prepareImport(from: corruptedURL) }
        let without = BackupFile(coach: CoachBackupGraph(photos: []), marker: "without photos")
        let noPhotos = try CoachHistoryArchive.export(without, includePhotos: false)
        defer { try? FileManager.default.removeItem(at: noPhotos) }
        let p2 = try CoachHistoryArchive.prepareImport(from: noPhotos)
        try check(p2.manifest?.photosIncluded == false && p2.file.coach?.photos.isEmpty == true, "Explicit no-photo export")
        p2.discard()
        let old = CoachPersistence.directory.appendingPathComponent("legacy.json")
        try JSONEncoder().encode(without).write(to: old)
        try check(try CoachHistoryArchive.prepareImport(from: old).file.marker == "without photos", "Legacy JSON route")
        try JSONEncoder().encode(file).write(to: old)
        try reject("JSON missing image assets") { _ = try CoachHistoryArchive.prepareImport(from: old) }
        let emptyRecords = try JSONEncoder().encode(without)
        func malicious(_ entries: [CoachHistoryArchive.Entry]) throws {
            let manifest = CoachHistoryArchive.Manifest(format: "pace-and-plates.history", version: 5, photosIncluded: true,
                records: .init(path: "records.json", bytes: emptyRecords.count, digest: CoachPhotoStore.digest(emptyRecords)), assets: entries)
            let metadata = try JSONEncoder().encode(manifest); var payload = CoachHistoryArchive.magic
            var count = UInt64(metadata.count).bigEndian
            withUnsafeBytes(of: &count) { payload.append(contentsOf: $0) }; payload.append(metadata); payload.append(emptyRecords)
            try payload.write(to: corruptedURL)
        }
        let digest = String(repeating: "a", count: 64)
        try malicious([.init(path: "photos/../secret.jpg", bytes: 1, digest: digest)])
        try reject("traversal") { _ = try CoachHistoryArchive.prepareImport(from: corruptedURL) }
        try malicious([.init(path: "/etc/passwd", bytes: 1, digest: digest)])
        try reject("absolute path") { _ = try CoachHistoryArchive.prepareImport(from: corruptedURL) }
        let e = CoachHistoryArchive.Entry(path: "photos/\(key)", bytes: 1, digest: digest)
        try malicious([e, e])
        try reject("duplicate entries") { _ = try CoachHistoryArchive.prepareImport(from: corruptedURL) }
        try malicious([.init(path: "photos/\(key)", bytes: CoachHistoryArchive.maxAsset + 1, digest: digest)])
        try reject("oversized asset declaration") { _ = try CoachHistoryArchive.prepareImport(from: corruptedURL) }
        let symlink = CoachPersistence.directory.appendingPathComponent("link")
        try FileManager.default.createSymbolicLink(at: symlink, withDestinationURL: archive)
        try reject("symlink input") { _ = try CoachHistoryArchive.prepareImport(from: symlink) }
        try reject("corrupt image import") { _ = try CoachPhotoStore.prepare(data: Data("not an image".utf8)) }
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        let bitmap = CGContext(data: nil, width: 3000, height: 1000, bitsPerComponent: 8, bytesPerRow: 3000 * 4, space: colorSpace, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        bitmap.setFillColor(CGColor(red: 0.2, green: 0.5, blue: 0.7, alpha: 1)); bitmap.fill(CGRect(x: 0, y: 0, width: 3000, height: 1000))
        let sourceImage = bitmap.makeImage()!
        let imageURL = CoachPersistence.directory.appendingPathComponent("synthetic-source.jpg")
        let writer = CGImageDestinationCreateWithURL(imageURL as CFURL, UTType.jpeg.identifier as CFString, 1, nil)!
        CGImageDestinationAddImage(writer, sourceImage, [kCGImagePropertyOrientation: 6,
            kCGImagePropertyGPSDictionary: [kCGImagePropertyGPSLatitude: 12.3, kCGImagePropertyGPSLongitude: 45.6]] as CFDictionary)
        precondition(CGImageDestinationFinalize(writer))
        let photo = try CoachPhotoStore.prepare(data: Data(contentsOf: imageURL))
        defer { CoachPhotoStore.cleanup(photo, removeFinal: false) }
        try check(max(photo.width, photo.height) == 2048 && photo.height > photo.width, "Photo orientation normalized and longest edge bounded")
        let savedImage = CGImageSourceCreateWithURL(photo.stagedURL as CFURL, nil)!
        let properties = CGImageSourceCopyPropertiesAtIndex(savedImage, 0, nil)! as NSDictionary
        try check(properties[kCGImagePropertyGPSDictionary] == nil, "Location metadata removed from owned pixels")
        let thumbSource = CGImageSourceCreateWithURL(photo.thumbnailURL as CFURL, nil)!
        let thumbImage = CGImageSourceCreateImageAtIndex(thumbSource, 0, nil)!
        try check(max(thumbImage.width, thumbImage.height) == 512, "Bounded thumbnail generated")
        try check(CoachPhotoStore.digest(Data(contentsOf: photo.stagedURL)) == photo.digest, "Retained image digest matches pixels")
        try check(!CoachPhotoStore.isSafeAssetKey("../../\(key)"), "Photo paths constrained")
        print("Coach archive: \(checks) checks passed")
    }
}
