import Foundation
import SwiftData

// MARK: - Shared Models

struct SharedWorkoutSession: Codable, Identifiable {
    var id: UUID
    var title: String
    var notes: String?
    var exercises: [SharedExercise]
    var date: Date
}

struct SharedExercise: Codable, Identifiable {
    var id: UUID
    var name: String
    var order: Int
    var type: String // "strength" or "cardio"
    var sets: [SharedExerciseSet]
    var muscleGroup: String? // To help map back to definitions if needed
}

struct SharedExerciseSet: Codable, Identifiable {
    var id: UUID
    var setNumber: Int
    var reps: Int
    var weight: Double
    var weightUnit: String
    var durationSeconds: Int?
    var distance: Double?
    var distanceUnit: String?
    var notes: String?
    var isIsolated: Bool = false

    var effectiveReps: Int {
        isIsolated ? reps * 2 : reps
    }

    var displayRepsText: String {
        isIsolated ? "\(reps) x 2" : "\(reps) reps"
    }
}

import UniformTypeIdentifiers
import CoreTransferable

// MARK: - Import limits

/// Bounds applied to any `SharedWorkoutSession` that originates outside the app
/// (a `.paceplate` file, a drag/drop payload, or a share link). Shared workouts
/// are small by construction, so these limits are far above anything the app
/// itself produces while stopping a crafted payload from exhausting memory or
/// flooding the template library.
enum SharedWorkoutLimits {
    static let maxPayloadBytes = 2 * 1_024 * 1_024
    static let maxExercises = 200
    static let maxSetsPerExercise = 100
    static let maxTitleLength = 200
    static let maxExerciseNameLength = 200
    static let maxNotesLength = 4_000
    static let maxReps = 10_000
    static let maxWeight = 10_000.0
    static let maxDurationSeconds = 7 * 24 * 60 * 60
    static let maxDistance = 10_000.0
}

enum SharedWorkoutImportError: LocalizedError {
    case payloadTooLarge
    case tooManyExercises(Int)
    case tooManySets(exercise: String, count: Int)

    var errorDescription: String? {
        switch self {
        case .payloadTooLarge:
            return "This workout file is too large to import."
        case .tooManyExercises(let count):
            return "This workout lists \(count) exercises, which is more than Pace & Plates can import (\(SharedWorkoutLimits.maxExercises))."
        case .tooManySets(let exercise, let count):
            return "\"\(exercise)\" has \(count) sets, which is more than Pace & Plates can import per exercise (\(SharedWorkoutLimits.maxSetsPerExercise))."
        }
    }
}

extension SharedWorkoutSession {
    /// Single entry point for decoding untrusted shared-workout bytes. Enforces
    /// the size cap before `JSONDecoder` touches the data and normalizes the
    /// result so downstream code can rely on bounded, finite values.
    static func decodeUntrusted(_ data: Data) throws -> SharedWorkoutSession {
        guard data.count <= SharedWorkoutLimits.maxPayloadBytes else {
            throw SharedWorkoutImportError.payloadTooLarge
        }
        return try JSONDecoder().decode(SharedWorkoutSession.self, from: data).sanitizedForImport()
    }

    /// Rejects structurally abusive payloads and clamps individual fields into
    /// sane ranges. Out-of-range numbers and overlong strings are coerced rather
    /// than rejected so a slightly odd but genuine file still imports.
    func sanitizedForImport() throws -> SharedWorkoutSession {
        guard exercises.count <= SharedWorkoutLimits.maxExercises else {
            throw SharedWorkoutImportError.tooManyExercises(exercises.count)
        }

        var copy = self
        copy.title = Self.clampString(title, maxLength: SharedWorkoutLimits.maxTitleLength, fallback: "Shared Workout")
        copy.notes = notes.map { Self.clampString($0, maxLength: SharedWorkoutLimits.maxNotesLength, fallback: "") }
        copy.exercises = try exercises.map { exercise in
            guard exercise.sets.count <= SharedWorkoutLimits.maxSetsPerExercise else {
                throw SharedWorkoutImportError.tooManySets(exercise: exercise.name, count: exercise.sets.count)
            }
            var exercise = exercise
            exercise.name = Self.clampString(exercise.name, maxLength: SharedWorkoutLimits.maxExerciseNameLength, fallback: "Exercise")
            exercise.type = exercise.type == "cardio" ? "cardio" : "strength"
            exercise.order = max(0, exercise.order)
            exercise.muscleGroup = exercise.muscleGroup.map {
                Self.clampString($0, maxLength: SharedWorkoutLimits.maxExerciseNameLength, fallback: "Other")
            }
            exercise.sets = exercise.sets.map { set in
                var set = set
                set.setNumber = max(0, set.setNumber)
                set.reps = min(max(0, set.reps), SharedWorkoutLimits.maxReps)
                set.weight = Self.clampNumber(set.weight, max: SharedWorkoutLimits.maxWeight)
                set.weightUnit = UnitConverter.canonicalWeightUnit(set.weightUnit)
                set.durationSeconds = set.durationSeconds.map { min(max(0, $0), SharedWorkoutLimits.maxDurationSeconds) }
                set.distance = set.distance.map { Self.clampNumber($0, max: SharedWorkoutLimits.maxDistance) }
                set.distanceUnit = set.distanceUnit.map(UnitConverter.canonicalDistanceUnit)
                set.notes = set.notes.map { Self.clampString($0, maxLength: SharedWorkoutLimits.maxNotesLength, fallback: "") }
                return set
            }
            return exercise
        }
        return copy
    }

