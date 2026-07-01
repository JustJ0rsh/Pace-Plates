enum PrivacyPolicyContent {
    static let markdown = """
    # Pace & Plates — Privacy Policy

    Effective date: 2026-04-08

    .   1) Overview
    Pace & Plates helps you log workouts, runs, and body weight on your iPhone. Your data stays on your device and, if you enable iCloud for the app, in your private iCloud account. We do not run our own backend for your content, do not sell your data, and do not use tracking/advertising SDKs

    .   2) Data We Handle
    - **Workout data (your content):** exercises, sets/reps/weight, notes.
    - **Running data (your content):** distance, duration, route (encoded GPS points), optional notes.
    - **Body weight (your content):** dated weight entries.
    - **Health data (optional):** read/write via Apple Health (HealthKit), e.g., saving a run as a workout.
    - **Location (optional):** precise location for run tracking and local weather. Location is not collected by the developer.
    - **Diagnostics:** none sent to us. Apple may provide anonymized crash info if you opted in at the OS level.
    - **Identifiers:** no IDFA; no cross-app tracking

    .   3) How We Use Data
    - **App features:** show, edit, and chart your workouts, runs, and weight.
    - **Integrations:** save runs to Apple Health (with permission); show local weather; optionally show a Live Activity.
    - **AI generation:** when you use Apple Intelligence, prompts are processed on-device through Apple’s framework. If you choose OpenRouter and provide your own API key, the prompt and the workout/running context needed to answer it are sent to OpenRouter and the model provider OpenRouter routes the request to.
    - **Preferences:** unit selection (metric/imperial) only affects on-device formatting

    .   4) Storage Locations
    - **On-device:** all logs and preferences are saved locally.
    - **iCloud (CloudKit, Private Database):** if enabled, your data syncs privately under your Apple ID. We (the developer) cannot access your private CloudKit data.
    - **Apple services:** HealthKit, WeatherKit, MapKit, ActivityKit, and Apple Intelligence operate under Apple’s terms. We do not receive those requests.
    - **OpenRouter (optional):** if you select OpenRouter in Settings, your AI prompt and the minimum app context needed for generation are sent directly from your device to OpenRouter using your API key.

    .   5) Third-Party SDKs/Services
    Apple frameworks: HealthKit, CloudKit (Private DB), MapKit, WeatherKit, ActivityKit, Core Location, SwiftData, Apple Intelligence.
    Optional cloud AI service: OpenRouter, only when you choose it and save an API key.
    No advertising or analytics SDKs.

    .   6) Sharing
    - We do **not** send your data to third parties unless you explicitly enable OpenRouter for AI generation. If you do, the AI prompt and included training context are shared with OpenRouter and the model provider handling that request.
    - We do **not** sell your data.
    - We do **not** use your data for advertising, profiling, or cross-app tracking.

    .   7) Permissions You Control
    - **Health (HealthKit):** grant/deny per data type in Health app -> Sharing.
    - **Location:** grant/deny in Settings -> Privacy -> Location Services.
    - **Notifications/Live Activities:** grant/deny in Settings -> Notifications.
    - **iCloud sync:** enable/disable in Settings -> [Your Name] -> iCloud -> Show All -> Pace & Plates
    - **AI provider:** choose Apple Intelligence or OpenRouter inside Pace & Plates Settings. Remove your OpenRouter key there at any time.

    .   8) Retention
    Your data remains until you delete it. You can remove entries individually in the app at any time

    .   9) How to Delete Your Data
    - **In-app:** delete workouts, sets, runs, and weight entries directly, or in the app’s settings.
    - **Health data:** Health app -> delete items saved by Pace & Plates.
    - **iCloud data:** Settings -> [Your Name] -> iCloud -> Apps Using iCloud -> Pace & Plates -> turn off and remove data.
    - **Remove app:** deleting the app removes on-device data; use the iCloud step above to remove cloud copies.
    - **Export/Import:** Settings -> Backup lets you export a JSON backup and re-import it later

    .   10) Children's Privacy
    Pace & Plates is not directed to children under 13 and does not knowingly collect personal information from children

    .   11) Security
    We rely on Apple platform security for on-device data, Keychain for the optional OpenRouter API key, and CloudKit’s authentication/encryption for iCloud. We do not run independent servers for your app content.

    .   12) International Transfers
    Data stored in iCloud is handled by Apple under your Apple ID and Apple’s terms. If you enable OpenRouter, OpenRouter and its routed model provider may process AI requests outside your country under their own terms.

    .   13) Changes
    We may update this policy when features change. We will update the effective date and our App Store disclosures accordingly
    """
}
