"""Synthetic-only protocol experiment, deliberately outside every app target.

This is NOT a SwiftData migration implementation. It models the proposed durable
selection/write protocol over a disposable SQLite graph generated from the audit
inventory. No API accepts an existing source store or app-container location.
"""
from __future__ import annotations

import base64
from contextlib import closing, contextmanager
import fcntl
import hashlib
import json
import os
from pathlib import Path
import re
import shutil
import sqlite3
import tempfile
import uuid


class RecoveryRequired(RuntimeError):
    pass


class Conflict(RecoveryRequired):
    pass


class Interrupted(RuntimeError):
    pass


def encoded(value):
    if isinstance(value, bytes):
        return {"blob": base64.b64encode(value).decode("ascii")}
    return value


def digest(value):
    return hashlib.sha256(json.dumps(value, sort_keys=True, separators=(",", ":"),
                                     ensure_ascii=False).encode()).hexdigest()


def quote(identifier):
    if not re.fullmatch(r"[A-Za-z_][A-Za-z0-9_]*", identifier):
        raise RecoveryRequired("Invalid fixture identifier")
    return '"' + identifier + '"'


def flush_directory(path):
    descriptor = os.open(path, os.O_RDONLY)
    try:
        os.fsync(descriptor)
    finally:
        os.close(descriptor)


def atomic_json(path, value):
    """Same-directory replace + fsync; existing metadata is never edited in place."""
    temporary = path.with_name(path.name + "." + uuid.uuid4().hex + ".tmp")
    try:
        with temporary.open("x", encoding="utf-8") as stream:
            os.chmod(temporary, 0o600)
            json.dump(value, stream, sort_keys=True, indent=2)
            stream.write("\n")
            stream.flush()
            os.fsync(stream.fileno())
        os.replace(temporary, path)
        flush_directory(path.parent)
    finally:
        temporary.unlink(missing_ok=True)


def validate_inventory_sources(inventory, source_texts):
    """Fail closed when persisted declarations in checked-in models drift.

    This deliberately narrow line parser rejects declaration rewrites too; a
    future Swift syntax change needs an explicit inventory/parser review.
    """
    for model in inventory["models"]:
        actual = {}
        for line in source_texts[model["source"]].splitlines():
            match = re.match(r"^    (?:@[^\n]+? )?var (\w+)\b", line)
            if match and "{" not in line.split("//")[0].split("=", 1)[0]:
                if match.group(1) in actual:
                    raise RecoveryRequired("Duplicate persisted declaration")
                actual[match.group(1)] = line.strip()
        expected = {field.get("name", field.get("field")): field["declaration"]
                    for field in model["stored_fields"] + model["additional_relationship_declarations"]}
        if actual != expected:
            raise RecoveryRequired("Source inventory drift: " + model["model"])


