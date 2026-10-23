"""Fast, path-free fixtures and source-contract checks. No Apple services used."""
import json
from pathlib import Path
import unittest

from candidate import (
    BUCKETS, COACH_FIELDS, REQUIRED_BUCKETS, Destination,
    InertRestoreAdapter, Rejected, Token, authorize,
    decode_synthetic_json, verify_source_contract,
)

ROOT = Path(__file__).resolve().parents[2]
BACKUP_SOURCE = (ROOT / "WorkingOut/Services/DataBackupService.swift").read_text()
COACH_SOURCE = (ROOT / "WorkingOut/Features/Coach/Data/CoachBackupGraph.swift").read_text()


def fixture(version=5, coach=False):
    value = {"exportedAt": 0, **{name: [] for name in REQUIRED_BUCKETS}}
    if version is not None:
        value["formatVersion"] = version
    if coach:
        value["coach"] = {name: [] for name in COACH_FIELDS}
    return value


def example(bucket):
    # Representative fields from the real DTOs, intentionally opaque to policy.
    value = {"id": "00000000-0000-0000-0000-000000000001"}
    values = {
        "exerciseDefinitions": {"name": "Synthetic custom exercise", "muscleGroup": "legs", "isUserDefined": True},
        "workoutSessions": {"date": 0, "notes": "Synthetic", "healthWorkoutUUID": "fake-health-id", "healthAvgHeartRate": 140},
        "exerciseLogs": {"reps": 3, "weight": 20, "weightUnit": "kg", "setNumber": 1, "isCompleted": False},
        "runningSessions": {"date": 0, "distance": 500, "distanceUnit": "m", "duration": 180, "locations": "W10=", "activityType": "running", "avgHeartRate": 140},
        "weightEntries": {"date": 0, "weight": 70, "weightUnit": "kg", "provenance": "manual_or_legacy", "sourceHealthSampleID": None},
        "runningPlans": {"name": "Synthetic plan", "profileSnapshotJSON": '{"goal":"synthetic"}', "aiPrompt": "Synthetic personal prompt"},
        "runningPlanSessions": {"weekIndex": 1, "dayIndex": 2, "notes": "Synthetic notes"},
        "aiConversations": {"date": 0, "mode": "synthetic", "goal": "test", "prompt": "Synthetic", "response": "Synthetic", "model": "inert"},
        "workoutTemplates": {"title": "Synthetic personal template", "isBuiltIn": False, "notes": "Synthetic"},
        "templateExercises": {"name": "Synthetic", "sets": 2, "reps": 3, "suggestedWeight": 20, "notes": "Synthetic"},
        "healthWorkoutInboxItems": {"healthWorkoutUUID": "fake-health-strength", "startDate": 0, "endDate": 10, "activityType": "strength", "duration": 10, "statusRaw": "pending", "createdAt": 0},
        "cardioWorkoutInboxItems": {"healthWorkoutUUID": "fake-health-run", "startDate": 0, "endDate": 10, "activityType": "running", "distanceMeters": 20, "duration": 10, "statusRaw": "pending", "createdAt": 0},
    }
    return {**value, **values.get(bucket, {"syntheticOpaqueValue": "preserve exactly"})}


