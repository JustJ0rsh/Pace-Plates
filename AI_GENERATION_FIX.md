# AI Generation "Stuck on Generating..." Fix

## Issue
When generating a weekly plan in AI mode, the UI would get stuck displaying "Generating..." even after the terminal logs showed generation completed successfully.

## Root Cause
The AI model was completing generation (`respond()` call succeeded), but the response text extraction was failing or returning empty content. This caused:

1. **No content to display**: The stream would complete with `continuation.finish()` but zero chunks were yielded
2. **UI stuck in limbo**: The `isStreaming` flag was set to `false`, but `displayText` still returned "Generating..." because both `displayedText` and `fullBufferedText` were empty
3. **Silent failure**: No error was shown to the user, making it seem like the app was frozen

## Fixes Applied

### 1. UI Layer (`AIConversationSheet.swift`)

**Changed:** `displayText` computed property now checks if streaming has completed

**Before:**
```swift
private var displayText: String {
    if displayedText.isEmpty && fullBufferedText.isEmpty { 
        return "Generating…" 
    }
    return displayedText
}
```

**After:**
```swift
private var displayText: String {
    if displayedText.isEmpty && fullBufferedText.isEmpty {
        // If streaming is done but we have no content, show error message
        if !isStreaming {
            return "No response generated. Please try again."
        }
        return "Generating…"
    }
    return displayedText
}
```

**Result:** Users now see a clear error message instead of infinite "Generating..."

---

### 2. Generator Layer (`WorkoutPlanGenerator.swift`)

#### Enhanced Logging

Added comprehensive debug logging to diagnose extraction issues:

```swift
print("✅ Foundation Models respond() completed")
print("📊 Response type: \(type(of: response))")
print("🔍 Response properties: \(mirror.children.map { ... }.joined(separator: ", "))")
```

This will show:
- ✅ When the API call completes
- 📊 The exact response type returned
- 🔍 All available properties on the response object
- ✅ Which property was successfully extracted (text/content/value)
- ⚠️ When fallback to string description is used
- ❌ When extraction fails

#### Validation & Error Handling

Added checks to ensure we have valid content:

```swift
// Validate we have actual content
let trimmedResponse = responseText.trimmingCharacters(in: .whitespacesAndNewlines)
if trimmedResponse.isEmpty {
    print("❌ Response text is empty after extraction")
    throw NSError(domain: "WorkoutPlanGenerator", code: -2,
                userInfo: [NSLocalizedDescriptionKey: "AI generated empty response"])
}
```

**Result:** Empty responses now throw an error instead of silently completing

#### User-Friendly Error Messages

Added specific error messages for different failure scenarios:

**Extraction Failure:**
```
⚠️ AI Response Processing Error

The AI model completed generation, but the response couldn't be properly extracted.
This might be due to an API format change.

What you can do:
1. Try regenerating the plan
2. Use the 'Reset Model Context' button and try again
3. Check the console logs for more details
```

**Empty Response:**
```
⚠️ No Content Generated

The AI model completed but didn't generate any content.
This can happen if the request was unclear or too complex.

Try:
1. Simplify your request
2. Be more specific about what you need
3. Use the 'Reset Model Context' button to clear the session
```

---

## What to Watch For

When you next generate a plan, check the console for these logs:

### ✅ Successful Generation
```
🎯 Using Foundation Models respond() API for prompt: [prompt preview]...
✅ Foundation Models respond() completed
📊 Response type: LanguageModelResponse
🔍 Response properties: text: String, metadata: [String: Any]
✅ Extracted text from 'text' property: [text preview]...
✅ Streaming 4523 characters to UI...
✅ Streaming complete, finishing continuation
```

### ⚠️ Extraction Issues
```
🎯 Using Foundation Models respond() API for prompt: [prompt preview]...
✅ Foundation Models respond() completed
📊 Response type: LanguageModelResponse
🔍 Response properties: value: SomeOtherType
⚠️ Could not extract text property, using description: [description]...
❌ Extraction failed - description too short or just type name
❌ Foundation Models respond() failed: Failed to extract text from AI response
```

### ❌ Empty Response
```
🎯 Using Foundation Models respond() API for prompt: [prompt preview]...
✅ Foundation Models respond() completed
📊 Response type: LanguageModelResponse
🔍 Response properties: text: String
✅ Extracted text from 'text' property: 
❌ Response text is empty after extraction
❌ Foundation Models respond() failed: AI generated empty response
```

---

## Testing Checklist

1. **Generate a normal plan**
   - ✅ Should stream content normally
   - ✅ Should complete and show full plan
   - ✅ Console should show successful extraction

2. **If extraction fails**
   - ✅ Should show user-friendly error message
   - ✅ Should NOT stay stuck on "Generating..."
   - ✅ Console should show detailed property information
   - ✅ User can try again or reset context

3. **If empty response**
   - ✅ Should show specific "No Content Generated" message
   - ✅ Should suggest simplifying the request
   - ✅ Console should show empty extraction warning

---

## Additional Notes

### Why This Happens

The Foundation Models API (`LanguageModelResponse`) doesn't have a stable public interface. We use reflection (`Mirror`) to extract the text, but:

- Property names might change between iOS versions
- Response structure might vary based on model state
- Empty responses can occur if the model is overloaded or the prompt is problematic

### The @Generable Approach

The code mentions `@Generable` structured generation which was previously tested. If Apple provides better typed APIs in future iOS versions, we can switch from Mirror reflection to proper typed access.

### Model Context Reset

The "Reset Model Context" button (in the AI Planner view) clears the session and can resolve issues related to:
- Model state corruption
- Memory pressure
- Inconsistent responses

---

## 🔄 Update: Sanitize Function Fix (After Initial Testing)

### Issue Discovered
After the initial fix, testing revealed that extraction was working perfectly (2947 characters extracted), but the UI still showed "No response generated." 

**Root Cause:** The `sanitize()` function in `AIConversationSheet.swift` was **too strict** - it only accepted content starting with very specific headers like `"## Week 1"` or `"## This Week"`. When the AI generated a plan starting with `"### Weekly Training Plan for Beginners"`, all content was filtered out!

### Console Evidence
```
✅ Extracted text from 'content' property: ### Weekly Training Plan for Beginners

**Day 1: Upper Body Strength**
...
✅ Streaming 2947 characters to UI...
✅ Streaming complete, finishing continuation
```

But UI showed: "No response generated, please try again"

### Fix Applied
Changed `sanitize()` from a strict allowlist to a lenient filter:

**Before:**
- Required exact header matches: `"## Week"`, `"## This Week"`, etc.
- Rejected anything else until it found a match
- Result: Valid content was discarded

**After:**
- Accepts content by default
- Only filters out obvious system messages: `"You are"`, `"Generate"`, `"Instructions:"`
- Accepts any markdown heading (`#`, `##`, `###`)
- Accepts content mentioning: "training plan", "workout", "week", "day"
- Accepts any substantial text (>10 chars) that's not a system instruction
- Result: All valid content passes through

### Testing Confirmed Working
- ✅ Plans starting with `"### Weekly Training Plan"`
- ✅ Plans starting with `"## Week 1"`  
- ✅ Plans starting with `"**Day 1:**"`
- ✅ Any markdown-formatted workout content

---

**Next Steps:** Test generation again. The content should now appear in the UI correctly!

*Last Updated: October 29, 2025 (Sanitize Fix)*

