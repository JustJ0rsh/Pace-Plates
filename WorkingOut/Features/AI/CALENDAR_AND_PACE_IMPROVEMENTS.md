# Calendar Scheduling & Pace Accuracy Improvements

## Summary

Added calendar scheduling for workout plans with automatic reminders, improved markdown formatting in history view, and enhanced running pace accuracy throughout the AI system.

---

## 1. Calendar Scheduling 📅

**New File:** `WorkingOut/Services/WorkoutCalendarService.swift`

### Features

**Automatic Workout Scheduling:**
- Parses workout plans and creates individual calendar events
- One event per day (Day 1, Day 2, etc.)
- Scheduled starting tomorrow at 8 AM
- 1-hour duration for each workout
- 30-minute reminder before each workout

**Smart Parsing:**
- Detects day headers from multiple markdown formats:
  - `### Day 1: Upper Body`
  - `- Day 1: Leg Day`
  - `Day 1: Cardio`
- Extracts exercise details for event notes
- Cleans markdown formatting for calendar readability

**Access Management:**
- Requests calendar permissions
- Handles iOS 17+ and earlier versions
- Clear error messages
- Opens Settings if permission denied

---

## 2. Calendar Buttons Added 🔘

**File:** `AIHistoryView.swift`

**History View Enhancement:**
- "Add to Calendar" button appears on saved workout plans
- Only shows for workout plans (not Q&A)
- Success/error alerts with haptic feedback
- Links to Settings if calendar access needed

**File:** `AIConversationSheet.swift`

**Plan Generation View:**
- "Schedule" button in navigation bar
- Appears during plan generation
- Disabled while streaming
- Creates temporary conversation object to schedule

**Button Locations:**
```
┌─────────────────────────────────────┐
│ Save    Schedule        Share       │  ← Toolbar buttons
├─────────────────────────────────────┤
│ ## This Week's Training Plan        │
│                                     │
│ Day 1: Upper Body...                │
│ Day 2: Lower Body...                │
└─────────────────────────────────────┘
```

---

## 3. Enhanced Markdown in History 📝

**File:** `AIHistoryView.swift`

### Before vs After

**Before:**
- Plain `Text` component
- No formatting
- Hard to read workout plans
- No citation badges
- Black background only

**After:**
- Uses `MarkdownView` component
- Beautiful formatting with:
  - Proper headings
  - Color-coded bullets
  - Citation badges
  - Code blocks
  - Better spacing
- Glass morphism background
- Gradient overlays
- Border strokes

**Visual Improvements:**
```
Before:
─────────────────────────────
## Day 1: Upper Body
- Bench Press: 3x5 @ 390 lbs
[1] citation text
─────────────────────────────

After:
╔═════════════════════════════╗
║ Day 1: Upper Body           ║
║ • Bench Press: 3x5 @ 390 lbs║
║ [1️⃣] citation badge         ║
╚═════════════════════════════╝
```

---

## 4. Accurate Running Pace 🏃

**File:** `AIPromptBuilder.swift`

### What Changed

**User Pace Integration:**
- AI now receives user's actual average pace
- Calculates from recent runs (HealthKit + app data)
- Displayed prominently in prompts
- Used as baseline for recommendations

**Pace Guidance in Prompts:**
```
RUNNING PACE: User's recent average is 8:30 per mi. Use this as baseline:
- Easy runs: 30-60 seconds slower per mi (9:00-9:30 pace)
- Moderate runs: At or near 8:30 per mi
- Fast/interval runs: 15-30 seconds faster per mi (8:00-8:15 pace)
```

**Format Improvements:**
```swift
// Before:
"- Running: 'Run: X.X mi at [pace]'"

// After (with user data):
"- Running: 'Run: 3.0 mi at 8:30 per mi pace' (use user's actual pace: 8:30 per mi)"

// After (without user data):
"- Running: 'Run: 3.0 mi at easy/moderate pace'"
```

**Prompt Stats Update:**
- Moved pace to end of cardio line for better readability
- Shows: "Cardio: 5 runs, 15.5 mi | Avg pace: 8:30 per mi"
- Clear separation between stats and pace

---

## 5. User Experience Flow 🎯

### Scheduling Workout Plan

**Step 1: Generate or View Plan**
```
User generates workout plan or opens saved plan
```

**Step 2: Click Schedule Button**
```
[Schedule] button in toolbar
        ↓
Requests calendar permission (first time)
        ↓
Parses workout days from markdown
```

**Step 3: Creates Events**
```
Day 1: Upper Body & Core Focus
  📅 Tomorrow, 8:00 AM - 9:00 AM
  🔔 Reminder: 7:30 AM
  📝 Bench Press 3x5 @ 390 lbs...

Day 2: Lower Body & Cardio
  📅 Day after tomorrow, 8:00 AM - 9:00 AM
  🔔 Reminder: 7:30 AM
  📝 Leg Press 3x8 @ 249 lbs...

... continues for all days
```

**Step 4: Success Feedback**
```
✅ Added to Calendar
"Your workout plan has been added to your calendar with reminders."
[OK]
```

### Viewing Saved Plans

**History View:**
```
Saved Conversations
├─ 📅 Workout Plan
│  "Weekly Plan: Lose Goal"
│  Oct 27, 2025
│
├─ 💬 Question  
│  "What are protein benefits?"
│  Oct 26, 2025
```