class SyntheticExperiment:
    """Owns only the fresh TemporaryDirectory it created itself.

    Keep the instance alive to retain its files for crash/restart simulations.
    `restart()` reopens its journal and selection; it never regenerates fixtures.
    """
    VERSION = 1
    INGRESS = {"manual", "health-strength", "health-cardio", "health-weight",
               "plan-generation", "active-run-recovery", "background-callback",
               "backup-v1", "backup-v2", "backup-v3", "backup-v4", "backup-v5"}

    def __init__(self, inventory):
        self.inventory = inventory
        models = inventory["models"]
        if (len(models), sum(len(m["stored_fields"]) for m in models),
            sum(len(m["additional_relationship_declarations"]) for m in models)) != (14, 253, 14):
            raise RecoveryRequired("Inventory changed; review fixture/schema before use")
        self._temporary = tempfile.TemporaryDirectory(prefix="pace-synthetic-remediation-")
        self.root = Path(self._temporary.name).resolve()
        os.chmod(self.root, 0o700)
        self.nonce = uuid.uuid4().hex
        atomic_json(self.root / "SYNTHETIC_ONLY.json", {"nonce": self.nonce, "version": self.VERSION})
        self.source = self.root / "source"
        self.source.mkdir(mode=0o700)
        self._source_writer = self._new_fixture(self.source)
        self.original = self.snapshot(self.source)
        atomic_json(self.root / "selection.json", self._selection("source", 0, 0))

    def close(self):
        self._source_writer.close()
        self._temporary.cleanup()

    def _selection(self, directory, generation, writes):
        return {"version": self.VERSION, "nonce": self.nonce, "directory": directory,
                "generation": generation, "writes": writes}

    def _owned(self, directory, require_store=True):
        marker = json.loads((self.root / "SYNTHETIC_ONLY.json").read_text())
        if marker != {"nonce": self.nonce, "version": self.VERSION}:
            raise RecoveryRequired("Synthetic ownership marker mismatch")
        directory = Path(directory)
        if directory.parent != self.root or directory.is_symlink():
            raise RecoveryRequired("Directory is outside this synthetic run")
        if directory.name != "source" and not re.fullmatch(r"(?:stage|recovery)-[0-9a-f]{32}", directory.name):
            raise RecoveryRequired("Unowned synthetic directory name")
        if require_store:
            store = directory / "fixture.sqlite"
            if not store.is_file() or store.is_symlink():
                raise RecoveryRequired("Selected synthetic store missing or linked")
        return directory

    @contextmanager
    def lock(self):
        self._owned(self.source)
        lock = self.root / "writer.lock"
        with lock.open("a+b") as stream:
            try:
                fcntl.flock(stream.fileno(), fcntl.LOCK_EX | fcntl.LOCK_NB)
            except BlockingIOError as error:
                raise Conflict("Another synthetic writer owns the coordinator") from error
            try:
                yield
            finally:
                fcntl.flock(stream.fileno(), fcntl.LOCK_UN)

    @contextmanager
    def _connect(self, directory, writable=False):
        directory = self._owned(directory)
        connection = sqlite3.connect((directory / "fixture.sqlite").as_uri() +
                                     ("?mode=rw" if writable else "?mode=ro"), uri=True)
        connection.execute("PRAGMA foreign_keys=ON")
        try:
            with connection:
                yield connection
        finally:
            connection.close()

    def _new_fixture(self, directory):
        store = directory / "fixture.sqlite"
        connection = sqlite3.connect(store)
        os.chmod(store, 0o600)
        connection.execute("PRAGMA journal_mode=WAL")
        connection.execute("PRAGMA synchronous=FULL")
        connection.execute("CREATE TABLE _synthetic (nonce TEXT NOT NULL, version INTEGER NOT NULL)")
        connection.execute("INSERT INTO _synthetic VALUES (?, ?)", (self.nonce, self.VERSION))
        connection.execute("CREATE TABLE _operations (id TEXT PRIMARY KEY, payload_digest TEXT NOT NULL)")
        connection.execute("CREATE TABLE _events (id TEXT PRIMARY KEY, payload TEXT NOT NULL)")
        for model in self.inventory["models"]:
            columns = []
            for field in model["stored_fields"]:
                kind = self._kind(field)
                sql_type = {"Data": "BLOB", "Int": "INTEGER", "Bool": "INTEGER",
                            "Double": "REAL", "Date": "REAL", "TimeInterval": "REAL"}.get(kind, "TEXT")
                columns.append(quote(field["name"]) + " " + sql_type +
                               (" PRIMARY KEY" if field["name"] == "id" else ""))
            columns.extend(quote(r["field"]) + " TEXT" for r in model["additional_relationship_declarations"])
            connection.execute("CREATE TABLE " + quote(model["model"]) + " (" + ",".join(columns) + ")")
            for variant in range(3):
                values = [self._value(model["model"], field, variant) for field in model["stored_fields"]]
                for relation in model["additional_relationship_declarations"]:
                    target = re.search(r"var \w+: \[?(\w+)", relation["declaration"]).group(1)
                    target_id = self._id(target, variant)
                    values.append(json.dumps([target_id] if "[" in relation["declaration"] else target_id))
                connection.execute("INSERT INTO " + quote(model["model"]) + " VALUES (" +
                                   ",".join("?" for _ in values) + ")", values)
        connection.commit()
        assets = directory / "assets"
        assets.mkdir(mode=0o700)
        for name, content in {"route.bin": bytes(range(256)) * 4097,
                              "opaque-external.bin": b"synthetic\0external\xff" * 4000}.items():
            (assets / name).write_bytes(content)
            os.chmod(assets / name, 0o600)
        return connection

    @staticmethod
    def _id(model, variant):
        return str(uuid.uuid5(uuid.NAMESPACE_URL, "pace-synthetic:" + model + ":" + str(variant)))

    @staticmethod
    def _kind(field):
        return re.search(r"var \w+: ([^=/{]+)", field["declaration"]).group(1).strip().rstrip("?")

    def _value(self, model, field, variant):
        name = field["name"]
        kind = self._kind(field)
        if name == "id":
            return self._id(model, variant)
        if "?" in field["declaration"].split("=", 1)[0] and variant == 1:
            return None
        if name == "provenance" and variant == 1:
            return "manual_or_legacy"
        if kind == "Data":
            return (model + ":" + name).encode() + b"\x00\xff\x80" + bytes(range(32)) * (variant + 1)
        if kind in {"Int", "Bool"}:
            return (variant % 2) if kind == "Bool" else 17 + variant
        if kind in {"Double", "Date", "TimeInterval"}:
            return 1738574123.125 + variant if kind == "Date" else 42.125 + variant
        if kind == "UUID":
            return self._id(model + ":" + name, variant)
        if kind == "[String]":
            return json.dumps(["synthetic", "café 🏃", "line\n2", str(variant)], ensure_ascii=False)
        return "synthetic:" + model + ":" + name + ":café 🏃\n" + str(variant)

    def _schema_check(self, connection):
        expected = {m["model"]: [f["name"] for f in m["stored_fields"]] +
                    [r["field"] for r in m["additional_relationship_declarations"]]
                    for m in self.inventory["models"]}
        expected.update({"_synthetic": ["nonce", "version"], "_operations": ["id", "payload_digest"],
                         "_events": ["id", "payload"]})
        tables = {r[0] for r in connection.execute("SELECT name FROM sqlite_master WHERE type='table'")}
        if tables != set(expected):
            raise RecoveryRequired("Unknown or missing fixture table")
        for table, columns in expected.items():
            actual = [r[1] for r in connection.execute("PRAGMA table_info(" + quote(table) + ")")]
            if actual != columns:
                raise RecoveryRequired("Unknown or missing fixture field")
        if connection.execute("SELECT nonce, version FROM _synthetic").fetchall() != [(self.nonce, self.VERSION)]:
            raise RecoveryRequired("Store is not part of this synthetic run")

    def snapshot(self, directory):
        directory = self._owned(directory)
        with self._connect(directory) as connection:
            connection.execute("BEGIN")
            self._schema_check(connection)
            schemas = connection.execute("SELECT name, sql FROM sqlite_master WHERE type='table' ORDER BY name").fetchall()
            rows = {name: [[encoded(v) for v in row] for row in connection.execute(
                "SELECT * FROM " + quote(name) + (" ORDER BY id" if name != "_synthetic" else ""))]
                    for name, _ in schemas}
        operations = dict(rows["_operations"])
        try:
            valid_events = {identifier: digest(json.loads(payload)) for identifier, payload in rows["_events"]}
        except (TypeError, ValueError) as error:
            raise RecoveryRequired("Corrupt synthetic event payload") from error
        if operations != valid_events:
            raise RecoveryRequired("Synthetic event and operation ledger disagree")
        assets = {}
        asset_root = directory / "assets"
        if not asset_root.is_dir() or asset_root.is_symlink():
            raise RecoveryRequired("Missing or linked asset directory")
        for item in sorted(asset_root.rglob("*")):
            if item.is_symlink() or not item.is_file():
                raise RecoveryRequired("Unsafe synthetic asset")
            assets[str(item.relative_to(asset_root))] = hashlib.sha256(item.read_bytes()).hexdigest()
        return {"schema": digest(schemas), "rows": digest(rows),
                "graph_rows": digest({name: value for name, value in rows.items()
                                      if name not in {"_events", "_operations"}}), "assets": assets,
                "counts": {name: len(value) for name, value in rows.items()},
                "operations": rows["_operations"]}

    def _read(self, name):
        path = self.root / name
        if path.is_symlink():
            raise RecoveryRequired("Linked protocol metadata")
        try:
            value = json.loads(path.read_text())
            if value["version"] != self.VERSION or value["nonce"] != self.nonce:
                raise ValueError("Wrong version or run")
            return value
        except (OSError, ValueError, KeyError, TypeError) as error:
            raise RecoveryRequired("Missing or invalid " + name) from error

    def selection(self):
        value = self._read("selection.json")
        if set(value) != {"version", "nonce", "directory", "generation", "writes"}:
            raise RecoveryRequired("Unknown selection fields")
        if type(value["generation"]) is not int or type(value["writes"]) is not int or value["generation"] < 0 or value["writes"] < 0:
            raise RecoveryRequired("Invalid selection epoch")
        if not isinstance(value["directory"], str):
            raise RecoveryRequired("Invalid selection directory")
        self._owned(self.root / value["directory"])
        return value

    def _journal(self):
        value = self._read("journal.json")
        if (not isinstance(value.get("directory"), str) or
            not re.fullmatch(r"stage-[0-9a-f]{32}", value["directory"]) or
            type(value.get("generation")) is not int or value["generation"] < 1 or
            value.get("stage") not in {"allocated", "checkpointed", "copied", "verified", "active", "rolled-back"}):
            raise RecoveryRequired("Invalid migration journal")
        if value["stage"] != "allocated" and not isinstance(value.get("checkpoint"), dict):
            raise RecoveryRequired("Missing migration checkpoint")
        return value

    @staticmethod
    def _preserved(snapshot):
        # New synthetic writes append to the event ledger only. The copied
        # legacy graph, schema and external assets must remain byte/value exact.
        try:
            return snapshot["schema"], snapshot["graph_rows"], snapshot["assets"]
        except (KeyError, TypeError) as error:
            raise RecoveryRequired("Missing graph checkpoint") from error

    def _recovery(self):
        value = self._read("recovery.json")
        if (not isinstance(value.get("directory"), str) or
            not re.fullmatch(r"recovery-[0-9a-f]{32}", value["directory"]) or
            not isinstance(value.get("source"), str) or
            not re.fullmatch(r"stage-[0-9a-f]{32}", value["source"]) or
            type(value.get("generation")) is not int or value["generation"] < 2 or
            not isinstance(value.get("checkpoint"), dict)):
            raise RecoveryRequired("Invalid forward recovery journal")
        return value

    def _validated_selection(self):
        """Called while holding the writer lock at every public mutation boundary."""
        selected = self.selection()
        current = self.snapshot(self.root / selected["directory"])
        if selected["directory"] == "source":
            if (self.root / "journal.json").exists():
                journal = self._journal()
                expected_generation = journal["generation"] + (1 if journal["stage"] == "rolled-back" else -1)
                if (selected["generation"] != expected_generation or
                    journal["stage"] == "active"):
                    raise RecoveryRequired("Source selection conflicts with journal")
            elif selected["generation"] != 0:
                raise RecoveryRequired("Source selection lost its journal")
            return selected
        journal = self._journal()
        if journal["stage"] not in {"verified", "active"}:
            raise RecoveryRequired("Selected local store has no verified journal")
        if selected["directory"] == journal["directory"]:
            checkpoint = journal["checkpoint"]
            generation = journal["generation"]
        else:
            recovery = self._recovery()
            if recovery["source"] != journal["directory"] or recovery["directory"] != selected["directory"]:
                raise RecoveryRequired("Unrecognized local selection")
            checkpoint = recovery["checkpoint"]
            generation = recovery["generation"]
        if selected["generation"] != generation:
            raise RecoveryRequired("Journal/selection generation mismatch")
        if self._preserved(current) != self._preserved(checkpoint):
            raise RecoveryRequired("Selected legacy graph or assets changed")
        if selected["writes"] > current["counts"]["_operations"]:
            raise RecoveryRequired("Selected operation ledger lost committed history")
        return selected

    def token(self):
        selected = self.selection()
        return selected["directory"], selected["generation"]

    @staticmethod
    def _interrupt(point, requested):
        if point == requested:
            raise Interrupted("Injected interruption at " + point)

    def _copy(self, source, destination):
        self._owned(source)
        self._owned(destination, require_store=False)
        if (destination / "fixture.sqlite").exists():
            raise RecoveryRequired("Refuse to overwrite an existing copy")
        before = self.snapshot(source)
        with self._connect(source) as original, closing(sqlite3.connect(destination / "fixture.sqlite")) as copied:
            original.backup(copied)
            copied.execute("PRAGMA synchronous=FULL")
        os.chmod(destination / "fixture.sqlite", 0o600)
        shutil.copytree(source / "assets", destination / "assets")
        for item in (destination / "assets").rglob("*"):
            os.chmod(item, 0o600)
            with item.open("rb") as stream:
                os.fsync(stream.fileno())
        flush_directory(destination / "assets")
        flush_directory(destination)
        if self.snapshot(destination) != before or self.snapshot(source) != before:
            raise Conflict("Source changed or copy failed verification")
        return before

    def migrate(self, interrupt=None, hook=None):
        with self.lock():
            selected = self._validated_selection()
            journal_path = self.root / "journal.json"
            if not journal_path.exists():
                if selected["directory"] != "source":
                    raise RecoveryRequired("Local selection has no migration journal")
                directory = "stage-" + uuid.uuid4().hex
                (self.root / directory).mkdir(mode=0o700)
                journal = {"version": self.VERSION, "nonce": self.nonce, "directory": directory,
                           "generation": selected["generation"] + 1, "stage": "allocated"}
                atomic_json(journal_path, journal)
                self._interrupt("allocated", interrupt)
            else:
                journal = self._journal()
            destination = self._owned(self.root / journal["directory"], require_store=False)
            if selected["directory"] == journal["directory"]:
                if selected["generation"] != journal["generation"]:
                    raise RecoveryRequired("Journal/selection generation mismatch")
                self.snapshot(destination)
                journal["stage"] = "active"
                atomic_json(journal_path, journal)
                return selected
            if selected["directory"] != "source" or journal["stage"] == "active":
                raise RecoveryRequired("Ambiguous selection; no source fallback")
            if journal["stage"] == "allocated":
                journal["checkpoint"] = self.snapshot(self.source)
                journal["stage"] = "checkpointed"
                atomic_json(journal_path, journal)
                self._interrupt("checkpointed", interrupt)
            if self.snapshot(self.source) != journal["checkpoint"]:
                raise Conflict("Source changed since checkpoint; retained for review")
            if journal["stage"] == "checkpointed":
                # An interrupted unselected copy is reused only if fully verified.
                if (destination / "fixture.sqlite").exists():
                    if self.snapshot(destination) != journal["checkpoint"]:
                        raise RecoveryRequired("Partial stage requires explicit recovery")
                else:
                    self._copy(self.source, destination)
                self._interrupt("copy-before-journal", interrupt)
                journal["stage"] = "copied"
                atomic_json(journal_path, journal)
                self._interrupt("copied", interrupt)
            if hook:
                hook(self)
            if journal["stage"] == "copied":
                if self.snapshot(destination) != journal["checkpoint"] or self.snapshot(self.source) != journal["checkpoint"]:
                    raise Conflict("Source or destination changed before selection")
                journal["stage"] = "verified"
                atomic_json(journal_path, journal)
                self._interrupt("verified", interrupt)
            if journal["stage"] != "verified":
                raise RecoveryRequired("Unknown migration stage")
            # Recheck on every retry, including a crash after the verified journal.
            if self.snapshot(destination) != journal["checkpoint"] or self.snapshot(self.source) != journal["checkpoint"]:
                raise Conflict("Verified checkpoint is no longer current")
            self._interrupt("selection-before", interrupt)
            selected = self._selection(journal["directory"], journal["generation"], 0)
            atomic_json(self.root / "selection.json", selected)
            self._interrupt("selection-after", interrupt)
            journal["stage"] = "active"
            atomic_json(journal_path, journal)
            self._interrupt("active", interrupt)
            return selected

    def restart(self):
        """Missing markers, broken bindings or changed graph enter recovery."""
        with self.lock():
            return self._validated_selection()

    def write(self, token, operation_id, payload, ingress="manual", fake_cloud=False, interrupt=None):
        """Generic inert ingress boundary; never invokes Health/CloudKit/import code."""
        if ingress not in self.INGRESS:
            raise RecoveryRequired("Unreviewed synthetic ingress")
        with self.lock():
            selected = self._validated_selection()
            if fake_cloud or selected["directory"] == "source":
                raise RecoveryRequired("Personal writes require selected local destination")
            if token != (selected["directory"], selected["generation"]):
                raise Conflict("Retired callback token")
            directory = self.root / selected["directory"]
            payload_text = json.dumps(payload, sort_keys=True, separators=(",", ":"))
            payload_digest = digest(payload)
            with self._connect(directory, writable=True) as connection:
                connection.execute("BEGIN IMMEDIATE")
                prior = connection.execute("SELECT payload_digest FROM _operations WHERE id=?", (operation_id,)).fetchone()
                if prior and prior[0] != payload_digest:
                    raise Conflict("Same operation identity has conflicting content")
                if not prior:
                    connection.execute("INSERT INTO _events VALUES (?, ?)", (operation_id, payload_text))
                    connection.execute("INSERT INTO _operations VALUES (?, ?)", (operation_id, payload_digest))
                connection.commit()
            self._interrupt("model-after-commit", interrupt)
            # Writes count is bookkeeping only; rollback consults the durable ledger.
            with self._connect(directory) as connection:
                selected["writes"] = connection.execute("SELECT COUNT(*) FROM _operations").fetchone()[0]
            atomic_json(self.root / "selection.json", selected)
            atomic_json(self.root / "anchor.json", {"version": self.VERSION, "nonce": self.nonce,
                        "directory": selected["directory"], "generation": selected["generation"], "operation_id": operation_id,
                        "payload_digest": payload_digest})
            return "replayed" if prior else "inserted"

    def rollback_before_writes(self):
        with self.lock():
            selected = self._validated_selection()
            if selected["directory"] == "source":
                return selected
            journal = self._journal()
            if selected["directory"] != journal["directory"]:
                raise RecoveryRequired("A recovered local store is not a rollback candidate")
            if self.snapshot(self.root / selected["directory"]) != journal["checkpoint"]:
                raise RecoveryRequired("Local history changed; forward recovery required")
            if self.snapshot(self.source) != journal["checkpoint"]:
                raise Conflict("Source history changed; automatic rollback refused")
            selected = self._selection("source", selected["generation"] + 1, 0)
            atomic_json(self.root / "selection.json", selected)
            journal["stage"] = "rolled-back"
            atomic_json(self.root / "journal.json", journal)
            return selected

    def forward_recover(self, interrupt=None):
        """Copy the current local history into another local store; retain both."""
        with self.lock():
            selected = self._validated_selection()
            if selected["directory"] == "source":
                raise RecoveryRequired("Forward recovery requires local history")
            path = self.root / "recovery.json"
            if path.exists():
                recovery = self._recovery()
                if selected["directory"] == recovery["directory"]:
                    self.snapshot(self.root / recovery["directory"])
                    return selected
                if selected["directory"] != recovery["source"]:
                    raise RecoveryRequired("Recovery/selection mismatch")
            else:
                recovery = {"version": self.VERSION, "nonce": self.nonce,
                            "source": selected["directory"], "directory": "recovery-" + uuid.uuid4().hex,
                            "generation": selected["generation"] + 1,
                            "checkpoint": self.snapshot(self.root / selected["directory"])}
                (self.root / recovery["directory"]).mkdir(mode=0o700)
                atomic_json(path, recovery)
            source = self.root / recovery["source"]
            destination = self.root / recovery["directory"]
            if self.snapshot(source) != recovery["checkpoint"]:
                raise Conflict("Local history changed during forward recovery")
            if not (destination / "fixture.sqlite").exists():
                self._copy(source, destination)
            if self.snapshot(destination) != recovery["checkpoint"]:
                raise RecoveryRequired("Recovery copy does not match retained local history")
            self._interrupt("recovery-before-selection", interrupt)
            with self._connect(destination) as connection:
                writes = connection.execute("SELECT COUNT(*) FROM _operations").fetchone()[0]
            selected = self._selection(recovery["directory"], recovery["generation"], writes)
            atomic_json(self.root / "selection.json", selected)
            self._interrupt("recovery-after-selection", interrupt)
            return selected
