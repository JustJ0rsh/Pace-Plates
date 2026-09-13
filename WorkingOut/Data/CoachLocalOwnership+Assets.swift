import Foundation
import CryptoKit

extension CoachLocalOwnership {
    /// SwiftData/Core Data stores @Attribute(.externalStorage) blobs beside the
    /// SQLite file in .<store stem>_SUPPORT. SQLite backup cannot copy these.
    /// The destination is unselected and disposable until this copy verifies.
    static func copyAuxiliaryFiles(from source: URL, to destination: URL) throws {
        let manager = FileManager.default
        let sourceSupport = source.deletingLastPathComponent().appendingPathComponent(".\(source.deletingPathExtension().lastPathComponent)_SUPPORT", isDirectory: true)
        let destinationSupport = destination.deletingLastPathComponent().appendingPathComponent(".\(destination.deletingPathExtension().lastPathComponent)_SUPPORT", isDirectory: true)
        guard manager.fileExists(atPath: sourceSupport.path) else { return }
        let sourceValues = try sourceSupport.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey])
        guard sourceValues.isDirectory == true, sourceValues.isSymbolicLink != true,
              !manager.fileExists(atPath: destinationSupport.path) else {
            throw OwnershipError.unavailable("The source data assets could not be copied safely. The original store has been retained.")
        }
        try prepareDirectory(destinationSupport)
        guard let enumerator = manager.enumerator(at: sourceSupport,
                                                  includingPropertiesForKeys: [.isDirectoryKey, .isRegularFileKey, .isSymbolicLinkKey, .fileSizeKey],
                                                  options: []) else {
            throw OwnershipError.unavailable("The original store's external data assets could not be read.")
        }
        let sourcePrefix = sourceSupport.resolvingSymlinksInPath().standardizedFileURL.path + "/"
        for case let entry as URL in enumerator {
            try Task.checkCancellation()
            let values = try entry.resourceValues(forKeys: [.isDirectoryKey, .isRegularFileKey, .isSymbolicLinkKey, .fileSizeKey])
            guard values.isSymbolicLink != true, values.isDirectory == true || values.isRegularFile == true else {
                throw OwnershipError.unavailable("A storage asset is a link or unsupported file. Migration stopped without selecting the copy.")
            }
            let path = entry.resolvingSymlinksInPath().standardizedFileURL.path
            guard path.hasPrefix(sourcePrefix) else { throw OwnershipError.unavailable("A storage asset was outside its source directory.") }
            let relative = String(path.dropFirst(sourcePrefix.count))
            let target = destinationSupport.appendingPathComponent(relative, isDirectory: values.isDirectory == true)
            if values.isDirectory == true { try prepareDirectory(target); continue }
            let before = try auxiliaryDigest(entry)
            try manager.copyItem(at: entry, to: target)
            try manager.setAttributes([.protectionKey: FileProtectionType.completeUntilFirstUserAuthentication], ofItemAtPath: target.path)
            var protectedTarget = target; var exclusions = URLResourceValues(); exclusions.isExcludedFromBackup = true
            try protectedTarget.setResourceValues(exclusions)
            // Rechecking the source also detects a replacement while the copy
            // was in progress. A changed source requires a fresh attempt.
            guard try auxiliaryDigest(target) == before, try auxiliaryDigest(entry) == before else {
                throw OwnershipError.unavailable("An external data asset changed during migration. Retry after current activity has finished.")
            }
        }
    }

    private static func auxiliaryDigest(_ url: URL) throws -> Data {
        let handle = try FileHandle(forReadingFrom: url); defer { try? handle.close() }
        var digest = SHA256()
        while true {
            try Task.checkCancellation()
            let data = try handle.read(upToCount: 1_048_576) ?? Data()
            if data.isEmpty { break }; digest.update(data: data)
        }
        return Data(digest.finalize())
    }
}
