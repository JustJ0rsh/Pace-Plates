enum PrivacyPolicyContent {
    static let markdown = """
    # Pace & Plates — Privacy Policy

    Effective date: 2026-09-13

    .   1) Overview
    Pace & Plates helps you follow programs and log workouts, runs, body measurements, nutrition, and recovery. Coach uses protected local storage after you explicitly choose the reviewed local-history transition. Before that transition, older app records may use the legacy private iCloud configuration. We do not run our own backend for your content, sell your data, or use tracking/advertising SDKs.

    .   2) Data We Handle
    - **Workout data (your content):** exercises, sets/reps/weight, notes.
    - **Running data (your content):** distance, duration, route (encoded GPS points), optional notes.
    - **Body weight (your content):** dated weight entries.
    - **Coach (your content):** programs, prescriptions, actual results, reviewed progression, daily nutrition totals, optional sleep/soreness/energy/pain notes, waist measurements, and optional selected progress photos.
    - **Health data (optional):** read/write via Apple Health (HealthKit), e.g., saving a run as a workout.
    - **Location (optional):** precise location for run tracking and local weather. Location is not collected by the developer.
    - **Diagnostics:** none sent to us. Apple may provide anonymized crash info if you opted in at the OS level.
    - **Identifiers:** no IDFA; no cross-app tracking

    .   3) How We Use Data
    - **App features:** show, edit, and chart your workouts, runs, and weight.
    - **Integrations:** save runs to Apple Health (with permission); show local weather; optionally show a Live Activity.
    - **Built-in AI generation:** prompts are processed on-device through Apple Intelligence when available.
    - **Copy ChatGPT Prompt:** only an explicit Copy action places the reviewed text on the clipboard. No saved personal history is included automatically. Text you paste into an external service is handled under that service's terms; the app does not upload the prompt or connect to your ChatGPT account.
    - **Preferences:** unit selection (metric/imperial) only affects on-device formatting

    .   4) Storage Locations
    - **On-device:** all logs and preferences are saved locally.
    - **Coach local storage:** personal Coach records and imported photo copies use a protected store with CloudKit disabled and automatic backup excluded. After you choose local ownership, all tabs use the verified local copy of your history. New edits on that device no longer sync to the legacy CloudKit store.
    - **Legacy iCloud:** the original store is retained for recovery. The local-history transition does not delete pre-existing remote records or change other devices. We cannot access your private CloudKit data.
    - **Selected photos:** the system picker provides only items you select. The app retains resized copies without location metadata for offline viewing. Deleting an app copy does not delete the library original, and deleting the original does not delete the retained app copy.
    - **Deliberate backups:** history archives include records and, when selected, app-owned photo assets. You choose where to save or share them. Program exports contain prescriptions and notes; review notes before sharing. The app does not automatically upload backups.
    - **Apple services:** HealthKit, WeatherKit, MapKit, ActivityKit, and Apple Intelligence operate under Apple’s terms. We do not receive those requests.

    .   5) Third-Party SDKs/Services
    Apple frameworks: HealthKit, CloudKit (Private DB), MapKit, WeatherKit, ActivityKit, Core Location, SwiftData, Apple Intelligence.
    No advertising or analytics SDKs.

    .   6) Sharing
    - We do **not** send your data to third parties.
    - We do **not** sell your data.
    - We do **not** use your data for advertising, profiling, or cross-app tracking.

    .   7) Permissions You Control
    - **Health (HealthKit):** grant/deny per data type in Health app -> Sharing.
    - **Location:** grant/deny in Settings -> Privacy -> Location Services.
    - **Notifications/Live Activities:** grant/deny in Settings -> Notifications.
    - **iCloud sync:** enable/disable in Settings -> [Your Name] -> iCloud -> Show All -> Pace & Plates

    .   8) Retention
    Your data remains until you delete it. You can remove entries individually in the app at any time

    .   9) How to Delete Your Data
    - **In-app:** delete workouts, sets, runs, and weight entries directly, or in the app’s settings.
    - **Health data:** Health app -> delete items saved by Pace & Plates.
    - **iCloud data:** Settings -> [Your Name] -> iCloud -> Apps Using iCloud -> Pace & Plates -> turn off and remove data.
    - **Remove app:** deleting the app removes on-device data; use the iCloud step above to remove cloud copies.
    - **Export/Import:** Settings -> Backup exports a versioned history archive, with a choice to include progress photos. Older JSON backups remain importable. Keep deliberate backups if you want recovery after app removal.

    .   10) Children's Privacy
    Pace & Plates is not directed to children under 13 and does not knowingly collect personal information from children

    .   11) Security
    We rely on Apple platform security for on-device data and CloudKit’s authentication/encryption for iCloud. We do not run independent servers for your app content.

    .   12) International Transfers
    Data stored in iCloud is handled by Apple under your Apple ID and Apple’s terms.

    .   13) Changes
    We may update this policy when features change. We will update the effective date and our App Store disclosures accordingly
    """
}
