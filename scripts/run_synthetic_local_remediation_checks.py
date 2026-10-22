#!/usr/bin/env python3
"""Run the isolated protocol model and existing production copier probe.

No source-store path is accepted. --output controls evidence files only. Every
store is created from synthetic values under an automatically allocated temp
root. No simulator, signing identity, network or application container is used.
"""
import argparse
import hashlib
import json
import os
from pathlib import Path
import subprocess
import sys
import tempfile

ROOT = Path(__file__).resolve().parents[1]
parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument("--output", type=Path, help="Directory for logs, hashes and host-test executable")
parser.add_argument("--python-only", action="store_true", help="Run protocol tests without the macOS SwiftData probe")
args = parser.parse_args()
output = args.output or Path(tempfile.mkdtemp(prefix="pace-synthetic-evidence-"))
output.mkdir(parents=True, exist_ok=True)
output = output.resolve()


def run(command, name, env=None):
    result = subprocess.run(command, cwd=ROOT, env=env, text=True, capture_output=True, timeout=180)
    (output / (name + ".log")).write_text(result.stdout + result.stderr)
    print(name + ": " + ("PASS" if result.returncode == 0 else "FAIL"))
    if result.returncode:
        print(result.stdout + result.stderr)
        raise SystemExit(result.returncode)
    return result.stdout + result.stderr


protocol = run([sys.executable, "-W", "error::ResourceWarning",
                "scripts/synthetic_local_remediation/test_prototype.py"], "protocol")
source_files = [ROOT / "Docs/Coach/cloudkit-field-inventory-2026-10-22.json",
                ROOT / "scripts/synthetic_local_remediation/prototype.py",
                ROOT / "scripts/synthetic_local_remediation/test_prototype.py",
                ROOT / "scripts/coach_migration_test_main.swift",
                ROOT / "WorkingOut/Data/CoachLocalOwnership.swift",
                ROOT / "WorkingOut/Data/CoachLocalOwnership+Assets.swift",
                ROOT / "WorkingOut/Data/CoachLocalOwnership+Migration.swift"]
inventory = json.loads(source_files[0].read_text())
source_files.extend(ROOT / item["source"] for item in inventory["models"])
report = {"scope": "synthetic only; protocol model plus optional actual SwiftData copier probe",
          "source_sha256": {str(path.relative_to(ROOT)): hashlib.sha256(path.read_bytes()).hexdigest()
                            for path in source_files},
          "protocol_exit": 0, "swiftdata_copier": "not run (--python-only)",
          "models": 14, "stored_fields": 253, "relationship_declarations": 14,
          "production_defaults_changed": False, "real_stores_opened": False,
          "simulators_used": 0}
if not args.python_only:
    env = dict(os.environ)
    env["DEVELOPER_DIR"] = "/Applications/Xcode.app/Contents/Developer"
    executable = output / "production-copier-tests"
    module_cache = tempfile.mkdtemp(prefix="swift-module-cache-", dir=output)
    run(["xcrun", "swiftc", "-swift-version", "5", "-module-cache-path", module_cache,
         "WorkingOut/Data/CoachLocalOwnership.swift", "WorkingOut/Data/CoachLocalOwnership+Assets.swift",
         "WorkingOut/Data/CoachLocalOwnership+Migration.swift",
         "scripts/coach_migration_test_main.swift", "-o", str(executable)], "swift-build", env)
    result = run([str(executable)], "swift-copy", env)
    if "Coach migration file copy: 9 checks passed" not in result:
        raise SystemExit("Production copier probe did not report its expected checks")
    report["swiftdata_copier"] = "9 checks passed"
    report["developer_dir"] = env["DEVELOPER_DIR"]
(output / "report.json").write_text(json.dumps(report, indent=2) + "\n")
print("Evidence: " + str(output))
