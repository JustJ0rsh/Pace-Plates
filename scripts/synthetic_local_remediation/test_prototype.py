#!/usr/bin/env python3
"""Run deterministic disposable-store tests. Accepts no existing-store path."""
import json
from pathlib import Path
import sqlite3
import subprocess
import sys
import unittest
from unittest import mock

from prototype import Conflict, Interrupted, RecoveryRequired, SyntheticExperiment, atomic_json, validate_inventory_sources

ROOT = Path(__file__).resolve().parents[2]
INVENTORY = json.loads((ROOT / "Docs/Coach/cloudkit-field-inventory-2026-10-22.json").read_text())


SOURCE_TEXTS = {model["source"]: (ROOT / model["source"]).read_text() for model in INVENTORY["models"]}


class ProtocolTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        validate_inventory_sources(INVENTORY, SOURCE_TEXTS)

    def test_actual_model_declaration_drift_requires_inventory_review(self):
        for addition in ("    var futureStoredField: String = \"x\"\n", "    var inferredField = 42\n"):
            sources = dict(SOURCE_TEXTS)
            source = INVENTORY["models"][0]["source"]
            sources[source] += addition
            with self.assertRaises(RecoveryRequired):
                validate_inventory_sources(INVENTORY, sources)

    def setUp(self):
        self.experiment = SyntheticExperiment(INVENTORY)
        self.addCleanup(self.experiment.close)

    def selected_directory(self):
        return self.experiment.root / self.experiment.selection()["directory"]

    def assert_original(self):
        self.assertEqual(self.experiment.original, self.experiment.snapshot(self.experiment.source))

    def test_all_253_fields_14_relationships_and_schema_preserved(self):
        e = self.experiment
        e.migrate()
        fields = relations = 0
        with e._connect(e.source) as original, e._connect(self.selected_directory()) as local:
            for model in INVENTORY["models"]:
                name = model["model"]
                source_rows = original.execute('SELECT * FROM "' + name + '" ORDER BY id').fetchall()
                local_rows = local.execute('SELECT * FROM "' + name + '" ORDER BY id').fetchall()
                self.assertEqual(source_rows, local_rows, name)
                self.assertEqual(3, len(local_rows))
                fields += len(model["stored_fields"])
                for relation in model["additional_relationship_declarations"]:
                    import re
                    target = re.search(r"var \w+: \[?(\w+)", relation["declaration"]).group(1)
                    known_ids = {row[0] for row in local.execute('SELECT id FROM "' + target + '"')}
                    for (raw,) in local.execute('SELECT "' + relation["field"] + '" FROM "' + name + '"'):
                        identifiers = json.loads(raw)
                        if isinstance(identifiers, str):
                            identifiers = [identifiers]
                        self.assertTrue(set(identifiers) <= known_ids)
                    relations += 1
            self.assertEqual((14, 253, 14), (len(INVENTORY["models"]), fields, relations))
            self.assertIsNone(local.execute('SELECT sourceHealthSampleID FROM WeightEntry WHERE id=?',
                                            (e._id("WeightEntry", 1),)).fetchone()[0])
            self.assertEqual("manual_or_legacy", local.execute('SELECT provenance FROM WeightEntry WHERE id=?',
                                            (e._id("WeightEntry", 1),)).fetchone()[0])
        self.assertEqual(e.original, e.snapshot(self.selected_directory()))
        self.assert_original()

    def test_copy_reads_committed_wal_and_preserves_external_bytes(self):
        e = self.experiment
        self.assertTrue((e.source / "fixture.sqlite-wal").stat().st_size > 0)
        e.migrate()
        for source in (e.source / "assets").iterdir():
            self.assertEqual(source.read_bytes(), (self.selected_directory() / "assets" / source.name).read_bytes())
        self.assertEqual(e.original, e.snapshot(self.selected_directory()))

    def test_interrupt_every_durable_boundary_resumes_without_duplicate_copy(self):
        for point in ("allocated", "checkpointed", "copy-before-journal", "copied", "verified",
                      "selection-before", "selection-after", "active"):
            with self.subTest(point=point):
                e = SyntheticExperiment(INVENTORY)
                try:
                    with self.assertRaises(Interrupted):
                        e.migrate(interrupt=point)
                    journal = e._read("journal.json")
                    self.assertEqual("source" if point not in {"selection-after", "active"} else journal["directory"],
                                     e.restart()["directory"])
                    first_directory = journal["directory"]
                    e.migrate()
                    e.migrate()
                    self.assertEqual(first_directory, e.restart()["directory"])
                    self.assertEqual(1, len(list(e.root.glob("stage-*"))))
                    self.assertEqual(e.original, e.snapshot(e.root / first_directory))
                    self.assertEqual(e.original, e.snapshot(e.source))
                finally:
                    e.close()

    def test_changed_source_after_checkpoint_refuses_selection(self):
        e = self.experiment
        with self.assertRaises(Interrupted):
            e.migrate(interrupt="checkpointed")
        e._source_writer.execute("UPDATE WeightEntry SET weight=weight+1")
        e._source_writer.commit()
        changed = e.snapshot(e.source)
        with self.assertRaises(Conflict):
            e.migrate()
        self.assertEqual("source", e.selection()["directory"])
        self.assertEqual(changed, e.snapshot(e.source))

    def test_remote_change_simulation_at_final_verification_refuses_selection(self):
        e = self.experiment
        def remote_change(experiment):
            experiment._source_writer.execute("UPDATE WeightEntry SET weight=weight+2")
            experiment._source_writer.commit()
        with self.assertRaises(Conflict):
            e.migrate(hook=remote_change)
        self.assertEqual("source", e.selection()["directory"])

    def test_changed_source_after_verified_journal_refuses_on_resume(self):
        e = self.experiment
        with self.assertRaises(Interrupted):
            e.migrate(interrupt="verified")
        e._source_writer.execute("UPDATE WeightEntry SET weight=weight+1")
        e._source_writer.commit()
        with self.assertRaises(Conflict):
            e.migrate()
        self.assertEqual("source", e.selection()["directory"])

    def test_corrupt_unselected_stage_never_selected(self):
        e = self.experiment
        with self.assertRaises(Interrupted):
            e.migrate(interrupt="copied")
        stage = e.root / e._read("journal.json")["directory"]
        with e._connect(stage, writable=True) as connection:
            connection.execute("UPDATE WeightEntry SET weight=999")
        with self.assertRaises(Conflict):
            e.migrate()
        self.assertEqual("source", e.selection()["directory"])
        self.assert_original()

    def test_missing_or_corrupt_external_asset_never_selected(self):
        for mode in ("missing", "corrupt"):
            with self.subTest(mode=mode):
                e = SyntheticExperiment(INVENTORY)
                try:
                    with self.assertRaises(Interrupted):
                        e.migrate(interrupt="copied")
                    asset = e.root / e._read("journal.json")["directory"] / "assets/route.bin"
                    if mode == "missing":
                        asset.unlink()
                    else:
                        asset.write_bytes(b"not-the-route")
                    with self.assertRaises(Conflict):
                        e.migrate()
                    self.assertEqual("source", e.selection()["directory"])
                finally:
                    e.close()

    def test_symlink_asset_refused_without_following_outside_root(self):
        e = self.experiment
        (e.source / "assets/link").symlink_to("/not-opened-by-this-test")
        with self.assertRaises(RecoveryRequired):
            e.migrate()
        self.assertEqual("source", e.selection()["directory"])

    def test_unknown_schema_field_and_table_fail_closed(self):
        for sql in ("ALTER TABLE WeightEntry ADD COLUMN future_field TEXT", "CREATE TABLE future_table (id TEXT)"):
            with self.subTest(sql=sql):
                e = SyntheticExperiment(INVENTORY)
                try:
                    e._source_writer.execute(sql)
                    e._source_writer.commit()
                    with self.assertRaises(RecoveryRequired):
                        e.migrate()
                    self.assertEqual("source", e.selection()["directory"])
                finally:
                    e.close()

    def test_missing_selection_does_not_fall_back_to_source(self):
        e = self.experiment
        e.migrate()
        (e.root / "selection.json").unlink()
        with self.assertRaises(RecoveryRequired):
            e.restart()
        with self.assertRaises(RecoveryRequired):
            e.migrate()
        self.assert_original()

    def test_corrupt_marker_or_future_version_requires_recovery(self):
        for content in ('{"broken":', '{"version":9000,"nonce":"irrelevant"}'):
            with self.subTest(content=content):
                path = self.experiment.root / "selection.json"
                saved = path.read_bytes()
                path.write_text(content)
                try:
                    with self.assertRaises(RecoveryRequired):
                        self.experiment.restart()
                finally:
                    path.write_bytes(saved)

    def test_missing_selected_store_does_not_reopen_retained_source(self):
        e = self.experiment
        e.migrate()
        (self.selected_directory() / "fixture.sqlite").rename(self.selected_directory() / "retained-corrupt.sqlite")
        with self.assertRaises(RecoveryRequired):
            e.restart()
        with self.assertRaises(RecoveryRequired):
            e.migrate()
        self.assert_original()

    def test_fake_cloud_and_unselected_source_reject_all_personal_ingress(self):
        e = self.experiment
        for ingress in sorted(e.INGRESS):
            with self.subTest(ingress=ingress):
                with self.assertRaises(RecoveryRequired):
                    e.write(e.token(), ingress, {"synthetic": True}, ingress=ingress)
        e.migrate()
        before = e.snapshot(self.selected_directory())
        for ingress in sorted(e.INGRESS):
            with self.assertRaises(RecoveryRequired):
                e.write(e.token(), ingress, {"synthetic": True}, ingress=ingress, fake_cloud=True)
        self.assertEqual(before, e.snapshot(self.selected_directory()))
        self.assertFalse((e.root / "anchor.json").exists())
        self.assert_original()

    def test_each_modeled_ingress_writes_once_to_selected_local_destination(self):
        e = self.experiment
        e.migrate()
        for ingress in sorted(e.INGRESS):
            self.assertEqual("inserted", e.write(e.token(), ingress, {"synthetic": ingress}, ingress=ingress))
            self.assertEqual("replayed", e.write(e.token(), ingress, {"synthetic": ingress}, ingress=ingress))
        self.assertEqual(len(e.INGRESS), e.snapshot(self.selected_directory())["counts"]["_events"])
        self.assert_original()

    def test_old_callback_cannot_write_or_advance_anchor_after_selection(self):
        e = self.experiment
        old = e.token()
        e.migrate()
        with self.assertRaises(Conflict):
            e.write(old, "suspended-query", {"weight": 1}, ingress="health-weight")
        self.assertFalse((e.root / "anchor.json").exists())
        self.assertEqual(0, e.snapshot(self.selected_directory())["counts"]["_events"])

    def test_model_commit_before_anchor_failure_replays_once(self):
        e = self.experiment
        e.migrate()
        token = e.token()
        with self.assertRaises(Interrupted):
            e.write(token, "sample-1", {"value": 1}, interrupt="model-after-commit")
        self.assertFalse((e.root / "anchor.json").exists())
        self.assertEqual(1, e.snapshot(self.selected_directory())["counts"]["_events"])
        self.assertEqual("replayed", e.write(token, "sample-1", {"value": 1}))
        self.assertEqual(1, e.selection()["writes"])
        self.assertEqual(1, e.snapshot(self.selected_directory())["counts"]["_operations"])
        self.assertEqual("sample-1", e._read("anchor.json")["operation_id"])
        self.assert_original()

    def test_conflicting_same_id_preserves_prior_content_and_anchor(self):
        e = self.experiment
        e.migrate()
        e.write(e.token(), "stable-1", {"value": "old"})
        before = e.snapshot(self.selected_directory())
        anchor = e._read("anchor.json")
        with self.assertRaises(Conflict):
            e.write(e.token(), "stable-1", {"value": "new"})
        self.assertEqual(before, e.snapshot(self.selected_directory()))
        self.assertEqual(anchor, e._read("anchor.json"))

    def test_unknown_provenance_equal_values_with_distinct_ids_stay_distinct(self):
        e = self.experiment
        e.migrate()
        payload = {"weight": 80, "date": "2026-10-22", "sourceHealthSampleID": None,
                   "provenance": "manual_or_legacy"}
        e.write(e.token(), "legacy-id-1", payload)
        e.write(e.token(), "legacy-id-2", payload)
        self.assertEqual(2, e.snapshot(self.selected_directory())["counts"]["_events"])

    def test_prewrite_rollback_preserves_both_stores_and_invalidates_epoch(self):
        e = self.experiment
        e.migrate()
        retained_local = self.selected_directory()
        old = e.token()
        selected = e.rollback_before_writes()
        self.assertEqual("source", selected["directory"])
        self.assertEqual(e.original, e.snapshot(retained_local))
        self.assert_original()
        with self.assertRaises(RecoveryRequired):
            e.write(old, "stale", {})

    def test_postwrite_rollback_refused_even_when_marker_count_was_not_written(self):
        e = self.experiment
        e.migrate()
        with self.assertRaises(Interrupted):
            e.write(e.token(), "committed", {"value": "new-local"}, interrupt="model-after-commit")
        self.assertEqual(0, e.selection()["writes"])
        before = e.selection()
        with self.assertRaises(RecoveryRequired):
            e.rollback_before_writes()
        self.assertEqual(before, e.selection())
        self.assertEqual(1, e.snapshot(self.selected_directory())["counts"]["_events"])

    def test_source_change_prevents_prewrite_rollback(self):
        e = self.experiment
        e.migrate()
        e._source_writer.execute("UPDATE WeightEntry SET weight=1")
        e._source_writer.commit()
        with self.assertRaises(Conflict):
            e.rollback_before_writes()
        self.assertNotEqual("source", e.selection()["directory"])

    def test_forward_recovery_keeps_new_local_history_and_both_originals(self):
        e = self.experiment
        e.migrate()
        e.write(e.token(), "new-local", {"weight": 82})
        old_token = e.token()
        previous = self.selected_directory()
        before = e.snapshot(previous)
        selected = e.forward_recover()
        self.assertTrue(selected["directory"].startswith("recovery-"))
        self.assertEqual(before, e.snapshot(self.selected_directory()))
        self.assertEqual(before, e.snapshot(previous))
        self.assert_original()
        self.assertEqual(selected, e.restart())
        self.assertEqual(selected, e.forward_recover())
        with self.assertRaises(Conflict):
            e.write(old_token, "old-callback", {})
        self.assertEqual("replayed", e.write(e.token(), "new-local", {"weight": 82}))

    def test_forward_recovery_interruptions_do_not_lose_or_duplicate_history(self):
        for point in ("recovery-before-selection", "recovery-after-selection"):
            with self.subTest(point=point):
                e = SyntheticExperiment(INVENTORY)
                try:
                    e.migrate()
                    e.write(e.token(), "local-new", {"synthetic": True})
                    before = e.snapshot(e.root / e.selection()["directory"])
                    with self.assertRaises(Interrupted):
                        e.forward_recover(interrupt=point)
                    e.restart()
                    e.forward_recover()
                    self.assertEqual(before, e.snapshot(e.root / e.selection()["directory"]))
                    self.assertEqual(1, len(list(e.root.glob("recovery-*"))))
                finally:
                    e.close()

    def test_second_process_cannot_acquire_writer_lock(self):
        e = self.experiment
        code = "import fcntl,sys; f=open(sys.argv[1],'a+b'); fcntl.flock(f,fcntl.LOCK_EX|fcntl.LOCK_NB)"
        with e.lock():
            result = subprocess.run([sys.executable, "-c", code, str(e.root / "writer.lock")],
                                    capture_output=True, text=True, timeout=5)
            self.assertNotEqual(0, result.returncode)
            self.assertIn("BlockingIOError", result.stderr)
            with self.assertRaises(Conflict):
                e.migrate()
        with e.lock():
            pass
        self.assert_original()

    def test_copy_io_failure_leaves_source_selected_and_retained(self):
        e = self.experiment
        with mock.patch.object(e, "_copy", side_effect=OSError("injected storage-full")):
            with self.assertRaises(OSError):
                e.migrate()
        self.assertEqual("source", e.selection()["directory"])
        self.assert_original()
        e.migrate()
        self.assertEqual(e.original, e.snapshot(self.selected_directory()))

    def test_marker_io_failure_keeps_old_selection_and_retry_uses_same_stage(self):
        e = self.experiment
        def fail_marker(path, data):
            if path.name == "selection.json":
                raise OSError("injected marker storage-full")
            return atomic_json(path, data)
        with mock.patch("prototype.atomic_json", side_effect=fail_marker):
            with self.assertRaises(OSError):
                e.migrate()
        self.assertEqual("source", e.selection()["directory"])
        stage = e._read("journal.json")["directory"]
        e.migrate()
        self.assertEqual(stage, e.selection()["directory"])
        self.assert_original()

    def test_source_selection_path_traversal_and_metadata_symlink_refused(self):
        e = self.experiment
        marker = e.selection()
        marker["directory"] = "../outside"
        atomic_json(e.root / "selection.json", marker)
        with self.assertRaises(RecoveryRequired):
            e.restart()
        path = e.root / "selection.json"
        path.unlink()
        path.symlink_to(e.root / "SYNTHETIC_ONLY.json")
        with self.assertRaises(RecoveryRequired):
            e.restart()

    def test_tampered_journal_and_generation_fail_closed(self):
        e = self.experiment
        e.migrate()
        original = e._read("journal.json")
        for key, value in (("directory", "source"), ("stage", "unknown"), ("generation", 999)):
            with self.subTest(key=key):
                changed = dict(original)
                changed[key] = value
                atomic_json(e.root / "journal.json", changed)
                with self.assertRaises(RecoveryRequired):
                    e.restart()
        atomic_json(e.root / "journal.json", original)
        self.assert_original()

    def test_missing_or_tampered_active_journal_refuses_write_and_anchor(self):
        for mode in ("missing", "generation", "unverified"):
            with self.subTest(mode=mode):
                e = SyntheticExperiment(INVENTORY)
                try:
                    e.migrate()
                    token = e.token()
                    if mode == "missing":
                        (e.root / "journal.json").unlink()
                    else:
                        journal = e._read("journal.json")
                        journal["generation" if mode == "generation" else "stage"] = 999 if mode == "generation" else "copied"
                        atomic_json(e.root / "journal.json", journal)
                    with self.assertRaises(RecoveryRequired):
                        e.write(token, "must-not-write", {"value": 1})
                    self.assertEqual(0, e.snapshot(e.root / token[0])["counts"]["_events"])
                    self.assertFalse((e.root / "anchor.json").exists())
                finally:
                    e.close()

    def test_unknown_selected_schema_refuses_write_and_anchor(self):
        e = self.experiment
        e.migrate()
        token = e.token()
        with e._connect(self.selected_directory(), writable=True) as connection:
            connection.execute("ALTER TABLE WeightEntry ADD COLUMN future_data TEXT")
        with self.assertRaises(RecoveryRequired):
            e.write(token, "must-not-write", {"value": 1})
        self.assertFalse((e.root / "anchor.json").exists())
        with e._connect(self.selected_directory()) as connection:
            self.assertEqual(0, connection.execute("SELECT COUNT(*) FROM _events").fetchone()[0])

    def test_selected_graph_and_asset_corruption_refused_at_every_entry(self):
        for corruption in ("graph", "asset"):
            with self.subTest(corruption=corruption):
                e = SyntheticExperiment(INVENTORY)
                try:
                    e.migrate()
                    token = e.token()
                    directory = e.root / token[0]
                    if corruption == "graph":
                        with e._connect(directory, writable=True) as connection:
                            connection.execute("UPDATE WeightEntry SET weight=999")
                    else:
                        (directory / "assets/route.bin").write_bytes(b"corrupt")
                    for action in (e.restart, e.migrate, e.forward_recover, e.rollback_before_writes,
                                   lambda: e.write(token, "must-not-write", {})):
                        with self.assertRaises(RecoveryRequired):
                            action()
                    self.assertFalse((e.root / "anchor.json").exists())
                    self.assertEqual(e.original, e.snapshot(e.source))
                finally:
                    e.close()

    def test_corrupt_event_payload_cannot_be_silently_replayed(self):
        e = self.experiment
        e.migrate()
        e.write(e.token(), "stable", {"value": 1})
        anchor = e._read("anchor.json")
        with e._connect(self.selected_directory(), writable=True) as connection:
            connection.execute("UPDATE _events SET payload='{}'")
        with self.assertRaises(RecoveryRequired):
            e.write(e.token(), "stable", {"value": 1})
        self.assertEqual(anchor, e._read("anchor.json"))

    def test_fixture_scope_rejects_nonowned_directory(self):
        with self.assertRaises(RecoveryRequired):
            self.experiment.snapshot(Path("/Users/joshua/Library"))
        self.assert_original()


if __name__ == "__main__":
    unittest.main(verbosity=2)
