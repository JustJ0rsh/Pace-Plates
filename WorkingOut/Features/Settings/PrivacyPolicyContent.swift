enum PrivacyPolicyContent {
    static let markdown = """
    # Pace & Plates — Privacy Policy

    Effective date: 2026-10-23. Applies to Pace & Plates version 2.5.

    ## 1. Overview
    Pace & Plates helps you follow programs and log workouts, runs, body measurements, nutrition, and recovery. This version stores app history locally with CloudKit synchronization disabled. Existing local history opens directly. If older history needs a local copy, recording stays paused until you explicitly choose and complete the verified copy. We do not run our own backend for your content, sell your data, or use tracking/advertising SDKs.

    ## 2. Data We Handle
    - **Workout data (your content):** exercises, sets/reps/weight, notes.
    - **Running data (your content):** distance, duration, route (encoded GPS points), optional notes.
    - **Body weight (your content):** dated weight entries.
    - **Coach (your content):** programs, prescriptions, actual results, reviewed progression, daily nutrition totals, optional sleep/soreness/energy/pain notes, waist measurements, and optional selected progress photos.
    - **Health data (optional):** read/write via Apple Health (HealthKit), e.g., saving a run as a workout.
    - **Location (optional):** precise location for run tracking and local weather. Location is not collected by the developer.
    - **Diagnostics:** none sent to us. Apple may provide anonymized crash info if you opted in at the OS level.
    - **Identifiers:** no IDFA; no cross-app tracking

    ## 3. How We Use Data
    - **App features:** show, edit, and chart your workouts, runs, and weight.
    - **Integrations:** read or save supported Apple Health data with permission; show weather and maps; optionally show a Live Activity or create Calendar events.
    - **Community (optional):** when enabled, Game Center can receive leaderboard scores and achievement updates under your Game Center profile; these can be visible to other players. Disabling it prevents new app submissions; it does not remove updates already submitted to Game Center.
    - **Built-in AI generation:** prompts are processed on-device through Apple Intelligence when available.
    - **Copy ChatGPT Prompt:** only an explicit Copy action places the reviewed text on the clipboard. No saved personal history is included automatically. Text you paste into an external service is handled under that service's terms; the app does not upload the prompt or connect to your ChatGPT account.
    - **Preferences:** unit selection (metric/imperial) only affects on-device formatting

    ## 4. Storage Locations
    - **On-device:** app history and preferences are saved locally. Apple Health and your Photos library remain separate from app history.
    - **Local history:** all tabs use protected local storage with CloudKit disabled. The local history directory and app-owned photo copies are excluded from automatic backup. Keep deliberate history backups for recovery or transfer; new edits do not sync through the legacy CloudKit store.
    - **Legacy iCloud:** the original store is retained for recovery. The local-history transition does not delete pre-existing remote records or change other devices. We cannot access your private CloudKit data.
    - **Selected photos:** the system picker provides only items you select. The app retains resized copies without location metadata for offline viewing. Deleting an app copy does not delete the library original, and deleting the original does not delete the retained app copy.
    - **Deliberate backups:** history archives include records and, when selected, app-owned photo assets. You choose where to save or share them. Program exports contain prescriptions and notes; review notes before sharing. The app does not automatically upload backups.
    - **Apple services:** HealthKit, WeatherKit, MapKit, ActivityKit, Game Center, Calendar, Photos, and Apple Intelligence operate under Apple’s terms and the permissions or actions you choose. We do not operate those services.

    ## 5. Third-Party SDKs/Services
    Apple frameworks: HealthKit, MapKit, WeatherKit, ActivityKit, Core Location, GameKit, EventKit, Photos, SwiftData, and Apple Intelligence. Retained history created by older versions may also have private CloudKit copies; this version does not synchronize app history with them.
    No advertising or analytics SDKs are included in the app. The website has separate support-form and website-interaction practices described at paceandplates.com/privacy.

    ## 6. Sharing
    - We do not receive your saved history on a developer-operated server. Optional Apple services and export, sharing, or clipboard actions you choose may send information to those services or selected destinations.
    - We do **not** sell your data.
    - We do **not** use your data for advertising, profiling, or cross-app tracking.

    ## 7. Permissions You Control
    - **Health (HealthKit):** grant/deny per data type in Health app -> Sharing.
    - **Location:** grant/deny in Settings -> Privacy -> Location Services.
    - **Notifications/Live Activities:** grant/deny in Settings -> Notifications.
    - **Calendar and Photos:** manage access in iOS Settings. The photo picker shares only selected items.
    - **Community:** control new Game Center submissions in the app's Community setting.
    - **Legacy iCloud copies:** manage them through Apple's iCloud settings. Changing that setting does not enable history synchronization in this version, and disabling iCloud does not necessarily delete retained records.

    ## 8. Retention
    Current local history remains until you delete it or remove the app. Deleting current history does not erase retained pre-transition stores, existing cloud copies, Apple Health records, original library photos, or exports saved elsewhere. Those copies have separate deletion controls.

    ## 9. How to Delete Your Data
    - **In-app:** delete current local workouts, sets, runs, and weight entries directly, or use the app's local-history deletion setting. Retained pre-transition stores, cloud copies, and exports kept elsewhere are not deleted by this action.
    - **Health data:** Health app -> delete items saved by Pace & Plates.
    - **Legacy iCloud data:** use Apple's iCloud data-management controls for retained copies. This app does not delete them.
    - **Remove app:** removing the app does not delete Apple Health data, original library photos, retained cloud copies, or backups saved elsewhere.
    - **Export/Import:** Settings -> Backup exports a versioned history archive, with a choice to include progress photos. Older JSON backups remain importable. Keep deliberate backups if you want recovery after app removal.

    ## 10. Children's Privacy
    Pace & Plates is not directed to children under 13 and does not knowingly collect personal information from children

    ## 11. Security
    We rely on Apple platform security for on-device data. Optional Apple services and retained legacy cloud copies use Apple's security controls. We do not run independent servers for your app content.

    ## 12. International Transfers
    Optional Apple services and retained legacy iCloud copies are handled by Apple under your Apple account and Apple's terms. Exports or text you send to another service are handled under that destination's terms.

    ## 13. Changes
    We may update this policy when features change. We will update the effective date and our App Store disclosures accordingly
    """
}
