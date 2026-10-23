"""Proposed restore boundary, used only by an inert synthetic acceptance adapter.

This module is not imported by the application. It opens no stores and accepts no
file paths. Its local-only rule mirrors the separately implemented app boundary.
It does not replace Swift Codable, archive validation, or SwiftData merge logic.
"""
from copy import deepcopy
from dataclasses import dataclass
import hashlib
import json
import math
import re


BACKUP_FIELDS = {
    "formatVersion": "Int?", "coach": "CoachBackupGraph?", "exportedAt": "Date",
    "exerciseDefinitions": "[ExerciseDefinitionDTO]",
    "workoutSessions": "[WorkoutSessionDTO]", "exerciseLogs": "[ExerciseLogDTO]",
    "runningSessions": "[RunningSessionDTO]", "weightEntries": "[WeightEntryDTO]",
    "runningPlans": "[RunningPlanDTO]?", "runningPlanSessions": "[RunningPlanSessionDTO]?",
    "aiConversations": "[AIConversationDTO]?", "workoutTemplates": "[WorkoutTemplateDTO]?",
    "templateExercises": "[TemplateExerciseDTO]?",
    "healthWorkoutInboxItems": "[HealthWorkoutInboxItemDTO]?",
    "cardioWorkoutInboxItems": "[CardioWorkoutInboxItemDTO]?",
}
BUCKETS = tuple(k for k, v in BACKUP_FIELDS.items() if v.startswith("["))
REQUIRED_BUCKETS = tuple(k for k in BUCKETS if not BACKUP_FIELDS[k].endswith("?"))
COACH_FIELDS = {
    "trainingPlans": "[TrainingPlanSnapshot]", "plannedSessions": "[PlannedSessionSnapshot]",
    "revisions": "[CoachPlanRevisionSnapshot]", "executions": "[CoachSessionExecutionSnapshot]",
    "suggestions": "[CoachProgressionSuggestionSnapshot]", "targets": "[CoachNutritionTargetPeriodSnapshot]",
    "nutrition": "[CoachNutritionLogSnapshot]", "recovery": "[CoachRecoveryCheckInSnapshot]",
    "waist": "[CoachWaistMeasurementSnapshot]", "photos": "[CoachProgressPhotoSnapshot]",
    "phaseReviews": "[CoachPhaseReviewSnapshot]", "calendarMappings": "[CoachCalendarMappingSnapshot]",
}


class Rejected(ValueError):
    pass


def stored_fields(source, declaration):
    """Narrow source contract, not a Swift parser. Unknown syntax requires review."""
    start = source.index(declaration)
    text = source[start:]
    depth = 0
    fields = {}
    for line in text.splitlines():
        clean = re.sub(r'"(?:\\.|[^"\\])*"', '""', line.split("//", 1)[0])
        if depth == 1:
            match = re.match(r"\s*(?:var|let)\s+(\w+)\s*(?::\s*([^={]+))?\s*(?:=|$)", clean)
            if match:
                name, type_name = match.groups()
                fields[name] = type_name.strip() if type_name else "<inferred>"
        depth += clean.count("{") - clean.count("}")
        if depth == 0 and "}" in clean:
            return fields
    raise Rejected("Unrecognized or incomplete Swift declaration")


def verify_source_contract(backup_source, coach_source):
    if stored_fields(backup_source, "struct BackupFile:") != BACKUP_FIELDS:
        raise Rejected("BackupFile shape changed; review candidate and fixtures")
    if stored_fields(coach_source, "struct CoachBackupGraph:") != COACH_FIELDS:
        raise Rejected("CoachBackupGraph shape changed; review candidate and fixtures")
    guard = "try requireLocalRestoreDestination(context, generation: generation)"
    if "file.coach?.hasPersonalRecords == true && !CoachPersistence.isLocal(context)" in backup_source:
        raise Rejected("Conditional legacy restore boundary reintroduced")
    prepared = backup_source[backup_source.index("private static func restorePrepared("):]
    prepared = prepared[:prepared.index("/// Restores stable snapshots")]
    if prepared.count(guard) != 2 or prepared.index(guard) > prepared.index("try prepared.installAssets()"):
        raise Rejected("Prepared restore guard moved after asset mutation")
    if prepared.rindex(guard) < prepared.index("try prepared.installAssets()"):
        raise Rejected("Prepared restore missing post-suspension guard")
    direct = backup_source[backup_source.index("static func restore(_ file:"):]
    direct = direct[:direct.index("/// Every backup may contain personal history")]
    if direct.index(guard) > direct.index("let existingDefs = try context.fetch"):
        raise Rejected("Direct restore guard moved after model access")
    if direct.count(guard) != 2 or direct.rindex(guard) > direct.index("try context.save()"):
        raise Rejected("Direct restore missing final commit guard")
    helper = backup_source[backup_source.index("static func requireLocalRestoreDestination("):]
    if ("guard CoachPersistence.isLocal(context)" not in helper
            or "isCurrentLocalDataPurgeGeneration(generation, context: context), !Task.isCancelled" not in helper):
        raise Rejected("Restore helper no longer enforces local/current destination")


