# Pace release provenance and physical-device availability

Checked 22 October 2026. Read-only inspection; no application data, signing settings, permissions, pairing, Developer Mode or device content was changed. Worktree: `/tmp/pace-synthetic-remediation-20261022`, based on PR8 `dd254b6f2849a21cf4de3e6e7fa9c6b41721fbf3`.

## Production 2.4 cannot yet be mapped to a signed source revision

The [US App Store page](https://apps.apple.com/us/app/pace-plates/id6754347082), retrieved during this pass, still lists version 2.4 with a July 19 release date. PR8 and current main declare 2.5, build 4.

The local repository is shallow. It has no tags. Authenticated read-only GitHub API checks returned no releases, no tags, and zero Actions artifacts. Workflow-run checks for two 2.4 candidate commits returned no runs. No Pace `.xcarchive` was present in the standard local Xcode Archives directory; the directory contained only an archive for an unrelated app, whose contents were not inspected. No `.ipa` or release export manifest was found in the scoped worktree search.

Version metadata alone leaves several candidates:

| Evidence | Observation | Interpretation |
| --- | --- | --- |
| Oldest available shallow commit `965744879fb0fbae3effbf214ec40436ac262eb4` | 11 July 2026; app version 2.4, build 1; message “Add wearable-aware vitals snapshot and settings” | Plausible source-era evidence, but no signed binary or store-build linkage. |
| Last ancestor before the 2.5 version bump, `856bf0b35a032639dfa9cb08367ab2a33273054d` | 24 August 2026; app version 2.4, build 3 | Later than the public July 19 release date; cannot be assumed shipped just because it says 2.4. |
| Version-bump commit `98979eb2c3579376e660957fabdf8e6d945325a8` | 24 August 2026; changes app/extensions from 2.4 to 2.5 and build 3 to 4 | Establishes the local source transition, not App Store submission or acceptance. |

The oldest candidate's `WorkingOut/Data/PersistenceController.swift` defaults to `cloudKitMode: .automatic` and defines an **11-model** schema. This source finding is not proof of upload, nor proof that this exact source shipped. In particular, the PR8 audit's **14 models / 253 fields must not be represented as the verified production 2.4 inventory**.

Remaining provenance requirement: an owner-provided signed 2.4 archive/export plus its source revision/build record, or App Store Connect build metadata tied to the exact submitted artifact and source. No App Store Connect settings, declarations or credentials were inspected or changed.

## Physical-device availability

The sandboxed `xcrun devicectl list devices` attempt failed while initializing CoreDeviceService. The same read-only command completed outside the sandbox after approval. Raw result is `devices.json`; a reduced non-identifier summary is `physical-summary.json`.

| Physical target | Observed state | Pace suitability |
| --- | --- | --- |
| iPad17,3, iPadOS 27.0 | Paired; connection unavailable; DDI services unavailable | Supported device family but not currently reachable for validation. |
| Watch7,12 | Paired; connection disconnected; DDI services unavailable | Pace has no standalone watchOS target; not a substitute for an iPhone/iPad. |

**Zero reachable supported physical Pace targets were found.** No install, device connection, unlock, trust, pairing or Developer Mode action was attempted. Physical acceptance remains pending device availability; permission state is not established by this inventory.

## Scope and limitations

No simulator was booted or stopped by this subtask. No real Health/CloudKit/workout records were opened. No original checkout file, app source, entitlement, release, branch, PR, account, permission or unrelated archive was modified. This report and the inventory files are the only new local artifacts.