class CandidateTests(unittest.TestCase):
    def test_source_contract_matches_current_real_dto_buckets_and_guard_sites(self):
        verify_source_contract(BACKUP_SOURCE, COACH_SOURCE)

    def test_source_contract_rejects_new_backup_field_coach_field_or_moved_guard(self):
        guard_line = "            try requireLocalRestoreDestination(context, generation: generation)"
        install_line = "            try await Task.detached(priority: .userInitiated) { try prepared.installAssets() }.value"
        moved_guard = BACKUP_SOURCE.replace(guard_line + "\n", "", 1).replace(install_line, install_line + "\n" + guard_line, 1)
        cases = [
            (BACKUP_SOURCE.replace("var formatVersion:", "var futureRecords: [String] = []\n    var formatVersion:"), COACH_SOURCE),
            (BACKUP_SOURCE.replace("var formatVersion:", "var inferredField = 42\n    var formatVersion:"), COACH_SOURCE),
            (BACKUP_SOURCE, COACH_SOURCE.replace("var trainingPlans:", "var futureRecords: [String] = []\n    var trainingPlans:")),
            (BACKUP_SOURCE.replace("guard CoachPersistence.isLocal(context)", "guard true"), COACH_SOURCE),
            (moved_guard, COACH_SOURCE),
        ]
        for backup, coach in cases:
            with self.subTest(change=backup != BACKUP_SOURCE), self.assertRaises(Rejected):
                verify_source_contract(backup, coach)

    def test_absent_null_and_empty_coach_require_local_for_versions_1_to_5(self):
        for version in (None, 1, 2, 3, 4, 5):
            for coach in ("absent", "null", "empty"):
                value = fixture(version, coach == "empty")
                if coach == "null":
                    value["coach"] = None
                value["weightEntries"] = [example("weightEntries")]
                with self.subTest(version=version, coach=coach), self.assertRaises(Rejected):
                    authorize(value, Destination(local=False), Token())

    def test_every_actual_legacy_bucket_requires_local_and_preserves_content(self):
        for version in range(1, 6):
            for bucket in BUCKETS:
                value = fixture(version)
                value[bucket] = [example(bucket)]
                adapter = InertRestoreAdapter()
                raw = json.dumps(value)
                with self.subTest(version=version, bucket=bucket):
                    with self.assertRaises(Rejected):
                        adapter.apply("synthetic", raw, Destination(local=False))
                    self.assertEqual([], adapter.commits)
                    self.assertEqual(0, adapter.asset_installs)
                    self.assertTrue(adapter.apply("synthetic", raw))
                    self.assertEqual(value, adapter.commits[0])

    def test_every_actual_coach_bucket_requires_local_before_modeled_side_effects(self):
        for bucket in COACH_FIELDS:
            value = fixture(coach=True)
            value["coach"][bucket] = [example(bucket)]
            adapter = InertRestoreAdapter()
            raw = json.dumps(value)
            with self.subTest(bucket=bucket), self.assertRaises(Rejected):
                adapter.apply("synthetic", raw, Destination(local=False))
            self.assertEqual([], adapter.commits)
            self.assertEqual(0, adapter.asset_installs)
            self.assertTrue(adapter.apply("synthetic", raw))
            self.assertEqual(value, adapter.commits[0])

    def test_empty_and_catalog_only_payloads_have_no_cloud_exception(self):
        for value in (fixture(), {**fixture(), "exerciseDefinitions": [example("exerciseDefinitions")]}):
            for destination in (Destination(local=False), Destination(selected=False), Destination(verified=False), Destination(retired=True)):
                with self.subTest(destination=destination), self.assertRaises(Rejected):
                    authorize(value, destination, Token())

    def test_stale_store_and_generation_tokens_do_not_commit_or_install_assets(self):
        value = fixture(coach=True)
        value["coach"]["photos"] = [example("photos")]
        for token in (Token(generation=0), Token(store_id="retired-store")):
            adapter = InertRestoreAdapter()
            with self.subTest(token=token), self.assertRaises(Rejected):
                adapter.apply("synthetic", json.dumps(value), token=token)
            self.assertEqual([], adapter.commits)
            self.assertEqual(0, adapter.asset_installs)

    def test_exact_replay_is_noop_and_conflicting_replay_preserves_first_commit(self):
        value = fixture(coach=True)
        value["coach"]["photos"] = [example("photos")]
        adapter = InertRestoreAdapter()
        self.assertTrue(adapter.apply("synthetic", json.dumps(value)))
        self.assertFalse(adapter.apply("synthetic", json.dumps(value, sort_keys=True)))
        changed = json.loads(json.dumps(value))
        changed["weightEntries"] = [example("weightEntries")]
        with self.assertRaises(Rejected):
            adapter.apply("synthetic", json.dumps(changed))
        self.assertEqual([value], adapter.commits)
        self.assertEqual(1, adapter.asset_installs)

    def test_unknown_future_or_malformed_top_level_payload_fails_without_commit(self):
        cases = []
        for version in (0, 6, -1, True, "5", 1.5):
            cases.append({**fixture(), "formatVersion": version})
        cases.extend([[], {**fixture(), "newUnknownBucket": []}, {**fixture(), "weightEntries": {}},
                      {**fixture(), "weightEntries": ["not-a-record"]},
                      {**fixture(), "exportedAt": "not-numeric"},
                      {**fixture(), "coach": {"future": []}},
                      {key: value for key, value in fixture().items() if key != "exerciseLogs"}])
        for value in cases:
            adapter = InertRestoreAdapter()
            with self.subTest(value=value), self.assertRaises(Rejected):
                adapter.apply("synthetic", json.dumps(value))
            self.assertEqual([], adapter.commits)
            self.assertEqual(0, adapter.asset_installs)

    def test_duplicate_json_keys_nonfinite_numbers_and_invalid_json_are_rejected(self):
        for raw in ('{"formatVersion":1,"formatVersion":5}', '{"exportedAt":NaN}', '{"exportedAt":1e999}', '{', 'null'):
            with self.subTest(raw=raw), self.assertRaises(Rejected):
                decode_synthetic_json(raw)

    def test_optional_buckets_may_be_absent_or_null_and_nil_version_is_legacy(self):
        value = fixture(None)
        for key in BUCKETS:
            if key not in REQUIRED_BUCKETS:
                value[key] = None
        value["formatVersion"] = None
        self.assertEqual(value, decode_synthetic_json(json.dumps(value)))


if __name__ == "__main__":
    unittest.main(verbosity=2)
