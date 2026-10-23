# Publication verification — 22 October 2026

The earlier publication hold in the release and device-acceptance reports is superseded by this verification. The owner supplied materially new evidence: GitHub CLI login was completed for JustJ0rsh. The shared default account was not switched.

## Identity and the previously denied read

A command-scoped credential retrieved from the existing JustJ0rsh keyring login authenticated as `JustJ0rsh`. The repository API returned `JustJ0rsh/Pace-Plates`, default branch `main`, public visibility, and admin/push access. No credential values were printed or saved, and no scopes were changed.

The granted `repo` scope covers repository webhooks according to [GitHub's scope documentation](https://docs.github.com/en/apps/oauth-apps/building-oauth-apps/scopes-for-oauth-apps#available-scopes). That new evidence materially resolved the exact earlier missing-hook-access requirement. The previously denied repository-hooks read was retried **once** with this existing login and returned HTTP 200 with an empty list. No denial was bypassed.

## Branch and deployment checks

Read-only repository API checks returned:

- `main` at `a3a869f6232bbd970b45951a49f17d7245141120`, matching the reviewed base.
- No existing `codex/coach-release-safety-20261022` remote ref or PR before publication.
- Zero repository webhooks, Actions workflows, deployment environments or deployment records.
- Zero check runs and commit statuses on the reviewed base; no required checks configured on `main`.
- GitHub Pages disabled.

The independent local audit found no checked-in CI provider configuration, Xcode Cloud configuration, Xcode pre/post execution action, active pre-push hook, or shell-script build phase. Fastlane's only lane captures local screenshots. Existing manual App Store Connect scripts are unchanged and not connected to a push/PR execution path. The reviewed patch changes no deployment configuration.

These checks found no automatic deployment path for a feature-branch push or draft PR. They do not enable a deployment, merge, account, credential or protection change. Publication uses only the isolated review branch; none of the original dirty work is included.

## QA and review boundary

The reviewed implementation/QA commits are `9fdee8f13a45f07c4d6a2ddcd7cb961b50d9412a`, `e9c61a25cafdb39d5a982c367d0f4d01645ff87c`, and `2c27821041e70734cf8abd58744a7685323fcccc`. This publication note changes documentation only.

Evidence remains the [release-readiness review](release-readiness-2026-10-22.md), [integrity follow-up](data-integrity-followup-2026-10-22.md), and [device-acceptance report](device-acceptance-2026-10-22.md): 184 synthetic disk assertions, eight earlier simulator journeys, native Files backup recovery, native JSON import/relaunch, Release simulator compilation, and unsigned isolated device compilation. Exploratory test failures and the interrupted run are disclosed in those reports; they are not presented as passing suites.

**Physical acceptance remains pending.** No reachable supported iPhone/iPad was available, and the isolated device candidate remains unsigned and uninstalled. Real Health/CloudKit behavior, device lock/reboot protection, background guidance and ordinary-device performance are unverified. The draft PR must retain these limitations and must not be treated as approval to merge, deploy or begin a paid pilot.

Publishing evidence, exact remote head, PR URL and hosted-check state are recorded in `.tmp/publish-verification-20261022/`. No hosted CI pass can be claimed when no hosted workflow/check is configured.
