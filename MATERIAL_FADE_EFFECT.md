# Material Background Fade Effect

## Overview
Implemented Apple's native Material background system with gradient masking to create clean, system-integrated scroll fade effects in AI views.

---

## What is a Material Background?

From Apple's documentation:

> **Material background** — a visual effect that applies system blur and vibrancy.

Materials automatically:
- ✅ Blur content behind them
- ✅ Apply vibrancy effects (text/icons adapt)
- ✅ Integrate with system Dark/Light mode
- ✅ Match iOS native appearance
- ✅ Provide depth and hierarchy

---

## Implementation

### Simple Structure
```swift
Rectangle()
    .fill(.regularMaterial)  // System blur + vibrancy
    .mask(
        LinearGradient(...)  // Shape the material with fade
    )
```

### Why This Works Better

**Previous Approach (Custom):**
- ❌ ZStack with multiple layers
- ❌ Manual color overlays
- ❌ Hard-coded background colors
- ❌ Doesn't adapt to system modes
- ❌ More code, more complexity

**Material Approach (Apple):**
- ✅ Single `Rectangle` with `.regularMaterial`
- ✅ System handles blur and vibrancy
- ✅ Auto-adapts to Dark/Light mode
- ✅ Native iOS look and feel
- ✅ Cleaner, less code

---

## Material Types Available

Apple provides different material intensities:

| Material | Blur Intensity | Use Case |
|----------|---------------|----------|
| `.ultraThinMaterial` | Very light | Subtle overlays |
| `.thinMaterial` | Light | Minimal separation |
| **`.regularMaterial`** | **Medium** | **General UI (our choice)** |
| `.thickMaterial` | Heavy | Strong separation |
| `.ultraThickMaterial` | Very heavy | Maximum depth |

We use **`.regularMaterial`** for balanced blur that works well over content.

---

## Gradient Mask

The gradient mask shapes the material into a fade effect:

### Top Fade (120pt)
```swift
LinearGradient(
    stops: [
        .init(color: .black, location: 0.0),      // 0%:  Fully visible material
        .init(color: .black.opacity(0.9), location: 0.05),
        .init(color: .black.opacity(0.7), location: 0.15),
        .init(color: .black.opacity(0.4), location: 0.35),
        .init(color: .black.opacity(0.15), location: 0.5),
        .init(color: .clear, location: 0.65)       // 65%: Invisible
    ],
    startPoint: .top,
    endPoint: .bottom
)
```

**Visualization:**
```
Top of screen
┌─────────────────────┐
│ ████████████████████ │ ← 0%:  Solid material (full blur)
│ ▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓ │ ← 5%:  90% material
│ ▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒ │ ← 15%: 70% material
│ ░░░░░░░░░░░░░░░░░░░░ │ ← 35%: 40% material
│ ····················· │ ← 50%: 15% material
│                      │ ← 65%: Invisible (content shows)
│   [Scrollable        │
│    Content]          │
```

### Bottom Fade (120pt)
```swift
LinearGradient(
    stops: [
        .init(color: .clear, location: 0.35),      // 35%: Invisible
        .init(color: .black.opacity(0.15), location: 0.5),
        .init(color: .black.opacity(0.4), location: 0.65),
        .init(color: .black.opacity(0.7), location: 0.85),
        .init(color: .black.opacity(0.9), location: 0.95),
        .init(color: .black, location: 1.0)        // 100%: Fully visible material
    ],
    startPoint: .top,
    endPoint: .bottom
)
```

---

## Conditional Visibility

The fade only appears when content exists:

```swift
@State private var showScrollFades: Bool = false

// Shows fades after content loads
.background(GeometryReader { geo in
    Color.clear.onAppear {
        DispatchQueue.main.async {
            showScrollFades = true
        }
    }
})
```

**Result:**
- Empty view → No fades (clean)
- Content appears → Fades smoothly animate in (`.transition(.opacity)`)

---

## Applied To

### 1. AIConversationSheet.swift
**Purpose:** Weekly training plan display

**Trigger:** Content appears in ScrollView

**Effect:** Material fades blur/fade the workout plan text

### 2. AIChatSheet.swift
**Purpose:** AI chat messages

**Trigger:** First message is sent (`messages.count > 0`)

**Effect:** Material fades blur/fade the message bubbles

---

## Technical Benefits

### 1. System Integration
- Material automatically matches system appearance
- Dark mode → darker material
- Light mode → lighter material
- Accessibility settings respected

### 2. Performance
- Native SwiftUI effect (hardware accelerated)
- No custom rendering
- Efficient blur implementation
- Minimal CPU/GPU usage

### 3. Vibrancy
Materials support **vibrancy** - text/icons on materials automatically adjust:
- Increased contrast
- Enhanced readability
- Adaptive colors

### 4. Maintenance
- Less custom code = fewer bugs
- Apple handles blur quality
- Automatic updates with iOS versions
- No hard-coded colors

---

## Visual Result

### Before Content Loads
```
┌──────────────────────────┐
│  Header                  │
├──────────────────────────┤
│                          │
│                          │  ← No fades visible
│   [Empty/Generating]     │
│                          │
│                          │
└──────────────────────────┘
```

### After Content Appears
```
┌──────────────────────────┐
│  Header                  │
├──────────────────────────┤
│ ▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓ │ ← Material blur fades in
│ ▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒ │
│ ░░░░░░░░░░░░░░░░░░░░░░░░ │
│ Day 1: Upper Body        │ ← Clear content area
│ - Arnold Press           │
│ - Bench Press            │
│ Day 2: Lower Body        │
│ ░░░░░░░░░░░░░░░░░░░░░░░░ │
│ ▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒ │
│ ▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓ │ ← Material blur fades out
└──────────────────────────┘
```

---

## Customization Options

### Change Material Intensity
```swift
.fill(.ultraThinMaterial)  // Lighter blur
.fill(.thickMaterial)      // Heavier blur
```

### Adjust Fade Height
```swift
.frame(height: 80)   // Shorter fade
.frame(height: 150)  // Longer fade
```

### Modify Gradient Curve
```swift
// Quicker fade (shorter transition)
.init(color: .clear, location: 0.8)  // Fades faster

// Slower fade (longer transition)
.init(color: .clear, location: 0.5)  // Fades gradually
```

---

## Code Comparison

### Before (Complex - 40+ lines per fade)
```swift
ZStack {
    Rectangle()
        .fill(.ultraThickMaterial)
        .mask(gradient1)
    
    LinearGradient(
        colors: [customColor1, customColor2, ...]
    )
}
```

### After (Clean - 10 lines per fade)
```swift
Rectangle()
    .fill(.regularMaterial)
    .mask(
        LinearGradient(...)
    )
```

**Result:** 70% less code, native appearance, better performance.

---

## Testing Checklist

1. ✅ Empty view → No fades visible
2. ✅ Content appears → Fades smoothly animate in
3. ✅ Scroll content → Blur effect visible at edges
4. ✅ Dark mode → Material adapts to dark theme
5. ✅ Light mode → Material adapts to light theme
6. ✅ Touch/scroll → Fades don't block interaction (`.allowsHitTesting(false)`)
7. ✅ Dynamic content → Fades persist through updates

---

## References

- Apple Human Interface Guidelines: Materials
- SwiftUI Documentation: Material Styles
- WWDC: Visual Effects and Blurs
- iOS Design Language: Depth and Hierarchy

---

**Last Updated:** October 29, 2025
**Apple Standard:** Material Background with Gradient Masking

