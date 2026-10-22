#!/usr/bin/env python3
"""Run actual Community reporting bodies against inert platform doubles on macOS.

This never imports GameKit/UIKit, opens an account, or writes app preferences.
Only unrelated SwiftData streak calculations are omitted; report bodies come
straight from the selected source checkout. Set DEVELOPER_DIR to choose Xcode.
"""
import argparse
import hashlib
import json
import os
from pathlib import Path
import re
import subprocess
import tempfile

parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument("--source-root", type=Path, default=Path(__file__).resolve().parents[1])
parser.add_argument("--output", type=Path)
args = parser.parse_args()
temporary = tempfile.TemporaryDirectory(prefix="pace-community-consent-") if args.output is None else None
output = args.output or Path(temporary.name)
output.mkdir(parents=True, exist_ok=True)
fixture = Path(__file__).parent / "fixtures/community-consent"
source = args.source_root / "WorkingOut/Services"
score = (source / "GameCenterService.swift").read_text()
streak = (source / "StreakService.swift").read_text()
assert score.count("import GameKit") == 1 and score.count("import UIKit") == 1
score = score.replace("import GameKit\n", "").replace("import UIKit\n", "")
start = streak.index("private extension StreakService {")
thresholds = re.findall(r"^    static let (?:daily|weekly)Thresholds:.*$", streak, re.MULTILINE)
assert len(thresholds) == 2
report = "import Foundation\nenum StreakService {\n" + "\n".join(thresholds) + "\n}\n"
report += streak[start:].replace("private extension StreakService {", "extension StreakService {", 1)
assert "import GameKit" not in score + report
assert "import UIKit" not in score + report and "import SwiftData" not in score + report
(output / "GameCenterService.swift").write_text(score)
(output / "StreakReporting.swift").write_text(report)
files = [fixture / "mocks.swift", output / "GameCenterService.swift", output / "StreakReporting.swift"]
consent = source / "CommunityConsent.swift"
if consent.exists():
    files.append(consent)
files.append(fixture / "main.swift")
manifest = {
    "source_root": str(args.source_root),
    "source_sha256": {p.name: hashlib.sha256(p.read_bytes()).hexdigest() for p in [source / "GameCenterService.swift", source / "StreakService.swift"] + ([consent] if consent.exists() else [])},
    "no_live_framework_imports": True,
    "transforms": ["remove GameKit/UIKit imports to bind inert doubles", "extract exact StreakService reporting extension and actual threshold constants; widen private visibility only"],
}
(output / "manifest.json").write_text(json.dumps(manifest, indent=2) + "\n")
sdk = subprocess.check_output(["xcrun", "--sdk", "macosx", "--show-sdk-path"], text=True).strip()
swiftc = subprocess.check_output(["xcrun", "--find", "swiftc"], text=True).strip()
command = [swiftc, "-swift-version", "5", "-sdk", sdk, "-module-cache-path", str(output / "module-cache"), *map(str, files), "-o", str(output / "consent-tests")]
build = subprocess.run(command, capture_output=True, text=True)
(output / "build.log").write_text(build.stdout + build.stderr)
if build.returncode:
    print(build.stdout + build.stderr)
    raise SystemExit(build.returncode)
result = subprocess.run([str(output / "consent-tests")], capture_output=True, text=True, timeout=20)
(output / "run.log").write_text(result.stdout + result.stderr)
print(result.stdout + result.stderr)
raise SystemExit(result.returncode)
