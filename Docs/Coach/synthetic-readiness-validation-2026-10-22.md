# Synthetic readiness validation — 22 October 2026

This follow-up starts at PR8 `dd254b6f2849a21cf4de3e6e7fa9c6b41721fbf3`, retaining PR8's manual completion and Community fixes without duplicating them. It supplies an isolated storage protocol prototype and simulator-only natural onboarding/Keychain tests. It does not implement a production migration or settle the storage/release policy.

## Implemented and reviewed

The [standalone storage experiment](synthetic-storage-prototype-2026-10-22.md) covers the proposed journal, selection, backup/copy, conflict, replay and recovery protocol. All 253 inventoried field names and 14 relationship declarations appear in generated SQLite fixtures. The actual production SQLite/WAL and external-asset copiers are also exercised independently with a two-model SwiftData probe. These are distinct evidence scopes; neither establishes an all-model production migration.

Natural onboarding tests use the existing isolated `.none` disk store and inert integrations, while bypassing test-mode profile seeding and forced onboarding suppression. An opt-in requires all of Debug, simulator, UI-test mode, `UITEST_NATURAL_PROFILE=1`, and a valid `UITEST_PROFILE_SCOPE` UUID. Security calls use a unique synthetic Keychain service. Release and physical-device builds cannot enable this mode; ordinary UI tests still use an in-memory profile. No Keychain item is deleted.

The new tests verify skipping setup, saving an empty optional profile, and entering a synthetic age/height/goal. Empty completion survives a process relaunch through the normal onboarding decision. The populated case clears the disposable app's defaults and local fixture on relaunch while retaining its scoped Keychain item: the normal profile gate must suppress onboarding and actual Security readback must match the synthetic values. The diagnostic also confirms legacy profile defaults are absent.

Independent review found and corrected prototype paths that initially accepted writes after missing journal, unknown schema, or selected graph changes. Every selected-state mutation now validates the journal/selection binding, schema, immutable fixture graph/assets, and event ledger. Independent review reran all 35 protocol tests and found no remaining blockers. The observed height control required an any-role accessibility query rather than assuming Button.

## Evidence and safe reproduction

- Host runner: `python3 scripts/run_synthetic_local_remediation_checks.py --output /tmp/pace-synthetic-remediation-evidence-20261022` — 35 protocol tests and 9 actual SwiftData copier checks passed. The runner accepts no existing source-store path.
- Simulator: one newly created iPhone 17e / iOS 26.5 named `PaceNaturalProfile-20261022`, reserved under `/tmp/dot-simulator-budget-20261022/README.md`. Explicit destination, parallel testing disabled, maximum concurrent simulator destinations 1. Use a new exclusively leased simulator for future runs; do not reset an existing user's app.
- Xcode scheme `WorkingOut`, Debug, normal local ad hoc simulator signing (`CODE_SIGNING_ALLOWED=YES`, `CODE_SIGN_IDENTITY=-`). No signing account or entitlement source file changes. Select `WorkingOutUITests/NaturalOnboardingUITests`, `WorkingOutUITests/OnboardingAuditUITests`, and `WorkingOutUITests/WorkingOutUITests/testCoachPersistenceAndExecutionRegressions`.

The initial unsigned run passed PR8's two onboarding tests and the 184-assertion existing regression suite, but failed the new Keychain readback and a height-selector assumption. It is retained as failed setup evidence. The linker-only unsigned app had no effective normal app signing metadata; normal Xcode ad hoc simulator signing makes the Keychain test viable without changing production signing configuration. No exact Security failure status was captured in the unsigned run.

Final combined result: **6 tests passed, 0 failed, 0 skipped** (125.3 seconds reported by the test tool). This includes all three natural-profile cases, both unchanged PR8 onboarding cases, and `Coach checks passed: 184`. The result bundle reports two non-failing invalid-frame-dimension runtime warnings during profile/manual-workout interaction; these are not represented as completed visual/layout acceptance.

Retained evidence is in the original checkout under `.tmp/synthetic-readiness-20261022/`: `qa/adhoc-onboarding-and-storage.xcresult`, `qa/summary.json`, `qa/final-adhoc.log`, `qa/initial-unsigned.log`, `prototype/report.json`, host logs, independent review, and `tested-source-sha256.json`. Check the recorded hashes before reusing results after source changes.

Simulator coordination started with zero occupied devices. Pace used one new exclusively leased simulator, disabled test clones, and shut down only that device after QA; its lease was removed under the exclusive lock. At release the fresh inventory showed two other booted devices, owned by Hiking and Tiny. They were left running and untouched.

## Unchanged boundaries and remaining gates

The original `codex/simplify-coach-plans` checkout remains untouched; its tracked diff SHA-256 remains `065c133f2441635de8ed4787973b96d2a40e34b7a5fce1a9a857ace670ceefb1`. No real stores, Health records, CloudKit records, physical-device data or unrelated edits were read or migrated. No cloud records, retained source, entitlements, real sync behavior, public promises, prices, analytics, credentials or device permissions were changed. Letters Home was not touched.

The [release/device evidence](release-device-provenance-2026-10-22.md) finds no reachable supported physical device and no signed artifact/source linkage for App Store 2.4. An older candidate has 11 models; the 14-model inventory must not be attributed to shipping 2.4. These remain open gates, along with real-device lock/reboot behavior, true process-kill/power-loss durability, all production ingress/backup formats, the ten Coach-local types/photos, multi-device reconciliation and owner-approved production migration policy. The [existing design](local-storage-remediation-design-2026-10-22.md) remains the concrete proposal for those decisions.