def decode_synthetic_json(raw):
    def unique_object(pairs):
        result = {}
        for key, value in pairs:
            if key in result:
                raise Rejected("Duplicate JSON key")
            result[key] = value
        return result

    def invalid_constant(_):
        raise Rejected("Non-finite JSON number")

    def finite_float(raw):
        value = float(raw)
        if not math.isfinite(value):
            raise Rejected("Non-finite JSON number")
        return value

    try:
        value = json.loads(raw, object_pairs_hook=unique_object,
                           parse_constant=invalid_constant, parse_float=finite_float)
    except (ValueError, TypeError) as error:
        raise Rejected("Malformed synthetic JSON") from error
    validate_shape(value)
    return value


def validate_shape(payload):
    if not isinstance(payload, dict) or set(payload) - set(BACKUP_FIELDS):
        raise Rejected("Unknown backup shape")
    version = payload.get("formatVersion")
    if version is None:
        version = 1
    if type(version) is not int or version not in range(1, 6):
        raise Rejected("Unsupported backup version")
    if type(payload.get("exportedAt")) not in (int, float):
        raise Rejected("Synthetic Date must use the default Codable numeric form")
    for key in REQUIRED_BUCKETS:
        if key not in payload:
            raise Rejected("Missing required backup bucket")
    for key in BUCKETS:
        if payload.get(key) is None and key not in REQUIRED_BUCKETS:
            continue
        if not isinstance(payload.get(key), list) or any(not isinstance(row, dict) for row in payload[key]):
            raise Rejected("Malformed backup bucket")
    coach = payload.get("coach")
    if coach is not None:
        if not isinstance(coach, dict) or set(coach) != set(COACH_FIELDS):
            raise Rejected("Unknown or incomplete Coach graph shape")
        if any(not isinstance(rows, list) or any(not isinstance(row, dict) for row in rows)
               for rows in coach.values()):
            raise Rejected("Malformed Coach graph bucket")


@dataclass(frozen=True)
class Destination:
    store_id: str = "synthetic-local"
    generation: int = 1
    local: bool = True
    selected: bool = True
    verified: bool = True
    retired: bool = False


@dataclass(frozen=True)
class Token:
    store_id: str = "synthetic-local"
    generation: int = 1


def authorize(payload, destination, token):
    validate_shape(payload)
    if (not destination.local or not destination.selected or not destination.verified
            or destination.retired or token.store_id != destination.store_id
            or token.generation != destination.generation):
        raise Rejected("Restore requires the current verified selected local destination")


class InertRestoreAdapter:
    """One in-memory commit; no filesystem, archive, database, or service effects."""
    def __init__(self):
        self._operations = {}
        self.commits = []
        self.asset_installs = 0

    def apply(self, operation_id, raw_json, destination=Destination(), token=Token()):
        payload = decode_synthetic_json(raw_json)
        authorize(payload, destination, token)
        if not isinstance(operation_id, str) or not operation_id:
            raise Rejected("Missing operation identity")
        fingerprint = hashlib.sha256(json.dumps(payload, sort_keys=True, allow_nan=False).encode()).hexdigest()
        key = (destination.store_id, destination.generation, operation_id)
        if key in self._operations:
            if self._operations[key] != fingerprint:
                raise Rejected("Conflicting operation replay")
            return False
        # A modeled atomic commit, not a proof of database/filesystem durability.
        snapshot = deepcopy(payload)
        self.commits.append(snapshot)
        self.asset_installs += len((payload.get("coach") or {}).get("photos", []))
        self._operations[key] = fingerprint
        return True
