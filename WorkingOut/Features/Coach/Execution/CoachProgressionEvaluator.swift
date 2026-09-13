import Foundation
import SwiftData
import CryptoKit

@MainActor
enum CoachProgressionEvaluator {
    static func evidence(context: ModelContext, planID: UUID? = nil) throws -> [CoachProgressionEvidence] {
        let occurrences = try context.fetch(FetchDescriptor<PlannedSession>())
        let relevantOccurrences = occurrences.filter { planID == nil || $0.plan?.id == planID }
        let checks = try context.fetch(FetchDescriptor<CoachRecoveryCheckIn>()).sorted { $0.updatedAt > $1.updatedAt }
        let gates = try context.fetch(FetchDescriptor<CoachPhaseReview>())
        let revisions = try context.fetch(FetchDescriptor<CoachPlanRevision>())
        var evidence: [CoachProgressionEvidence] = try context.fetch(FetchDescriptor<CoachSessionExecution>()).compactMap { item in
            guard let occurrence = relevantOccurrences.first(where: { $0.id == item.plannedSessionID }),
                  let data = item.prescriptionData,
                  case let .strength(prescription) = try JSONDecoder().decode(CoachSessionTemplate.self, from: data) else { return nil }
            let snapshot = try CoachExecutionCoordinator.snapshot(item)
            let revision = SHA256.hash(data: item.snapshotData ?? Data()).map { String(format: "%02x", $0) }.joined()
            let endedAt = item.endedAt ?? item.startedAt
            let planZone = occurrence.plan.map(CoachRepository.timeZone) ?? .current
            let check = checks.first { check in
                check.civilDate == CoachSchedule.civilDate(endedAt, timeZone: TimeZone(identifier: check.timeZoneIdentifier) ?? planZone)
            }
            let gate = gates.first { $0.planID == occurrence.plan?.id && $0.phaseID == occurrence.phaseID && $0.revisionID == item.prescriptionRevisionID }
            let document = try revisions.first(where: { $0.id == item.prescriptionRevisionID }).map {
                try JSONDecoder().decode(CoachPlanDocument.self, from: $0.documentData)
            }
            let phase = document?.phases.first { $0.id == occurrence.phaseID }
            let readinessReviewed = phase.map { $0.advanceMode == .scheduled || gate?.statusRaw == "ready" } ?? false
            return CoachProgressionEvidence(executionID: item.id, endedAt: item.endedAt ?? item.startedAt,
                status: item.statusRaw, prescription: prescription, results: snapshot.setResults, revision: revision,
                painScore: check?.painScore, soreness: check?.soreness, readinessReviewed: readinessReviewed,
                recoveryCheckInID: check?.id, phaseReviewID: gate?.id)
        }
        // Unstarted skipped and overdue occurrences have no execution record,
        // but still interrupt a required sequence of completed occurrences.
        for row in relevantOccurrences where row.executionID == nil {
            let zone = row.plan.map(CoachRepository.timeZone) ?? .current
            let today = CoachSchedule.civilDate(Date(), timeZone: zone)
            let day = row.currentCivilDate ?? CoachSchedule.civilDate(row.scheduledDate, timeZone: zone)
            guard row.completionProvenance != "removed_by_reviewed_revision",
                  (["skipped", "completed", "partial"].contains(row.status) && day <= today || row.status == "pending" && day < today),
                  let data = row.prescriptionData,
                  case let .strength(prescription) = try JSONDecoder().decode(CoachSessionTemplate.self, from: data) else { continue }
            evidence.append(.init(executionID: row.id, endedAt: row.completedAt ?? row.scheduledDate,
                status: row.status, prescription: prescription, results: [], revision: "occurrence_without_actuals"))
        }
        return evidence
    }

    static func invalidateChangedEvidence(context: ModelContext) throws {
        let evidence = try evidence(context: context)
        let suggestions = try context.fetch(FetchDescriptor<CoachProgressionSuggestion>()).filter { $0.statusRaw == "pending" }
        var changed = false
        for suggestion in suggestions {
            let ids = try JSONDecoder().decode([UUID].self, from: suggestion.evidenceIDsData)
            let selected = evidence.filter { ids.contains($0.executionID) }
            let currentFingerprint = try CoachProgressionRules.fingerprint(selected)
            if selected.count != ids.count || currentFingerprint != suggestion.evidenceFingerprint {
                suggestion.statusRaw = "stale"; changed = true
            }
        }
        if changed { try context.save() }
    }

