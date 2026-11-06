enum PrivacyPolicyContent {
    static let markdown = """
    # Pace & Plates — Privacy Policy

    Effective date: 2026-10-30. Applies to the Pace & Plates iCloud restoration update.

    ## 1. Overview
    Pace & Plates helps you follow programs and log workouts, runs, body measurements, nutrition, and recovery. Workouts, runs, weight entries, plans, exercise libraries, and AI conversations can sync through your private iCloud account, as they did before version 2.5. Additional Coach records and app-owned progress photos stay on this device. We do not run our own backend for your content, sell your data, or use tracking/advertising SDKs.

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
    - **On-device:** the app keeps local copies of its history and preferences. Apple Health and your Photos library remain separate from app history.
    - **Private iCloud:** workouts, runs, weight entries, plans and scheduled sessions, exercise libraries, templates, AI conversations, and workout-import records use the app's existing private CloudKit store when iCloud is available and enabled. Saved activity records may include routes, measurements, notes, and values imported from Apple Health. Synchronization depends on your account, settings, connectivity, and Apple's services. We cannot access your private CloudKit data.
    - **Additional Coach records:** plan revisions, detailed execution snapshots, progression suggestions, nutrition, recovery check-ins, waist measurements, calendar mappings, and progress-photo records use protected local storage with CloudKit disabled. This storage and app-owned photo copies are excluded from automatic backup. Use deliberate history backups to recover or transfer these records. Plans, scheduled sessions, and results recorded in workout or run history use the iCloud storage described above.
    - **Recovery copies:** the iCloud restoration update retains previous stores for recovery while restoring access to existing history. Deleting current app records does not delete these retained copies.
    - **Selected photos:** the system picker provides only items you select. The app retains resized copies without location metadata for offline viewing. Deleting an app copy does not delete the library original, and deleting the original does not delete the retained app copy.
    - **Deliberate backups:** history archives include records and, when selected, app-owned photo assets. You choose where to save or share them. Program exports contain prescriptions and notes; review notes before sharing. The app does not automatically upload backups.
    - **Apple services:** HealthKit, WeatherKit, MapKit, ActivityKit, Game Center, Calendar, Photos, and Apple Intelligence operate under Apple’s terms and the permissions or actions you choose. We do not operate those services.

    ## 5. Third-Party SDKs/Services
    Apple frameworks: HealthKit, CloudKit, MapKit, WeatherKit, ActivityKit, Core Location, GameKit, EventKit, Photos, SwiftData, and Apple Intelligence.
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
    - **iCloud:** manage Pace & Plates synchronization in Apple's iCloud settings. Disabling synchronization does not necessarily delete previously stored records.

    ## 8. Retention
    Current history remains until you delete it. Deletion of records in the iCloud-backed history synchronizes through iCloud when available. Additional Coach records and app-owned photo copies remain local. Deleting current history does not erase retained recovery stores, Apple Health records, original library photos, or exports saved elsewhere. Removing the app does not delete its iCloud history.

    ## 9. How to Delete Your Data
    - **In-app:** delete workouts, sets, runs, and weight entries directly, or use Settings -> Backup & Data -> Delete All Data. Deletions from iCloud-backed history synchronize when available; additional Coach records and app-owned photos are deleted locally. Retained recovery copies and exports kept elsewhere are not deleted by this action.
    - **Health data:** Health app -> delete items saved by Pace & Plates.
    - **iCloud data:** use Apple's iCloud data-management controls to manage the app's cloud records. In-app deletion also synchronizes for records in the active iCloud-backed history.
    - **Remove app:** removing the app does not delete Apple Health data, original library photos, retained cloud copies, or backups saved elsewhere.
    - **Export/Import:** Settings -> Backup exports a versioned history archive, with a choice to include progress photos. Older JSON backups remain importable. Keep deliberate backups if you want recovery after app removal.

    ## 10. Children's Privacy
    Pace & Plates is not directed to children under 13 and does not knowingly collect personal information from children

    ## 11. Security
    We rely on Apple platform security for on-device data and CloudKit's authentication and encryption for private iCloud history. Optional Apple services use Apple's security controls. We do not run independent servers for your app content.

    ## 12. International Transfers
    Optional Apple services and private iCloud history are handled by Apple under your Apple account and Apple's terms. Exports or text you send to another service are handled under that destination's terms.

    ## 13. Changes
    We may update this policy when features change. We will update the effective date and our App Store disclosures accordingly
    """
}
