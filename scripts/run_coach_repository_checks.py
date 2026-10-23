#!/usr/bin/env python3
"""Exercise actual Coach repository guards using disposable macOS SwiftData stores."""
import argparse
import hashlib
import json
import os
from pathlib import Path
import re
import shutil
import subprocess
import tempfile

ROOT = Path(__file__).resolve().parents[1]
parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument('--output', type=Path)
args = parser.parse_args()
out = (args.output or Path(tempfile.mkdtemp(prefix='pace-repository-evidence-'))).resolve()
out.mkdir(parents=True, exist_ok=True)
schema = ROOT / 'WorkingOut/Resources/Coach/coach-plan-v1.schema.json'
shutil.copy2(schema, out / schema.name)
models = sorted(p for p in (ROOT / 'WorkingOut/Models').glob('*.swift') if '@Model' in p.read_text())
sources = models + [ROOT / p for p in [
    'WorkingOut/Data/CoachPersistence.swift',
    'WorkingOut/Models/ScheduledRunTarget.swift',
    'WorkingOut/Features/Coach/Execution/CoachExecutionState.swift',
    'WorkingOut/Features/Coach/Domain/CoachProgramDocument.swift',
    'WorkingOut/Features/Coach/Domain/CoachPlanValidator.swift',
    'WorkingOut/Features/Coach/Domain/CoachSchedule.swift',
    'WorkingOut/Features/Coach/Data/CoachRepository.swift',
    'WorkingOut/Features/Coach/Data/CoachRepository+Schedule.swift',
    'scripts/coach_repository_test_main.swift']]
compiled = []
for source in sources:
    if source.name in {'CoachRepository.swift', 'CoachRepository+Schedule.swift'}:
        # Notification delivery is unrelated to these persistence guards. Only
        # replace its module import; every repository declaration/body is exact.
        text = source.read_text()
        assert text.count('import UserNotifications') == 1
        copy = out / source.name
        copy.write_text(text.replace('import UserNotifications', '// Inert notification adapter in host fixture.'))
        compiled.append(str(copy))
    else:
        compiled.append(str(source))
env = dict(os.environ, DEVELOPER_DIR='/Applications/Xcode.app/Contents/Developer')
command = ['xcrun', 'swiftc', '-swift-version', '5', '-D', 'DEBUG', '-module-cache-path',
           str(out / 'module-cache'), *compiled, '-o', str(out / 'repository-checks')]
with (out / 'compile.log').open('w') as log:
    subprocess.run(command, env=env, stdout=log, stderr=subprocess.STDOUT, check=True)
result = subprocess.run([str(out / 'repository-checks')], env=env, capture_output=True, text=True)
(out / 'checks.log').write_text(result.stdout + result.stderr)
result.check_returncode()
match = re.search(r'Coach repository: (\d+) checks passed', result.stdout)
assert match, result.stdout
report = {'result': 'passed', 'checks': int(match.group(1)),
          'scope': 'Actual production repository/domain/model code; disposable macOS SwiftData stores',
          'adapters': ['inert notification delivery', 'inert storage-generation gate'],
          'source_sha256': {str(p.relative_to(ROOT)): hashlib.sha256(p.read_bytes()).hexdigest() for p in sources + [schema]},
          'device_access': False, 'simulators': 0, 'real_records': False}
(out / 'report.json').write_text(json.dumps(report, indent=2) + '\n')
print(json.dumps({k: v for k, v in report.items() if k != 'source_sha256'}, indent=2))