    static func generate(plan: TrainingPlan, context: ModelContext) throws -> (suggestions: [CoachProgressionSuggestion], holds: [String]) {
        try CoachRepository(context: context).requireLocal()
        try invalidateChangedEvidence(context: context)
        guard let document = try CoachRepository(context: context).document(for: plan) else { return ([], ["No authored progression rules are available."]) }
        let evidence = try evidence(context: context, planID: plan.id)
        let checks = try context.fetch(FetchDescriptor<CoachRecoveryCheckIn>())
        let hold = checks.contains { CoachProgressionRules.shouldHoldForRecovery(civilDate: $0.civilDate,
            timeZoneIdentifier: $0.timeZoneIdentifier, painScore: $0.painScore, soreness: $0.soreness) }
        var existing = try context.fetch(FetchDescriptor<CoachProgressionSuggestion>()).filter { $0.planID == plan.id }
        var holds: [String] = []
        for rule in document.progressionRules ?? [] {
            switch rule {
            case let .doubleProgression(value):
                switch try CoachProgressionRules.evaluate(rule: value, evidence: evidence, holdForRecovery: hold) {
                case let .hold(reason):
                    holds.append("\(value.title): \(reason)")
                    for suggestion in existing where suggestion.ruleID == value.id && suggestion.statusRaw == "pending" { suggestion.statusRaw = "stale" }
                case let .propose(proposal):
                    for suggestion in existing where suggestion.ruleID == value.id && suggestion.statusRaw == "pending" && suggestion.evidenceFingerprint != proposal.evidenceFingerprint { suggestion.statusRaw = "stale" }
                    if existing.contains(where: { $0.ruleID == value.id && $0.evidenceFingerprint == proposal.evidenceFingerprint }) { continue }
                    let suggestion = CoachProgressionSuggestion()
                    suggestion.planID = plan.id; suggestion.ruleID = value.id; suggestion.exerciseID = value.exerciseId
                    suggestion.sourceTemplateID = value.sessionTemplateId; suggestion.reason = proposal.reason
                    suggestion.evidenceFingerprint = proposal.evidenceFingerprint
                    suggestion.evidenceIDsData = try JSONEncoder().encode(proposal.evidenceIDs)
                    suggestion.proposedPrescriptionData = try JSONEncoder().encode(proposal)
                    context.insert(suggestion); existing.append(suggestion)
                }
            case let .manualReview(value): holds.append("\(value.title): \(value.instructions)")
            }
        }
        try context.save()
        return (existing.sorted { $0.createdAt > $1.createdAt }, holds)
    }

