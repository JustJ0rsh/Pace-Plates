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
        FileRepresentation(contentType: .json) { session in
            let fileURL = try makeTransferFile(for: session, fileExtension: "json", prettyPrinted: true)
            return SentTransferredFile(fileURL)
        } importing: { received in
            let data = try Data(contentsOf: received.file)
            return try JSONDecoder().decode(SharedWorkoutSession.self, from: data)
        }

        DataRepresentation(contentType: .json) { session in
            try encodedData(for: session, prettyPrinted: true)
        } importing: { data in
            try JSONDecoder().decode(SharedWorkoutSession.self, from: data)
        }

        DataRepresentation(contentType: .paceplate) { session in
            try encodedData(for: session, prettyPrinted: true)
        } importing: { data in
            try JSONDecoder().decode(SharedWorkoutSession.self, from: data)
        }
        
        FileRepresentation(contentType: .paceplate) { session in
            let fileURL = try makeTransferFile(for: session, fileExtension: "paceplate", prettyPrinted: true)
            return SentTransferredFile(fileURL)
        } importing: { received in
            let data = try Data(contentsOf: received.file)
            return try JSONDecoder().decode(SharedWorkoutSession.self, from: data)
        }

        // Backward compatibility: also accept legacy .ppworkout
        DataRepresentation(contentType: .paceAndPlatesWorkout) { session in
            try encodedData(for: session, prettyPrinted: true)
        } importing: { data in
            try JSONDecoder().decode(SharedWorkoutSession.self, from: data)
        }
        FileRepresentation(contentType: .paceAndPlatesWorkout) { session in
            let fileURL = try makeTransferFile(for: session, fileExtension: "ppworkout")
            return SentTransferredFile(fileURL)
        } importing: { received in
            let data = try Data(contentsOf: received.file)
            return try JSONDecoder().decode(SharedWorkoutSession.self, from: data)
        }
    }

    private static func encodedData(for session: SharedWorkoutSession, prettyPrinted: Bool = false) throws -> Data {
        let encoder = JSONEncoder()
        if prettyPrinted {
            encoder.outputFormatting = .prettyPrinted
        }
        return try encoder.encode(session)
    }

    private static func makeTransferFile(
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

    private static func sanitizedFileStem(for title: String) -> String {
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
            let encoder = JSONEncoder()
            encoder.outputFormatting = .prettyPrinted
            let data = try encoder.encode(sharedSession)
            
            // Create a temporary file
            let tempDir = FileManager.default.temporaryDirectory
            let safeTitle = session.title
                .components(separatedBy: .init(charactersIn: "/\\?%*|\"<>:"))
                .joined(separator: "_")
            let fileName = "\(safeTitle.isEmpty ? "Workout" : safeTitle).paceplate"
            let fileURL = tempDir.appendingPathComponent(fileName)
            
            try data.write(to: fileURL, options: .atomic)
            return fileURL
        } catch {
            print("Error exporting workout: \(error)")
            return nil
        }
    }
    
    /// Parses a workout from a file URL
    func parseWorkoutFile(url: URL) -> SharedWorkoutSession? {
        // Start accessing security scoped resource if needed
        let isAccessing = url.startAccessingSecurityScopedResource()
        defer {
            if isAccessing {
                url.stopAccessingSecurityScopedResource()
            }
        }
        
        do {
            let data = try Data(contentsOf: url)
            let decoder = JSONDecoder()
            return try decoder.decode(SharedWorkoutSession.self, from: data)
        } catch {
            print("Error parsing workout file: \(error)")
            return nil
        }
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
    
    /// Parses a share URL and returns the SharedWorkoutSession
    func parseShareURL(_ url: URL) -> SharedWorkoutSession? {
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
        
        guard let data = Data(base64Encoded: dataString) else {
            return nil
        }
        
        do {
            let sharedSession = try JSONDecoder().decode(SharedWorkoutSession.self, from: data)
            return sharedSession
        } catch {
            print("Failed to decode workout session: \(error)")
            return nil
        }
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
