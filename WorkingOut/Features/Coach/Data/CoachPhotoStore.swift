import Foundation
import CryptoKit
import ImageIO
import UniformTypeIdentifiers

struct CoachPreparedPhoto: Sendable {
    let id: UUID
    let assetKey: String
    let stagedURL: URL
    let thumbnailURL: URL
    let width: Int
    let height: Int
    let digest: String
    let byteCount: Int
}

enum CoachPhotoStore {
    struct Journal: Codable { let id: UUID; let assetKey: String; let operation: String }
    static func journalURL(_ id: UUID) -> URL { stagingDirectory.appendingPathComponent("\(id.uuidString).photoimport.json") }
    static func writeJournal(id: UUID, key: String, operation: String) throws {
        try CoachPersistence.protect(stagingDirectory, isDirectory: true)
        try JSONEncoder().encode(Journal(id: id, assetKey: key, operation: operation)).write(to: journalURL(id), options: [.atomic, .completeFileProtectionUnlessOpen])
    }
    static let maxSourceBytes = 25 * 1_024 * 1_024
    static let maxSourcePixels = 64_000_000
    static var directory: URL { CoachPersistence.directory.appendingPathComponent("Photos", isDirectory: true) }
    static var stagingDirectory: URL { CoachPersistence.directory.appendingPathComponent("PhotoStaging", isDirectory: true) }

    static func assetURL(for key: String) throws -> URL {
        guard isSafeAssetKey(key) else { throw CoachRepositoryError.invalidValue("photo asset name") }
        return directory.appendingPathComponent(key)
    }

    static func isSafeAssetKey(_ key: String) -> Bool {
        guard key.hasSuffix(".jpg"), !key.contains("/"), !key.contains("\\"), !key.contains("..") else { return false }
        return UUID(uuidString: String(key.dropLast(4))) != nil
    }

    static func prepare(data: Data, id: UUID = UUID()) throws -> CoachPreparedPhoto {
        guard data.count <= maxSourceBytes else { throw CoachRepositoryError.invalidValue("photo smaller than 25 MiB") }
        try CoachPersistence.protect(stagingDirectory, isDirectory: true)
        let sourceURL = stagingDirectory.appendingPathComponent("\(id.uuidString).source")
        try data.write(to: sourceURL, options: [.atomic, .completeFileProtectionUnlessOpen])
        defer { try? FileManager.default.removeItem(at: sourceURL) }
        guard let source = CGImageSourceCreateWithURL(sourceURL as CFURL, [kCGImageSourceShouldCache: false] as CFDictionary),
              let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
              let width = properties[kCGImagePropertyPixelWidth] as? Int,
              let height = properties[kCGImagePropertyPixelHeight] as? Int,
              width > 0, height > 0, width <= maxSourcePixels / height else { throw CoachRepositoryError.invalidValue("image up to 64 megapixels") }
        func image(maximum: Int) throws -> CGImage {
            let options: [CFString: Any] = [kCGImageSourceCreateThumbnailFromImageAlways: true,
                                          kCGImageSourceCreateThumbnailWithTransform: true,
                                          kCGImageSourceThumbnailMaxPixelSize: maximum,
                                          kCGImageSourceShouldCacheImmediately: false]
            guard let image = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else { throw CoachRepositoryError.invalidValue("readable image") }
            return image
        }
        let retained = try image(maximum: 2048)
        let key = "\(id.uuidString).jpg"
        let staged = stagingDirectory.appendingPathComponent(key)
        let thumb = stagingDirectory.appendingPathComponent("\(id.uuidString).thumbnail.jpg")
        do {
            try writeJPEG(retained, to: staged)
            try writeJPEG(image(maximum: 512), to: thumb)
            let bytes = try Data(contentsOf: staged)
            return CoachPreparedPhoto(id: id, assetKey: key, stagedURL: staged, thumbnailURL: thumb, width: retained.width,
                                      height: retained.height, digest: digest(bytes), byteCount: bytes.count)
        } catch {
            try? FileManager.default.removeItem(at: staged); try? FileManager.default.removeItem(at: thumb); throw error
        }
    }

    private static func writeJPEG(_ image: CGImage, to url: URL) throws {
        guard let destination = CGImageDestinationCreateWithURL(url as CFURL, UTType.jpeg.identifier as CFString, 1, nil) else { throw CoachRepositoryError.invalidValue("photo destination") }
        // Encoding the transformed pixel image with only compression settings
        // discards the source's location, camera, and other metadata.
        CGImageDestinationAddImage(destination, image, [kCGImageDestinationLossyCompressionQuality: 0.88] as CFDictionary)
        guard CGImageDestinationFinalize(destination) else { throw CoachRepositoryError.invalidValue("photo file") }
        try CoachPersistence.protect(url)
    }

    static func finalize(_ photo: CoachPreparedPhoto) throws {
        try CoachPersistence.protect(directory, isDirectory: true)
        try FileManager.default.moveItem(at: photo.stagedURL, to: assetURL(for: photo.assetKey))
        do { try FileManager.default.moveItem(at: photo.thumbnailURL, to: directory.appendingPathComponent("\(photo.id.uuidString).thumbnail.jpg")) }
        catch { try? FileManager.default.removeItem(at: assetURL(for: photo.assetKey)); throw error }
    }

    static func cleanup(_ photo: CoachPreparedPhoto, removeFinal: Bool) {
        try? FileManager.default.removeItem(at: photo.stagedURL); try? FileManager.default.removeItem(at: photo.thumbnailURL)
        if removeFinal {
            if let url = try? assetURL(for: photo.assetKey) { try? FileManager.default.removeItem(at: url) }
            try? FileManager.default.removeItem(at: directory.appendingPathComponent("\(photo.id.uuidString).thumbnail.jpg"))
        }
    }

    static func verifyRetainedFile(_ url: URL) throws {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, [kCGImageSourceShouldCache: false] as CFDictionary),
              CGImageSourceGetType(source) as String? == UTType.jpeg.identifier,
              let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
              let width = properties[kCGImagePropertyPixelWidth] as? Int, let height = properties[kCGImagePropertyPixelHeight] as? Int,
              (1...2048).contains(width), (1...2048).contains(height), properties[kCGImagePropertyGPSDictionary] == nil,
              CGImageSourceCreateImageAtIndex(source, 0, [kCGImageSourceShouldCache: false] as CFDictionary) != nil,
              CGImageSourceGetStatusAtIndex(source, 0) == .statusComplete else {
            throw CoachRepositoryError.invalidValue("complete app-owned JPEG image up to 2048 pixels without location metadata")
        }
    }

    static func digest(_ data: Data) -> String { SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined() }
}
