import Foundation
import SwiftData

@Model
final class AIConversation {
    var id: UUID = UUID()
    var date: Date = Date()
    var mode: String = "plan" // "plan" | "ask"
    var goal: String = "maintain"
    var prompt: String = ""
    var response: String = ""
    var model: String = "on-device"
    // If a structured plan was generated, we persist the JSON here so the app can render a data-driven view later
    var structuredPlanJSON: String? = nil

    init(id: UUID = UUID(), date: Date = Date(), mode: String, goal: String, prompt: String, response: String, model: String, structuredPlanJSON: String? = nil) {
        self.id = id
        self.date = date
        self.mode = mode
        self.goal = goal
        self.prompt = prompt
        self.response = response
        self.model = model
        self.structuredPlanJSON = structuredPlanJSON
    }
}
