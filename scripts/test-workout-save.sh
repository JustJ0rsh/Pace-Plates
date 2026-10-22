#!/bin/bash
set -euo pipefail
root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
output="$(mktemp -d "${TMPDIR:-/tmp}/workout-save.XXXXXX")"
trap 'rm -rf "$output"' EXIT
swiftc -module-cache-path "$output/module-cache" "$root/WorkingOut/Services/WorkoutSaveBoundary.swift" "$root/scripts/workout_save_tests.swift" -o "$output/tests"
"$output/tests"
