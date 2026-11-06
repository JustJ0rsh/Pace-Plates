# Version 2.5 wording reconciliation

Owner confirmed the remaining phone acceptance checks on 2026-10-23. This confirmation does not substitute for distribution-archive or App Store Connect validation.

The in-app policy, public website draft, and prepared store description now distinguish local version2.5 history from older private CloudKit copies. They describe deliberate versioned backups, optional progress-photo assets, separate deletion controls, and optional Apple/clipboard/share destinations. Website copy additionally preserves support-form, Resend delivery, Cloudflare logging, and individual website-interaction event and aggregate-count disclosures.

Store text is prepared in `app-store-description-2.5.txt` and `release-notes-2.5.txt`; these files do not publish or submit metadata. Do not automatically change the App Privacy questionnaire from prose alone. Validate answers against the final release's actual service flows and Apple definitions.

Website source is based on the current Cloudflare deployment's recorded source `76f3f755483ced4f42d918760b2071cd387357db`, not repository main, which has been repurposed for Hiking+. Only Pace index/privacy HTML changes belong in that deployment; preserve all existing API functions, routing, support page and assets.

No new model, entitlement, credential, permission, or storage behavior is introduced by these wording changes. Final App Store distribution archive remains a separate release artifact.
