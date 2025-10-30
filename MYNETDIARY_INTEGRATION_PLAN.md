# MyNetDiary & Third-Party App Integration Plan

## Overview
This document outlines how Pace & Plates (P&P) can integrate with MyNetDiary and other fitness tracking apps to provide seamless workout data sharing.

## About MyNetDiary
**MyNetDiary** is a comprehensive nutrition and fitness tracking app that includes:
- Calorie counting and meal tracking with AI Meal Scan
- Barcode scanner for food logging
- Exercise and workout tracking
- **HealthKit integration** (reads/writes workout data)
- Integration with fitness devices (Fitbit, Garmin, Apple Watch, etc.)

## Current P&P Capabilities
Your app already has robust HealthKit integration:
- ✅ Reads workouts from HealthKit
- ✅ Writes runs/walks to HealthKit
- ✅ Imports HealthKit workouts automatically (see `RunLogView.swift` line 350-400)
- ✅ Tracks daily steps from Health app
- ✅ Supports activity type detection (.running workouts)

## Integration Strategy: Three Options

### **Option 1: HealthKit Bridge (RECOMMENDED - Already Partially Working!)**

**How It Works:**
1. MyNetDiary logs walks/runs to Apple Health
2. P&P automatically imports them from HealthKit
3. Both apps stay synchronized through Health as the "source of truth"

**Current Status:**
- ✅ P&P already imports HealthKit workouts automatically
- ✅ Code in place: `importHealthRuns()` function
- ⚠️ Currently only imports `.running` workout type
- 🔧 Needs enhancement to also import `.walking` workouts

**What Needs to Be Added:**
1. **Expand workout type support** - Include walking, hiking, cycling
2. **Settings toggle** - Let users choose which workout types to import
3. **Visual indicator** - Show which workouts came from external apps (with app icon/name if available)
4. **Bidirectional sync** - When P&P creates a workout, MyNetDiary can also see it

**Pros:**
- ✅ No direct app-to-app integration needed
- ✅ Works with ANY app that uses HealthKit (Strava, Nike Run Club, Fitbit, etc.)
- ✅ Apple's built-in privacy controls
- ✅ Most seamless user experience
- ✅ Already 80% implemented!

**Cons:**
- ⚠️ Requires user to grant HealthKit permissions to both apps
- ⚠️ Limited to data types supported by HealthKit

---

### **Option 2: Manual Entry - "Log Past Workout" Feature**

**How It Works:**
1. User completes walk in MyNetDiary
2. Opens P&P and taps "Add Past Workout"
3. Manually enters: date, time, distance, duration
4. P&P saves it locally and optionally writes to HealthKit

**What Needs to Be Added:**
1. **New "Add Past Workout" button** in Run log view
2. **Form with fields:**
   - Activity type (Walk, Run, Hike, Cycle)
   - Date & Time
   - Distance & Unit (km/mi)
   - Duration
   - Notes (optional)
   - Calories (optional - or auto-calculate)
3. **Optional HealthKit write** - Give user choice to also log to Health

**Pros:**
- ✅ Works even if HealthKit integration fails
- ✅ Gives users full control over data entry
- ✅ Can add workouts from apps that DON'T use HealthKit
- ✅ Can add historical data

**Cons:**
- ⚠️ Manual effort required
- ⚠️ Potential for data entry errors
- ⚠️ No automatic GPS route data

---

### **Option 3: Hybrid Approach (BEST USER EXPERIENCE)**

Combine both methods:
1. **Automatic import** from HealthKit (primary method)
2. **Manual entry** as fallback for edge cases

**User Flow:**
```
Start Walk in MyNetDiary
    ↓
MyNetDiary → Apple Health
    ↓
P&P auto-imports from Health (within minutes)
    ↓
If import fails or workout not detected:
    → User can manually add via "Add Past Workout"
```

**Settings Panel:**
```
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
Workout Import Settings
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

[✓] Automatically import workouts from Health app

Import workout types:
  [✓] Running
  [✓] Walking
  [✓] Hiking
  [ ] Cycling
  [ ] Swimming

[✓] Show source app name (when available)

Last sync: 2 minutes ago
[Sync Now]
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
```

---

## Recommended Implementation Plan

### Phase 1: Enhance HealthKit Import (Quick Win - ~2-3 hours)
1. ✅ Modify `importHealthRuns()` to also import walking workouts
2. ✅ Add workout type filtering in settings
3. ✅ Display workout source (MyNetDiary vs P&P vs other apps)
4. ✅ Test with multiple workout types

**Code Changes Needed:**
- `HealthKitManager.swift`: Add method to fetch walking/hiking workouts
- `RunLogView.swift`: Update import logic to handle multiple workout types
- `RunningSession.swift`: Add `activityType` and `sourceApp` fields
- Settings: Add workout import preferences

### Phase 2: Manual Entry Feature (~3-4 hours)
1. ✅ Create new `AddPastWorkoutView.swift`
2. ✅ Add form with all necessary fields
3. ✅ Implement save to SwiftData + optional HealthKit write
4. ✅ Add "Add Past Workout" button to run log toolbar