**Detail View:**
```
┌────────────────────────────────────┐
│ Prompt                             │
│ Weekly Training Plan (Lose Goal)   │
├────────────────────────────────────┤
│ Response (MarkdownView)            │
│                                    │
│ ## This Week's Training Plan       │
│                                    │
│ ### Day 1: Upper Body [1️⃣]        │
│ • Bench Press — 3x5 @ 390 lbs     │
│ • Pull-Ups — 4x8 @ bodyweight     │
│                                    │
│ ### Day 2: Lower Body              │
│ • Leg Press — 3x8 @ 249 lbs       │
│ • Lunges — 4x12 per leg @ 120 lbs │
├────────────────────────────────────┤
│ [📅 Add to Calendar]  [↗️ Share]   │
└────────────────────────────────────┘
```

---

## 6. Technical Implementation

### Calendar Service

```swift
WorkoutCalendarService.shared.scheduleWorkoutPlan(conversation)
```

**Key Methods:**
- `requestAccess()` - Handles iOS 17+ and older
- `scheduleWorkoutPlan()` - Main scheduling function
- `parseWorkoutDays()` - Extracts days from markdown
- `extractDayTitle()` - Regex parsing for multiple formats

**Error Handling:**
- `.accessDenied` - Opens Settings app
- `.calendarNotFound` - No default calendar
- `.failedToParseWorkouts` - Invalid format
- `.failedToCreateEvents` - Calendar save failed

### Pace Calculation

**Source:** `WorkoutPlanGenerator.swift` lines 793-804

```swift
// Calculates average pace from recent runs
let paces = recent.compactMap { workout -> Double? in
    guard let distance = workout.totalDistance?.doubleValue(for: .meter()), 
          distance > 0 else { return nil }
    let duration = workout.duration
    let distanceInUnit = distanceUnit.contains("km") ? 
        distance / 1000.0 : distance / 1609.34
    return duration / 60.0 / distanceInUnit // minutes per unit
}

if !paces.isEmpty {
    let avgPace = paces.reduce(0, +) / Double(paces.count)
    avgRecentPace = formatPace(avgPace, unit: distanceUnit)
}
```

**Format:** `"8:30 per mi"` or `"5:15 per km"`

---

## 7. Files Changed

```
✏️ WorkingOut/Services/WorkoutCalendarService.swift [NEW]
   → Calendar event creation and management
   
✏️ WorkingOut/Features/AI/AIHistoryView.swift
   → Added MarkdownView for better formatting
   → Added calendar button for workout plans
   → Success/error alerts
   
✏️ WorkingOut/Features/AI/AIConversationSheet.swift
   → Added schedule button in toolbar
   → Calendar integration
   → Alert handling
   
✏️ WorkingOut/Services/AIPromptBuilder.swift
   → Running pace integration in prompts
   → Pace guidance (easy/moderate/fast)
   → Better stat formatting

📄 CALENDAR_AND_PACE_IMPROVEMENTS.md [NEW]
   → Full documentation
```

---

## 8. Testing Checklist

### Calendar Scheduling
- [ ] First time: Calendar permission prompt appears
- [ ] Permission granted: Events created successfully
- [ ] Permission denied: Settings alert appears
- [ ] Events appear in default calendar
- [ ] Reminders set 30 minutes before
- [ ] Event times correct (8 AM - 9 AM)
- [ ] Event notes contain workout details
- [ ] Success alert shows with haptic

### Markdown Formatting
- [ ] History view shows formatted markdown
- [ ] Citations appear as blue badges
- [ ] Headings properly styled
- [ ] Bullets use accent color
- [ ] Glass morphism background visible
- [ ] Text is readable and well-spaced

### Running Pace
- [ ] User with recent runs: Pace shown in prompts
- [ ] Pace appears in workout plans
- [ ] Pace recommendations (easy/moderate/fast)
- [ ] User without runs: Generic pace suggestions
- [ ] Pace format correct (MM:SS per unit)
- [ ] Chat responses use accurate pace data

---

## 9. Benefits

### For Users
✅ **Never forget workouts** - Calendar reminders  
✅ **Better readability** - Formatted markdown everywhere  
✅ **Accurate training** - Pace based on actual performance  
✅ **Easy scheduling** - One-tap calendar integration  
✅ **Clear guidance** - Knows when to run easy/hard  

### For Developers
✅ **Clean code** - Reusable calendar service  
✅ **No linter errors** - Well-structured  
✅ **Good UX** - Proper error handling  
✅ **Maintainable** - Centralized prompt building  
✅ **Extensible** - Easy to add more calendar features  

---

## 10. Future Enhancements

**Calendar Features:**
- [ ] Custom workout times (not just 8 AM)
- [ ] Location tagging (gym, track, etc.)
- [ ] Sync with existing calendar events
- [ ] Update/delete scheduled workouts
- [ ] Multiple reminder options

**Pace Features:**
- [ ] Heart rate zone suggestions
- [ ] Pace predictions for distances
- [ ] Training effect estimation
- [ ] Race pace calculator
- [ ] Altitude-adjusted paces

---

*Last Updated: October 27, 2025*

