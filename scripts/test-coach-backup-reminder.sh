#!/bin/bash
set -euo pipefail

repository_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
test_directory="$(mktemp -d "${TMPDIR:-/tmp}/coach-backup-reminder.XXXXXX")"
trap 'rm -rf "$test_directory"' EXIT

swiftc -parse-as-library \
  "$repository_root/WorkingOut/Services/CoachBackupReminder.swift" \
  "$repository_root/scripts/coach_backup_reminder_test_main.swift" \
  -o "$test_directory/coach-backup-reminder-tests"

"$test_directory/coach-backup-reminder-tests"
