# OpenRouter Anonymous Quota Proposal

## Recommendation

Use a small server-side OpenRouter proxy with a server-enforced daily quota per anonymous installation.

Recommended shape:
- Cloudflare Worker as the proxy
- Durable Object as the quota store
- Keychain-backed anonymous install ID in the app
- App Attest on supported devices to make the anonymous ID harder to fake
- One server-side OpenRouter key only
- Daily limit enforced on the proxy, not on the device

This is the best fit for your app because you do not have login, you want a real daily cap, and the current app is client-only today.

## Why This Wins

Current state in the app:
- OpenRouter requests go directly from the device in [WorkingOut/Services/OpenRouterAIService.swift](WorkingOut/Services/OpenRouterAIService.swift).
- The quota is only local `UserDefaults` state in [WorkingOut/Services/AIUsageBudgetManager.swift](WorkingOut/Services/AIUsageBudgetManager.swift).
- Settings currently describe those limits as "Device guardrails" in [WorkingOut/Features/Settings/SettingsView.swift](WorkingOut/Features/Settings/SettingsView.swift).

Problems with the current model:
- A device-local counter is not real abuse protection. It can be reset or bypassed.
- If you ever fund OpenRouter usage yourself, the OpenRouter key cannot safely live on the device.
- The current limit is charged inside the provider retry loop, so one user action can burn multiple daily attempts.
- The app is currently biased toward `:free` models, and OpenRouter's docs say free models have low rate limits and are usually not suitable for production use.

Relevant research:
- OpenRouter auth docs say API keys are powerful and must be protected: [Authentication](https://openrouter.ai/docs/api/reference/authentication)
- OpenRouter request schema includes `user`, described as "A stable identifier for your end-users. Used to help detect and prevent abuse.": [API Reference](https://openrouter.ai/docs/api/reference/overview)
- OpenRouter responses include usage and cost data: [API Reference](https://openrouter.ai/docs/api/reference/overview)
- OpenRouter says extra accounts or API keys do not change platform rate limits, and free models are capped per day: [Limits](https://openrouter.ai/docs/api/reference/limits)
- OpenRouter FAQ says `:free` models have low rate limits and are usually not suitable for production use: [FAQ](https://openrouter.ai/docs/faq)
- Apple recommends DeviceCheck and App Attest as part of an antifraud strategy and says App Attest can validate app integrity before a server grants access to sensitive data: [Apple Security](https://developer.apple.com/security/)

## Recommended Architecture

### 1. Anonymous identity

On first launch:
- Generate a random `anonymousInstallId`
- Store it in Keychain
- If App Attest is available, create an App Attest key and register it with the server

Why:
- You do not need login
- You get a stable anonymous subject for quota tracking
- App Attest makes replay and scripted abuse harder than a plain UUID

### 2. Server-side proxy

The app should call your proxy, not OpenRouter directly.

Suggested endpoints:
- `GET /v1/ai/quota` -> returns remaining quota, reset time, cooldown, and burst-limit state
- `POST /v1/ai/chat`
- `POST /v1/ai/workout-plan`
- `POST /v1/ai/run-plan`

Proxy behavior:
1. Validate the anonymous install ID
2. Verify App Attest assertion when available
3. Load quota state for `{install_id, day_bucket}`
4. Reject if daily or minute quota is exhausted
5. Forward the request to OpenRouter using the server-side key
6. Send `user = sha256(anonymousInstallId)` to OpenRouter
7. Record usage and return the response or stream back to the app

### 3. Quota model

Start with a simple action-based quota first. It matches your product ask better than cost math in the UI.

Recommended initial limits to review:
- `10` AI actions per day per anonymous installation
- `4` AI actions per rolling minute
- `90` second cooldown after upstream `429` or `503`

Important rule:
- Charge once per user action, not once per upstream retry

That means if the proxy retries OpenRouter provider/model fallback internally, the user still spends only one action.

### 4. Usage logging

Even if you enforce a simple "actions per day" limit at launch, log:
- `prompt_tokens`
- `completion_tokens`
- `total_tokens`
- `cost`
- feature type (`chat`, `workout-plan`, `run-plan`)

OpenRouter already returns usage data. Store it so you can later tune the daily limit with real app data.

## Why Cloudflare Worker + Durable Object

I recommend this over adding a bigger backend because the repo has no existing server layer today.

Why this pairing is a good fit:
- Worker gives you a thin HTTPS proxy quickly
- Durable Object gives you one consistent quota authority per anonymous install
- The quota problem is mostly atomic increments plus short-window burst control
- It keeps your OpenRouter key off the device

A Durable Object is a better fit than a purely client-side counter because you need one authoritative source of truth.

## What Not To Do

- Do not ship your own OpenRouter API key inside the iOS app.
- Do not rely on `UserDefaults` as the real quota system.
- Do not keep production on `:free` OpenRouter models if you are funding usage yourself.
- Do not decrement quota inside the model retry loop.

## Lower-Effort Fallback

If you want the smallest possible infrastructure step, there is a weaker fallback:
- Mint one limited OpenRouter key per anonymous install from your backend
- Put a daily credit limit or guardrail on that key

Why I do not recommend it as the primary design:
- The app still receives a usable OpenRouter key
- Reverse engineering or key extraction is still possible
- It constrains blast radius, but it does not solve client-side key exposure

Use this only if you want minimal code churn and accept weaker protection.

## Proposed App Changes

Existing files to change:
- [WorkingOut/Services/AIUsageBudgetManager.swift](WorkingOut/Services/AIUsageBudgetManager.swift)
  Replace device-local authority with a server quota client and keep only cached display state locally.
- [WorkingOut/Services/OpenRouterAIService.swift](WorkingOut/Services/OpenRouterAIService.swift)
  Change the base URL from OpenRouter to your proxy for app-managed mode. If any direct OpenRouter calls remain, update the attribution header to the documented `X-OpenRouter-Title`.
- [WorkingOut/Services/AIProviderManager.swift](WorkingOut/Services/AIProviderManager.swift)
  Split "user supplied OpenRouter key" from "app-managed proxy" so both modes can exist cleanly.
- [WorkingOut/Features/Settings/SettingsView.swift](WorkingOut/Features/Settings/SettingsView.swift)
  Show server quota status instead of only local device counters when app-managed mode is enabled.
- [WorkingOut/Features/Settings/PrivacyPolicyContent.swift](WorkingOut/Features/Settings/PrivacyPolicyContent.swift)
  Update the privacy copy because the app would now run server-side AI relay infrastructure.

New files to add:
- `WorkingOut/Services/AnonymousAIIdentityManager.swift`
- `WorkingOut/Services/AIQuotaService.swift`
- `Docs/AI_PROXY_API.md` or similar backend contract doc

## Minimal Rollout Plan

Phase 1:
- Add anonymous install ID
- Add proxy with daily/minute quota
- Route all app-managed OpenRouter traffic through the proxy
- Keep current local counter only as a temporary UX cache

Phase 2:
- Add App Attest validation
- Add usage logging and dashboard
- Tune limits using real cost data

Phase 3:
- Remove direct app-managed OpenRouter traffic from the device entirely
- Keep direct OpenRouter only for explicit BYOK mode, if you still want BYOK

## Review Decision

If you approve this direction, the implementation I would recommend next is:
1. Add anonymous install identity in the app
2. Build the proxy contract first
3. Refactor `AIUsageBudgetManager` to talk to that contract
4. Move `OpenRouterAIService` behind the proxy for app-managed mode

That sequence gives you the real quota protection first and avoids another round of churn later.
