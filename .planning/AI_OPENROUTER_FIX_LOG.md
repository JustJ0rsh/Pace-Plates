# AI OpenRouter Fix Log

Date: 2026-06-20

## Goal

Make OpenRouter usable with the user's API key, store the key safely, enforce app-side limits that match OpenRouter free-model limits, and continue smoke testing AI-related surfaces.

## Source-Backed Limit Decision

OpenRouter free-model limits are enforced per account/key. The current app-side default is now:

- 20 requests per minute.
- 50 free-model requests per UTC day for accounts below OpenRouter's credited threshold.
- Optional 1000 free-model requests per UTC day setting for accounts that qualify for OpenRouter's higher free-model cap.

The app also keeps per-action model fallback capped at 3 attempts so a single request cannot silently try an unbounded number of free providers.

## Fixes Applied

- Stored OpenRouter API keys in Keychain with `kSecAttrAccessibleWhenUnlockedThisDeviceOnly`.
- Stopped loading the saved API key back into the Settings text field.
- Added basic pasted-key validation to reject empty, too-short, or whitespace-containing values.
- Saving a key now selects OpenRouter as the active AI provider.
- Added OpenRouter daily limit controls and a local usage counter reset in Settings.
- Changed local OpenRouter daily usage buckets from local time to UTC-day buckets.
- Raised local default limits from 10/day and 4/minute to 50/day and 20/minute.
- Added visible OpenRouter quota summaries on the AI tab and Running Assistant AI card.

## Bugs Found While Working

- Saving an OpenRouter key did not switch the AI provider to OpenRouter on Apple-Intelligence-capable devices.
- Settings loaded the full saved API key into view state on every appearance.
- Local usage counters reset at local midnight instead of UTC-day boundaries.
- Existing in-app OpenRouter limits were much lower than OpenRouter's documented free-model limits.
- OpenRouter Settings save/reset alerts inherited the generic Backup alert title.
- AI provider status synchronization wrote the Keychain-configured flag on every status read, which can trigger unnecessary SwiftUI/AppStorage invalidation.

## Verification

- Passed `git diff --check` on tracked modified AI/settings files; untracked Swift service files were covered by the Xcode build.
- Passed `xcodebuild build -project 'Pace & Plates.xcodeproj' -scheme WorkingOut -configuration Debug -destination 'platform=iOS Simulator,id=C8CE439A-A426-4124-8C8C-5BC457A2DBFA' -derivedDataPath /tmp/pace-plates-ai-derived`.
- Installed and launched the rebuilt app on simulator `C8CE439A-A426-4124-8C8C-5BC457A2DBFA`.
- Confirmed normal Home launch renders after the final build.
- Confirmed the AI tab renders in normal app state. It remains on Apple Intelligence in this simulator because no real OpenRouter API key was entered.
- Confirmed the live OpenRouter models endpoint still includes the app's preferred free fallback model IDs.

## Verification Limits

- A focused XCTest attempt for Settings > AI Provider was interrupted twice because Xcode's UI test runner stalled before assertions on app-idle/automation-session handling. The run did build the app and UI test target, but did not produce passing assertion results.
- The simulator tap bridge highlighted the Home Settings button but did not complete that navigation reliably, so Settings subpage visual verification could not be completed through the live mirror in this pass.
- No real OpenRouter generation request was sent because the user's actual API key was not available in this session and should not be guessed or stored by the agent.