**New Components:**
- `AddPastWorkoutView.swift` - Form for manual entry
- Add menu item in `RunLogView` toolbar

### Phase 3: Polish & UX Improvements (~2 hours)
1. ✅ Smart duplicate detection (don't import if manually entered)
2. ✅ Workout source badges/icons in list view
3. ✅ Settings page for import preferences
4. ✅ Better visual distinction between tracked vs imported workouts

---

## Technical Notes

### HealthKit Workout Types to Support
```swift
// Current: only .running
// Should add:
.walking
.hiking  
.cycling // if user wants
.swimming // future
.yoga // future
```

### Data Mapping
When importing from HealthKit:
- `HKWorkout.startDate` → `RunningSession.date`
- `HKWorkout.duration` → `RunningSession.duration`
- `HKWorkout.totalDistance` → `RunningSession.distance`
- `HKWorkout.uuid` → `RunningSession.healthWorkoutUUID`
- `HKWorkout.sourceRevision.source.name` → Display as "Logged in [App Name]"

### Duplicate Prevention
Already implemented via `healthWorkoutUUID` matching! Just needs extension to other workout types.

---

## User-Facing Features

### "Where's My MyNetDiary Workout?" Helper
Add a banner/tip in the Runs view:
```
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
ℹ️ Workouts from other apps

Pace & Plates automatically imports workouts
from the Health app, including those logged
in MyNetDiary, Strava, or other fitness apps.

Make sure:
  • Both apps have Health access enabled
  • MyNetDiary is set to write workouts to Health

[Open Health App]  [Settings]
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
```

---

## Privacy & User Control

### Permissions Required
- ✅ HealthKit read access (workouts, distance, energy, routes)
- ✅ HealthKit write access (to save P&P workouts)

### User Controls
- Toggle auto-import on/off
- Choose which workout types to import
- Choose whether to show source app names
- Manual sync button
- Delete local copy vs delete from Health

---

## Expected User Experience

### Scenario: Walking tracked in MyNetDiary
1. User completes 2.5-mile walk in MyNetDiary
2. MyNetDiary writes workout to Apple Health
3. User opens P&P (or P&P running in background)
4. P&P automatically imports the walk within 1-2 minutes
5. Walk appears in Run Log with:
   - 🚶 Walking icon (vs 🏃 running)
   - "Logged in MyNetDiary" badge
   - All stats: distance, duration, calories, map (if available)
6. User can view details, add notes, or delete

### Scenario: Manual entry fallback
1. User realizes a workout didn't import
2. Taps "+" → "Add Past Workout"
3. Selects "Walk" as type
4. Enters date/time, distance (2.5 mi), duration (45 min)
5. Adds note: "Morning walk with Mom"
6. Saves → Appears in log immediately

---

## Comparison: Other Fitness App Integrations

| App | HealthKit Support | Direct Integration Possible? |
|-----|-------------------|------------------------------|
| **MyNetDiary** | ✅ Yes | Via HealthKit only |
| Strava | ✅ Yes | Via HealthKit (recommended) |
| Nike Run Club | ✅ Yes | Via HealthKit only |
| Fitbit | ✅ Yes (with sync) | Via HealthKit |
| Garmin Connect | ✅ Yes | Via HealthKit |
| MapMyRun | ✅ Yes | Via HealthKit |
| Peloton | ✅ Yes | Via HealthKit |

**Key Insight:** HealthKit is the universal standard. Any app that writes workouts to Health will automatically work with P&P once we expand workout type support.

---

## Conclusion & Recommendation

### ✅ Best Approach: Hybrid (Option 3)
1. **Phase 1 Priority:** Enhance HealthKit import to include walking workouts
   - This will make MyNetDiary integration work automatically
   - Benefits ALL apps that use HealthKit
   - Minimal development effort (mostly already built)

2. **Phase 2 Priority:** Add manual entry feature
   - Safety net for edge cases
   - Gives users full control
   - Useful for historical data entry

### Why This Works Best for Your Mom's Use Case
- ✅ She can continue using MyNetDiary as her primary walking tracker
- ✅ P&P will automatically show her walks without extra effort
- ✅ She gets the benefit of P&P's weather integration and beautiful UI
- ✅ If something doesn't sync, she has the manual entry fallback
- ✅ All her walking data stays in one place (Health app) as source of truth

### Next Steps
1. Review this plan and confirm the approach
2. Implement Phase 1 (HealthKit walking import) - Quick win!
3. Test with real MyNetDiary data
4. Implement Phase 2 (manual entry) for completeness
5. Document the integration in your app's help/tutorial

---

## Questions to Consider
1. **Activity types:** Should we also import cycling, swimming, yoga, etc.?
2. **Naming:** Keep "Runs" screen name or rename to "Activity Log" / "Workouts"?
3. **Calories:** Trust imported calorie data or recalculate based on P&P's formula?
4. **Route data:** Some apps don't include GPS routes - handle gracefully?
5. **Chart visualization:** Should walks appear in the same chart as runs, or separate?

---

*Generated for Pace & Plates - MyNetDiary Integration*
*Date: October 29, 2025*

