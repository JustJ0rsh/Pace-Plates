#!/bin/bash
set -euo pipefail

repository_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
test_directory="$(mktemp -d "${TMPDIR:-/tmp}/coach-execution.XXXXXX")"
trap 'rm -rf "$test_directory"' EXIT

swiftc \
  "$repository_root/WorkingOut/Features/Coach/Domain/CoachProgramDocument.swift" \
  "$repository_root/WorkingOut/Features/Coach/Execution/CoachExecutionState.swift" \
  "$repository_root/WorkingOut/Features/Coach/Execution/CoachProgressionRules.swift" \
  "$repository_root/WorkingOut/Models/ScheduledRunTarget.swift" \
  "$repository_root/scripts/coach_execution_tests.swift" \
  -o "$test_directory/coach-execution-tests"

"$test_directory/coach-execution-tests"