    private static func clampString(_ value: String, maxLength: Int, fallback: String) -> String {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return fallback }
        return String(trimmed.prefix(maxLength))
    }

    private static func clampNumber(_ value: Double, max upper: Double) -> Double {
        guard value.isFinite else { return 0 }
        return min(max(0, value), upper)
    }
}

private enum WorkoutShareFileExtension {
    static let preferred = "paceandplates"
    static let legacy = "paceplate"
    static let olderLegacy = "ppworkout"
}

extension UTType {
    static var paceAndPlatesWorkout: UTType {
        UTType(exportedAs: "com.justj0rsh.paceandplates.ppworkout", conformingTo: .json)
    }
    static var paceplate: UTType {
        UTType(exportedAs: "com.justj0rsh.paceandplates.paceplate", conformingTo: .json)
    }
}

extension SharedWorkoutSession: Transferable {
    static var transferRepresentation: some TransferRepresentation {
        FileRepresentation(contentType: .paceplate) { session in
            let fileURL = try makeTransferFile(
                for: session,
                fileExtension: WorkoutShareFileExtension.preferred,
                prettyPrinted: true
            )
            return SentTransferredFile(fileURL)
        } importing: { received in
            try SharedWorkoutSession.decodeUntrusted(try readBoundedFile(received.file))
        }

        DataRepresentation(contentType: .paceplate) { session in
            try encodedData(for: session, prettyPrinted: true)
        } importing: { data in
            try SharedWorkoutSession.decodeUntrusted(data)
        }

        // Backward compatibility: also accept legacy .ppworkout
        DataRepresentation(contentType: .paceAndPlatesWorkout) { session in
            try encodedData(for: session, prettyPrinted: true)
        } importing: { data in
            try SharedWorkoutSession.decodeUntrusted(data)
        }
        FileRepresentation(contentType: .paceAndPlatesWorkout) { session in
            let fileURL = try makeTransferFile(for: session, fileExtension: WorkoutShareFileExtension.olderLegacy)
            return SentTransferredFile(fileURL)
        } importing: { received in
            try SharedWorkoutSession.decodeUntrusted(try readBoundedFile(received.file))
        }
    }

    /// Reads a shared-workout file only after confirming it is within the payload
    /// limit, so an oversized file is rejected without being loaded into memory.
    fileprivate static func readBoundedFile(_ url: URL) throws -> Data {
        if let size = try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize,
           size > SharedWorkoutLimits.maxPayloadBytes {
            throw SharedWorkoutImportError.payloadTooLarge
        }
        return try Data(contentsOf: url)
    }

    fileprivate static func encodedData(for session: SharedWorkoutSession, prettyPrinted: Bool = false) throws -> Data {
        let encoder = JSONEncoder()
        if prettyPrinted {
            encoder.outputFormatting = .prettyPrinted
        }
        return try encoder.encode(session)
    }

    fileprivate static func makeTransferFile(
        for session: SharedWorkoutSession,
        fileExtension: String,
        prettyPrinted: Bool = false
    ) throws -> URL {
        let tempDir = FileManager.default.temporaryDirectory
        let fileName = "\(sanitizedFileStem(for: session.title)).\(fileExtension)"
        let fileURL = tempDir.appendingPathComponent(fileName)
        let data = try encodedData(for: session, prettyPrinted: prettyPrinted)
        try data.write(to: fileURL, options: .atomic)
        return fileURL
    }

    fileprivate static func sanitizedFileStem(for title: String) -> String {
        let safeTitle = title
            .components(separatedBy: .init(charactersIn: "/\\?%*|\"<>:"))
            .joined(separator: "_")
        return safeTitle.isEmpty ? "Workout" : safeTitle
    }
}

// MARK: - Service

class WorkoutSharingService {
    static let shared = WorkoutSharingService()
    
    private let scheme = "paceandplates"
    private let host = "share"
    private let path = "/workout"
    