    static func accept(suggestionID: UUID, selectedIDs: Set<UUID>, increment: Double, confirmedPerImplement: Bool, context: ModelContext) throws {
        guard !selectedIDs.isEmpty, increment.isFinite, increment > 0 else { throw CoachExecutionCoordinator.ExecutionError.invalid("Select future sessions and enter a positive available increment.") }
        try CoachRepository(context: context).transaction { isolated in
            try invalidateChangedEvidence(context: isolated)
            guard let suggestion = try isolated.fetch(FetchDescriptor<CoachProgressionSuggestion>()).first(where: { $0.id == suggestionID }), suggestion.statusRaw == "pending",
                  let plan = try isolated.fetch(FetchDescriptor<TrainingPlan>()).first(where: { $0.id == suggestion.planID }),
                  var document = try CoachRepository(context: isolated).document(for: plan) else {
                throw CoachExecutionCoordinator.ExecutionError.invalid("This suggestion is no longer pending. Refresh its evidence before making a change.")
            }
            var proposal = try JSONDecoder().decode(CoachProgressionProposal.self, from: suggestion.proposedPrescriptionData)
            let currentEvidence = try evidence(context: isolated, planID: plan.id)
            guard let currentRule = document.progressionRules?.compactMap({ rule -> CoachDoubleProgressionRule? in
                if case let .doubleProgression(value) = rule, value.id == suggestion.ruleID { return value }; return nil
            }).first,
                  case let .propose(currentProposal) = try CoachProgressionRules.evaluate(rule: currentRule, evidence: currentEvidence, holdForRecovery: false),
                  currentProposal.evidenceFingerprint == proposal.evidenceFingerprint else {
                throw CoachExecutionCoordinator.ExecutionError.invalid("The latest occurrence sequence no longer supports this suggestion. Refresh progression before applying a change.")
            }
            guard proposal.loadBasis != .perImplement || confirmedPerImplement else { throw CoachExecutionCoordinator.ExecutionError.invalid("Confirm that the load is per implement, such as per hand for dumbbells.") }
            let newChecks = try isolated.fetch(FetchDescriptor<CoachRecoveryCheckIn>())
            guard !newChecks.contains(where: { CoachProgressionRules.shouldHoldForRecovery(civilDate: $0.civilDate,
                timeZoneIdentifier: $0.timeZoneIdentifier, painScore: $0.painScore, soreness: $0.soreness) }) else {
                throw CoachExecutionCoordinator.ExecutionError.invalid("Recent pain or soreness needs review before increasing the load.")
            }
            let rows = try isolated.fetch(FetchDescriptor<PlannedSession>()).filter { selectedIDs.contains($0.id) }
            let today = CoachSchedule.civilDate(Date(), timeZone: CoachRepository.timeZone(plan))
            guard rows.count == selectedIDs.count, rows.allSatisfy({ $0.plan?.id == plan.id && $0.status == "pending" && $0.executionID == nil && !$0.localScheduleOverride && $0.sourceTemplateID == proposal.templateID && ($0.currentCivilDate ?? "") >= today }) else {
                throw CoachExecutionCoordinator.ExecutionError.invalid("Only selected unstarted future occurrences of the same workout can change.")
            }
            let oldIncrement = proposal.increment.value
            proposal.newLoads = proposal.newLoads.mapValues { CoachWeight(value: $0.value - oldIncrement + increment, unit: $0.unit) }
            proposal.increment.value = increment
            func applying(_ template: CoachSessionTemplate) throws -> CoachSessionTemplate {
                guard case var .strength(strength) = template,
                      let index = strength.exercises.firstIndex(where: { $0.id == proposal.exerciseID }),
                      strength.exercises[index].exercise.key == proposal.exerciseKey,
                      strength.exercises[index].exercise.equipment.sorted() == proposal.equipment.sorted(),
                      strength.exercises[index].prescriptionBasis == proposal.prescriptionBasis,
                      strength.exercises[index].loadBasis == proposal.loadBasis else {
                    throw CoachExecutionCoordinator.ExecutionError.invalid("The future exercise no longer matches this proposal.")
                }
                let futureSets = strength.exercises[index].sets.filter { $0.role == .working }.sorted { $0.id < $1.id }
                guard let evidenceSets = proposal.workingSetPrescription,
                      futureSets.count == evidenceSets.count,
                      zip(futureSets, evidenceSets.sorted { $0.id < $1.id }).allSatisfy({ $0.id == $1.id && $0.target == $1.target && $0.effort == $1.effort }),
                      Set(futureSets.map(\.id)) == Set(proposal.newLoads.keys) else {
                    throw CoachExecutionCoordinator.ExecutionError.invalid("The future working sets or targets changed. Review new comparable evidence for this prescription.")
                }
                for setIndex in strength.exercises[index].sets.indices {
                    let id = strength.exercises[index].sets[setIndex].id
                    if let load = proposal.newLoads[id] { strength.exercises[index].sets[setIndex].load = load }
                }
                return .strength(strength)
            }
            guard let templateIndex = document.sessionTemplates.firstIndex(where: { $0.id == proposal.templateID }) else { throw CoachRepositoryError.missingRecord }
            document.sessionTemplates[templateIndex] = try applying(document.sessionTemplates[templateIndex])
            document.revision += 1
            let encoder = JSONEncoder(); encoder.outputFormatting = [.sortedKeys]
            let documentData = try encoder.encode(document)
            let validated = try CoachPlanValidator().validate(documentData)
            let revision = CoachPlanRevision()
            revision.planID = plan.id; revision.documentData = documentData; revision.sourceProgramID = document.programId
            revision.sourceRevision = document.revision; revision.provenance = "reviewed_progression"; revision.fingerprint = validated.fingerprint
            if let previous = try isolated.fetch(FetchDescriptor<CoachPlanRevision>()).first(where: { $0.id == plan.currentRevisionID }) {
                revision.exerciseMappingsData = previous.exerciseMappingsData
            }
            isolated.insert(revision)
            for phase in document.phases {
                let review = CoachPhaseReview()
                review.planID = plan.id; review.phaseID = phase.id; review.revisionID = revision.id
                review.statusRaw = phase.advanceMode == .reviewRequired ? "awaiting_review" : "ready"
                isolated.insert(review)
            }
            for row in rows {
                guard let data = row.prescriptionData else { throw CoachRepositoryError.missingRecord }
                row.prescriptionData = try encoder.encode(applying(JSONDecoder().decode(CoachSessionTemplate.self, from: data)))
                row.revisionID = revision.id
            }
            plan.currentRevisionID = revision.id; plan.updatedAt = Date(); plan.sourceRevision = document.revision; plan.fingerprint = validated.fingerprint
            suggestion.statusRaw = increment == oldIncrement ? "accepted" : "edited"
            suggestion.decidedAt = Date(); suggestion.selectedOccurrenceIDsData = try encoder.encode(selectedIDs.sorted { $0.uuidString < $1.uuidString })
            suggestion.proposedPrescriptionData = try encoder.encode(proposal)
        }
    }
}
