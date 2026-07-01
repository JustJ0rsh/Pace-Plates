# Live Activity Setup Instructions

## Overview
Live Activities will display real-time running stats (time, pace, distance) on the Lock Screen and Dynamic Island during active runs/walks.

## ✅ Already Completed
- ✅ Added `NSSupportsLiveActivities` to Info.plist
- ✅ Enhanced `LiveActivityManager` with formatted data
- ✅ Created `RunningLiveActivityWidget.swift` widget file
- ✅ Live Activity starts/updates/ends in `RunTrackingView`

## 🔧 Manual Setup Required (Xcode)

### Step 1: Create Widget Extension Target

1. **Open Xcode Project**
   - Open `Pace & Plates.xcodeproj`

2. **Add Widget Extension**
   - File → New → Target
   - Select "Widget Extension"
   - Click "Next"

3. **Configure Widget**
   - Product Name: `RunningWidget`
   - Include Configuration Intent: **Unchecked** (not needed)
   - Click "Finish"
   - When prompted "Activate RunningWidget scheme?" → Click "Activate"

### Step 2: Replace Widget Files

1. **Delete Default Files**
   - In the `RunningWidget` folder, delete:
     - `RunningWidget.swift` (default generated file)
     - `RunningWidgetBundle.swift` (default generated file)

2. **Add Your Widget File**
   - Drag `RunningLiveActivityWidget.swift` into the `RunningWidget` target folder
   - Make sure it's added to the `RunningWidget` target (check Target Membership)

### Step 3: Configure Widget Target

1. **Update Info.plist**
   - Select `RunningWidget` target
   - Go to Info tab
   - Add these keys if not present:
     ```
     NSSupportsLiveActivities: YES
     NSSupportsLiveActivitiesFrequentUpdates: YES
     ```

2. **Set Deployment Target**
   - Select `RunningWidget` target
   - General tab
   - Set "Minimum Deployments" to **iOS 16.1** or higher

3. **Configure App Groups (for sharing data)**
   - Select `RunningWidget` target
   - Signing & Capabilities
   - Click "+ Capability"
   - Add "App Groups"
   - Enable the same app group as your main app (e.g., `group.com.workingout.jorsh`)

### Step 4: Build & Run

1. **Select Main App Scheme**
   - In Xcode toolbar, select "WorkingOut" scheme (not RunningWidget)

2. **Build Project**
   - Cmd+B to build

3. **Run on Device**
   - ⚠️ **Live Activities only work on physical devices, NOT simulator**
   - Select your iPhone as the destination
   - Cmd+R to run

### Step 5: Test Live Activity

1. **Start a Run**
   - Open the app
   - Go to "Runs" tab
   - Tap "+" to track a run
   - Tap "Start"

2. **Check Live Activity**
   - **Lock Screen**: Press home/lock button → Should see Live Activity banner
   - **Dynamic Island (iPhone 14 Pro+)**: Should see running indicator in Dynamic Island
   - **Expanded View**: Long-press Dynamic Island to see full stats

3. **Verify Live Updates**
   - Live Activity should update every second showing:
     - ⏱️ **Duration** (00:00 format)
     - 📍 **Distance** (in km or mi)
     - ⚡ **Pace** (min/km or min/mi)

## 📱 Live Activity UI Features

### Lock Screen View
Shows three main stats in a card:
- **Distance**: Large number with unit
- **Time**: Duration in HH:MM:SS or MM:SS format
- **Pace**: Current pace per unit
- **Live Indicator**: Red dot + "LIVE" text

### Dynamic Island (iPhone 14 Pro+)

**Compact View** (collapsed):
- Left: Running icon (green)
- Right: Duration time

**Minimal View** (when multiple activities):
- Just the running icon

**Expanded View** (long-press):
- **Left**: Distance with icon
- **Center**: Duration (large)
- **Right**: Pace with icon
- **Bottom**: Running status + LIVE indicator

## 🐛 Troubleshooting

### Live Activity Not Showing?

1. **Check Settings**
   - Settings → Pace & Plates
   - Ensure "Live Activities" is enabled

2. **Device Requirements**
   - Must use **physical iPhone** (not simulator)
   - iOS 16.1 or later
   - Live Activities enabled in Settings

3. **Check Console Logs**
   - Look for these messages:
     - ✅ "Live Activity started successfully"
     - ⚠️ "Live Activities are not enabled"
     - ❌ "Failed to start Live Activity"

4. **Rebuild Project**
   - Clean build folder: Cmd+Shift+K
   - Rebuild: Cmd+B
   - Run on device: Cmd+R

### Live Activity Not Updating?

1. **Check Timer**
   - Timer updates every 1 second in `RunTracker.startTimer()`
   - Should call `LiveActivityManager.shared.update(...)` each second

2. **Verify Update Calls**
   - Add breakpoint in `LiveActivityManager.update()`
   - Should be called every second while running

3. **Check Frequent Updates Permission**
   - Ensure `NSSupportsLiveActivitiesFrequentUpdates` is `YES` in Info.plist

## 🎨 Customization

To customize the Live Activity appearance, edit `RunningLiveActivityWidget.swift`:

- **Colors**: Change `.foregroundColor(.green)` to your brand color
- **Fonts**: Adjust `.font(.title)` sizes
- **Layout**: Modify VStack/HStack arrangements
- **Icons**: Change SF Symbol icons (e.g., `figure.run` → `figure.walk`)

## 📝 Technical Details

### Data Flow
```
RunTracker.startRun()
    ↓
LiveActivityManager.start()
    ↓
Creates Live Activity with initial state
    ↓
Timer fires every 1 second
    ↓
LiveActivityManager.update()
    ↓
Live Activity UI updates on Lock Screen/Dynamic Island
    ↓
User stops run
    ↓
LiveActivityManager.end()
    ↓
Live Activity dismissed
```

### State Updates
The `RunningActivityAttributes.ContentState` contains:
- `startDate: Date` - When run started
- `duration: TimeInterval` - Elapsed time in seconds
- `distanceMeters: Double` - Distance in meters
- `paceSecondsPerUnit: Double?` - Pace (seconds per km/mi)
- `distanceUnit: String` - "km" or "mi"

Computed properties format these for display:
- `formattedDuration` → "00:15:42"
- `formattedDistance` → "2.34"
- `formattedPace` → "5:23"

### Performance
- Updates sent every 1 second (high frequency)
- Enabled by `NSSupportsLiveActivitiesFrequentUpdates`
- ActivityKit batches updates efficiently
- No impact on battery during active run

## ✅ Expected Behavior

When working correctly:

1. **Start Run** → Live Activity appears immediately
2. **During Run** → Stats update every second
3. **Lock Phone** → Activity visible on Lock Screen
4. **Unlock Phone** → Activity still visible (can tap to open app)
5. **Stop Run** → Activity dismisses with final stats
6. **Dynamic Island** → Glanceable stats without opening app

---

*Last Updated: October 29, 2025*

