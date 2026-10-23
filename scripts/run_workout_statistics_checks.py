#!/usr/bin/env python3
"""Run the workout statistics projection against real models in disposable stores."""
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
parser.add_argument('--output', type=Path)
args = parser.parse_args()
out = (args.output or Path(tempfile.mkdtemp(prefix='workout-statistics-'))).resolve()
out.mkdir(parents=True, exist_ok=True)
sources = sorted(p for p in (ROOT / 'WorkingOut/Models').glob('*.swift') if '@Model' in p.read_text())
sources += [ROOT / path for path in [
    'WorkingOut/Data/CoachPersistence.swift', 'WorkingOut/Models/ScheduledRunTarget.swift',
    'WorkingOut/Features/Coach/Execution/CoachExecutionState.swift',
    'WorkingOut/Features/Coach/Domain/CoachProgramDocument.swift',
    'WorkingOut/Services/UnitConverter.swift', 'WorkingOut/Services/WorkoutStatistics.swift',
    'WorkingOut/Services/WorkoutStatisticsRegressionChecks.swift',
    'scripts/workout_statistics_checks.swift']]
env = dict(os.environ, DEVELOPER_DIR='/Applications/Xcode.app/Contents/Developer')
command = ['xcrun', 'swiftc', '-swift-version', '5', '-D', 'DEBUG', '-module-cache-path', str(out / 'module-cache'),
           *map(str, sources), '-o', str(out / 'workout-statistics-checks')]
with (out / 'compile.log').open('w') as log:
    subprocess.run(command, env=env, stdout=log, stderr=subprocess.STDOUT, check=True)
result = subprocess.run([str(out / 'workout-statistics-checks')], env=env, capture_output=True, text=True)
(out / 'checks.log').write_text(result.stdout + result.stderr)
result.check_returncode()
count = re.search(r'Workout statistics: (\d+) checks passed', result.stdout)
assert count, result.stdout
report = {'result': 'passed', 'checks': int(count.group(1)),
          'scope': 'Actual WorkoutStatistics, UnitConverter and persistent models; disposable macOS SwiftData stores',
          'source_sha256': {str(p.relative_to(ROOT)): hashlib.sha256(p.read_bytes()).hexdigest() for p in sources},
          'device_access': False, 'simulators': 0, 'real_records': False}
(out / 'report.json').write_text(json.dumps(report, indent=2) + '\n')
print(json.dumps({k: v for k, v in report.items() if k != 'source_sha256'}, indent=2))
