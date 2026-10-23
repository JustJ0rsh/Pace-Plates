# Pace & Plates — verified product facts

Checked 22 October 2026. This is factual input for CyberCore product pages, not a pricing proposal or approval to change public copy. Preserve the existing free/no-subscription/no-paywall/no-ad promises.

## Evidence boundary

The public US storefront shows version **2.4**. The audited repository snapshots both declare **2.5, build 4**: main `a3a869f6232bbd970b45951a49f17d7245141120` and draft PR7 `0f69a4022f17f54fe54fb5b2d1fc6201a8c75ec2`. No signed-binary-to-commit mapping was available. New Coach capabilities and reviewed fixes must not be described as already shipped solely because they exist in the repository.

## Current public product facts

| Fact | Verified evidence / qualification |
| --- | --- |
| Publisher | The [US App Store listing](https://apps.apple.com/us/app/pace-plates/id6754347082) names CyberCore Security LLC as seller. |
| Price and promises | The listing is Free and promises no subscription, paywall, ads, tracking or analytics. Do not add contrary monetization or measurement. |
| Platform | Market as an iPhone/iPad fitness app requiring iOS/iPadOS 26+. The repository has no watchOS target; importing Watch workouts is not a standalone Watch app. |
| Core use | Strength-workout logging, run/cardio tracking and weight trends are supported by the [product site](https://paceandplates.com/) and corresponding app features. |
| Integrations | Optional Apple Health and location-dependent weather/maps exist. Built-in AI requires compatible hardware and Apple Intelligence availability; iOS 26 alone is insufficient. |
| Accounts | Ordinary app use requires no developer account. Optional Community uses an Apple Game Center account and can share fitness scores/achievements. |
| Privacy label | The storefront's Data Not Collected label is a developer declaration; the listing says Apple has not verified it. It is not independent certification of this audit or a statement that no Apple service receives data. |

## Claims supported by the inspected source

- No ad, payment, third-party analytics, ATT/IDFA or app-owned HTTP backend implementation was found in the main/PR7 app and extensions. `WorkingOut/PrivacyInfo.xcprivacy` declares tracking false, no tracking domains and no collected-data entries. This supports the audited source; it does not attest the released 2.4 binary.
- Built-in plan generation uses Apple Foundation Models (`WorkoutPlanGenerator.swift:175`, `RunAssistantAIService.swift:82`). Availability is checked in `AIProviderManager.swift:82`. The separate Copy ChatGPT Prompt flow is a deliberate clipboard action, with personal context off by default; the app does not automatically upload that prompt (`CoachPlanImportView.swift:88`).
- The app can call Apple services: WeatherKit receives coordinates, MapKit performs reverse geocoding, and opted-in Game Center can receive PRs/run statistics/streaks. Use precise service disclosure rather than an absolute claim that information never leaves the device.
- PR7 protects storage-switch races and stale draft replacement. Synthetic backup recovery and native Files checks passed. Physical-device acceptance is still pending. These are release-candidate facts, not current-store guarantees.

## Claims to withhold or qualify

1. **Do not promote personal-health iCloud sync as a resolved privacy/compliance assurance.** The default legacy schema can persist Health-derived and manually entered personal fitness information with CloudKit enabled. Coach-local mode changes future writes on that device and retains older copies. See the [privacy/storage audit](privacy-growth-audit-2026-10-22.md).
2. **Do not say all data always stays on-device, all copies disappear after one Delete action, or no Apple services receive data.** Those statements exceed the source evidence.
3. **Do not extend the app's no-analytics claim to the website.** The public [website script](https://paceandplates.com/scripts/main.js) already sends limited conversion/support events to `/api/event`; page HTML includes Cloudflare's analytics beacon. The [website privacy policy](https://paceandplates.com/privacy) separately discloses event counts and hosting logs. This audit did not execute those scripts, submit a form, add measurement, or inspect server-side event storage.
4. Do not advertise 2.5/Coach as released, medical outcomes, universal AI compatibility, independently verified privacy, or completed physical QA.

## Owner verification still needed

- Identify the source commit/build corresponding to live App Store 2.4 before making source-specific shipping assurances.
- Confirm the account-wide and app-specific DSA trader declarations in App Store Connect. The seller being an LLC does not verify those declarations. Apple's [DSA guidance](https://developer.apple.com/help/app-store-connect/manage-compliance-information/manage-european-union-digital-services-act-trader-requirements/) requires owner assessment and shows where Account Holders/Admins can inspect the settings. No declarations were accessed or changed.
- Resolve the health-data storage policy gate and complete physical-device acceptance before strengthening privacy or reliability claims.

No public page, price, analytics configuration, account declaration, PR7 code, or production storage was changed by this fact-sheet work.
