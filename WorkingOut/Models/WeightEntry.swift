import Foundation
import SwiftData

@Model
final class WeightEntry {
    var id: UUID = UUID()
    var sourceHealthSampleID: String? = nil
    var sourceName: String? = nil
    var provenance: String = "manual_or_legacy"
    var date: Date = Date()
    var weight: Double = 0
    var weightUnit: String = "lbs"
    
    init(id: UUID = UUID(), date: Date = Date(), weight: Double, weightUnit: String = "lbs") {
        self.id = id
        self.date = date
        self.weight = weight
        self.weightUnit = weightUnit
    }
} 