    private init() {}
    
    // MARK: - File Export
    
    /// Exports a workout session to a temporary file URL
    func exportWorkout(session: WorkoutSession) -> URL? {
        let sharedSession = convertToShared(session)
        
        do {
            return try SharedWorkoutSession.makeTransferFile(
                for: sharedSession,
                fileExtension: WorkoutShareFileExtension.preferred,
                prettyPrinted: true
            )
        } catch {
            print("Error exporting workout: \(error)")
            return nil
        }
    }
    
    /// Parses a workout from a file URL. Throws `SharedWorkoutImportError` when
    /// the file violates import limits, or a decoding error when it is malformed.
    func parseWorkoutFile(url: URL) throws -> SharedWorkoutSession {
        // Start accessing security scoped resource if needed
        let isAccessing = url.startAccessingSecurityScopedResource()
        defer {
            if isAccessing {
                url.stopAccessingSecurityScopedResource()
            }
        }

        return try SharedWorkoutSession.decodeUntrusted(
            try SharedWorkoutSession.readBoundedFile(url)
        )
    }

    // MARK: - URL Scheme (Legacy/Fallback)
    
    /// Generates a shareable URL for the given workout session
    func generateShareURL(from session: WorkoutSession) -> URL? {
        let sharedSession = convertToShared(session)
        
        do {
            let jsonData = try JSONEncoder().encode(sharedSession)
            // Compress or base64 encode the data to fit in URL
            // For simplicity, we'll just base64 encode it. 
            // In a real app with large data, we might want to use a backend or compression.
            let base64String = jsonData.base64EncodedString()
            
            var components = URLComponents()
            components.scheme = scheme
            components.host = host
            components.path = path
            components.queryItems = [
                URLQueryItem(name: "data", value: base64String),
                URLQueryItem(name: "title", value: session.title) // Readable title for preview
            ]
            
            return components.url
        } catch {
            print("Failed to encode workout session: \(error)")
            return nil
        }
    }
    
    /// Parses a share URL and returns the SharedWorkoutSession. Throws
    /// `SharedWorkoutImportError` when the payload violates import limits;
    /// returns nil when the URL is not a recognizable workout link.
    func parseShareURL(_ url: URL) throws -> SharedWorkoutSession? {
        guard url.scheme == scheme,
              url.host == host,
              url.path == path else {
            return nil
        }
        
        guard let components = URLComponents(url: url, resolvingAgainstBaseURL: true),
              let queryItems = components.queryItems,
              let dataString = queryItems.first(where: { $0.name == "data" })?.value else {
            return nil
        }

        // Base64 expands by 4/3, so bound the encoded string before decoding it.
        guard dataString.utf8.count <= SharedWorkoutLimits.maxPayloadBytes * 4 / 3 + 4 else {
            throw SharedWorkoutImportError.payloadTooLarge
        }
        guard let data = Data(base64Encoded: dataString) else {
            return nil
        }

        return try SharedWorkoutSession.decodeUntrusted(data)
    }
    
    // MARK: - Conversion Helpers
    
    // MARK: - Conversion Helpers
    
    func convertToShared(_ session: WorkoutSession) -> SharedWorkoutSession {
        let logs = session.exerciseLogs ?? []
        let groups = Dictionary(grouping: logs) { $0.exerciseName ?? "Unknown Exercise" }
        
        var sharedExercises: [SharedExercise] = []
        
        for (name, exerciseLogs) in groups {
            // Use the first log to get common details
            guard let firstLog = exerciseLogs.first else { continue }
            
            let sortedLogs = exerciseLogs.sorted { $0.setNumber < $1.setNumber }
            
            let sharedSets = sortedLogs.map { log in
                SharedExerciseSet(
                    id: UUID(), // New ID for the shared set
                    setNumber: log.setNumber,
                    reps: log.reps,
                    weight: log.weight,
                    weightUnit: log.weightUnit,
                    durationSeconds: log.durationSeconds,
                    distance: log.distance,
                    distanceUnit: log.distanceUnit,
                    notes: log.notes,
                    isIsolated: log.isIsolated
                )
            }
            
            let sharedExercise = SharedExercise(
                id: UUID(),
                name: name,
                order: firstLog.exerciseOrder,
                type: firstLog.exerciseType ?? "strength",
                sets: sharedSets,
                muscleGroup: firstLog.exerciseDefinition?.muscleGroup
            )
            
            sharedExercises.append(sharedExercise)
        }
        
        // Sort exercises by order
        sharedExercises.sort { $0.order < $1.order }
        
        return SharedWorkoutSession(
            id: session.id,
            title: session.title,
            notes: session.notes,
            exercises: sharedExercises,
            date: session.date
        )
    }
}
