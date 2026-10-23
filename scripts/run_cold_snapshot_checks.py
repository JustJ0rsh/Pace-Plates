#!/usr/bin/env python3
"""Compile and exercise the actual cold snapshot helper against temporary files only."""
import argparse
import hashlib
import json
import os
from pathlib import Path
import re
import subprocess
import tempfile

ROOT = Path(__file__).resolve().parents[1]
parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument("--output", type=Path)
parser.add_argument("--module-cache", type=Path)
args = parser.parse_args()
output = (args.output or Path(tempfile.mkdtemp(prefix="pace-cold-evidence-"))).resolve()
output.mkdir(parents=True, exist_ok=True)
cache = (args.module_cache or output / "module-cache").resolve()
sources = [ROOT / "WorkingOut/Data/CoachSQLiteReadSnapshot.swift", ROOT / "scripts/coach_cold_snapshot_test_main.swift"]
env = dict(os.environ)
env["DEVELOPER_DIR"] = "/Applications/Xcode.app/Contents/Developer"
executable = output / "cold-snapshot-checks"

def run(command, name):
    result = subprocess.run(command, cwd=ROOT, env=env, text=True, capture_output=True, timeout=180)
    text = result.stdout + result.stderr
    (output / (name + ".log")).write_text(text)
    if result.returncode:
        print(text)
        raise SystemExit(result.returncode)
    return text

run(["xcrun", "swiftc", "-swift-version", "5", "-D", "DEBUG", "-module-cache-path", str(cache), *map(str, sources), "-o", str(executable)], "compile")
result = run([str(executable)], "checks")
match = re.search(r"Cold SQLite snapshots: (\d+) checks passed", result)
if not match:
    raise SystemExit("Host helper did not produce its expected result")
report = {"scope": "Actual production cold snapshot helper; disposable host SQLite fixtures only",
          "checks": int(match.group(1)), "result": "passed", "simulators": 0, "device_access": False,
          "source_sha256": {str(p.relative_to(ROOT)): hashlib.sha256(p.read_bytes()).hexdigest() for p in sources}}
(output / "report.json").write_text(json.dumps(report, indent=2) + "\n")
print(result.strip())
print("Evidence: " + str(output))
