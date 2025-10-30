# Live Activity Quick Setup Checklist

## ✅ What's Already Done
- [x] Info.plist configured with Live Activity support
- [x] LiveActivityManager enhanced with formatting
- [x] Widget file created (`RunningLiveActivityWidget.swift`)
- [x] Integration code in RunTrackingView

## 🔧 What You Need to Do in Xcode

### 1. Create Widget Extension (5 minutes)

```
File → New → Target
   ↓
Select "Widget Extension"
   ↓
Product Name: "RunningWidget"
Include Configuration Intent: ❌ UNCHECKED
   ↓
Click "Finish" → "Activate"
```

### 2. Replace Widget Files (2 minutes)

**Delete:**
- ❌ `RunningWidget/RunningWidget.swift`
- ❌ `RunningWidget/RunningWidgetBundle.swift`

**Add:**
- ✅ Drag `RunningLiveActivityWidget.swift` → `RunningWidget` folder
- ✅ Check "RunningWidget" target membership

### 3. Configure Target (3 minutes)

**Deployment Target:**
- RunningWidget target → General → iOS 16.1+

**App Groups:**
- RunningWidget target → Signing & Capabilities
- Add "App Groups" capability
- Enable: `group.com.workingout.jorsh` (same as main app)

### 4. Build & Test (On Real iPhone!)

```
⚠️ IMPORTANT: Simulator doesn't support Live Activities
```

1. Select **"WorkingOut"** scheme (not RunningWidget)
2. Select your **iPhone** as destination
3. Build & Run (Cmd+R)
4. Start a run → Lock phone → See Live Activity! 🎉

---

## 🎯 What You'll See

### Lock Screen
```
┌────────────────────────────┐
│ 🏃 Active Run         🔴 LIVE │
├────────────────────────────┤
│                            │
│  Distance    Time    Pace  │
│   2.34 km   15:42   5:23   │
│                            │
└────────────────────────────┘
```

### Dynamic Island (iPhone 14 Pro+)
```
Compact:  🏃 [  •••  ] 15:42

Expanded (long-press):
┌────────────────────────┐
│      Active Run        │
│       15:42            │  ← Large timer
│                        │
│ Distance  |  Pace      │
│  2.34 km  | 5:23/km    │
│                        │
│ 🏃 Running    🔴 LIVE  │
└────────────────────────┘
```

---

## 🐛 Troubleshooting

**Not showing?**
- Settings → Pace & Plates → Enable Live Activities
- Use physical iPhone (not simulator)
- Check console for "✅ Live Activity started"

**Not updating?**
- Verify Info.plist has `NSSupportsLiveActivitiesFrequentUpdates = YES`
- Check timer is running (you should see time updating in app)

---

## 📞 Need Help?

See `LIVE_ACTIVITY_SETUP.md` for detailed instructions and troubleshooting.

---

**Estimated Setup Time: 10 minutes**
**Result: Live running stats on Lock Screen & Dynamic Island** 🚀

