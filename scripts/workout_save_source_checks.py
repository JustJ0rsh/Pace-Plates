"""Check production UI wiring alongside the executable save-boundary tests."""
from pathlib import Path

root = Path(__file__).resolve().parent.parent
legacy = (root / "WorkingOut/Features/Workouts/WorkoutSessionDetailView.swift").read_text()
coach = (root / "WorkingOut/Features/Coach/Execution/CoachStrengthExecutionView.swift").read_text().split("private struct SetEditorRequest", 1)[0]
set_editor = (root / "WorkingOut/Features/Workouts/EditExerciseLogView.swift").read_text()
content = (root / "WorkingOut/App/ContentView.swift").read_text()

assert legacy.count('Button("Finish")') == 1
assert coach.count('Button("Finish")') == 1
assert 'Button("Finish Workout"' not in coach
assert 'Button("Done")' not in coach
assert 'saveAndClose(.done)' not in legacy
assert legacy.count('Button("Done")') == 1  # The separate workout date picker.
assert 'Button("Done") { showingDatePicker = false }' in legacy
assert 'Button("Done") { saveAndDismiss() }' in set_editor
assert 'Button("Done") { showWorkoutRecoveries = false }' in content
assert 'if session.executionStatusRaw == "in_progress" {\n                        Button("Finish")' not in legacy
assert 'saveAndClose(.finish)' in legacy
assert 'if persistDetailChangesBeforeDismiss(.dismissal)' in legacy
assert 'if saveBeforeClosing(.finish) { dismiss() }' in coach
assert 'if didLoad { _ = saveBeforeClosing(.dismissal) }' in coach
assert '.confirmationDialog(' not in legacy
assert '.confirmationDialog(' not in coach
print("PASS: 15 workout save UI integration checks")
