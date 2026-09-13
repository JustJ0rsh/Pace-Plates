# Coach contract and daily-value validation

Run from the repository root with the installed Xcode Swift toolchain:

```sh
swiftc WorkingOut/Features/Coach/Domain/CoachProgramDocument.swift WorkingOut/Features/Coach/Domain/CoachPlanValidator.swift WorkingOut/Features/Coach/Domain/CoachSchedule.swift scripts/coach_contract_test_main.swift -o /tmp/coach_contract_checks
/tmp/coach_contract_checks
python3 scripts/coach_entry_value_checks.py
```

The contract suite runs 77 assertions against the bundled schema and example, including typed round trips, canonical fingerprints checked against CryptoKit, deterministic occurrence identities, a 26-week expansion, spring/fall daylight saving transitions, chosen civil-day preservation across date-line time zones, skipped civil-day rejection, exact JSON paths for invalid input, duplicate keys and IDs, unknown fields and versions, numeric bounds, underflow, resource limits, and corrupt interval expansion inputs. It never reads personal tracking data or writes application stores.

The daily-value harness extracts the current `CoachEntryNumber` and `CoachMeasurementUnits` declarations from the app source, then compiles and runs them in a disposable temporary directory. It does not maintain a parallel implementation. Its 14 numeric checks cover unknown versus zero, decimal comma, scientific notation, invalid/negative/nonfinite/underflow input, and exact edit round trips. Its eight unit checks cover supported conversions, legacy unit names, unknown-unit exclusion, and nonfinite observations.

These are executable domain checks. They do not establish SwiftUI journey acceptance, Health permissions/source behavior, or device photo and background execution behavior; record those observations separately.

## Central integration result

Final Debug and unsigned generic-iOS Release builds passed. The iPhone 17e / iOS 26.5 on-disk Coach regression fixture and full import-to-completed-workout journey passed, along with nutrition/recovery save/reopen, AI history navigation, and interrupted-run paused recovery. See [implementation-status.md](implementation-status.md) for artifact paths and the remaining physical-device acceptance boundaries.
