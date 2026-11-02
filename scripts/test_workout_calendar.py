#!/usr/bin/env python3
"""Run the app's pure Calendar regression checks without Calendar permissions."""
from pathlib import Path
import subprocess
import tempfile

root = Path(__file__).resolve().parent.parent
with tempfile.TemporaryDirectory(prefix="pace-calendar-checks-") as temporary:
    executable = str(Path(temporary) / "checks")
    subprocess.run([
        "swiftc", "-D", "DEBUG",
        str(root / "WorkingOut/Services/WorkoutCalendarPlan.swift"),
        str(root / "WorkingOut/Services/WorkoutCalendarPlanRegressionChecks.swift"),
        str(root / "scripts/workout_calendar_test_main.swift"),
        "-o", executable,
    ], check=True)
    subprocess.run([executable], check=True)
