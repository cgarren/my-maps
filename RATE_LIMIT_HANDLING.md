# Rate Limit & Quota Handling

## Overview

Comprehensive rate limit and quota handling for the Gemini API integration, including intelligent error detection, user-friendly messaging, and real-time progress tracking.

## The Problem

Gemini API has rate limits and quotas:
- **Free tier**: 10 requests per minute
- **Rate limits**: HTTP 429 errors
- **Quota exceeded**: Specific error messages with retry delays

Example error:
```
You exceeded your current quota, please check your plan and billing details.
Quota exceeded for metric: generativelanguage.googleapis.com/generate_content_free_tier_requests, limit: 10
Please retry in 25.032949621s.
```

## Solution

### 1. Error Classification

**New error types in `GeminiPlaceGenerator.GeminiError`:**

```swift
enum GeminiError: Error {
    case rateLimited(retryAfter: TimeInterval?)
    case quotaExceeded(retryAfter: TimeInterval?)
    // ... other errors
    
    var localizedDescription: String {
        // User-friendly messages for each error type
    }
}
```

**Intelligent classification:**
- Detects "quota exceeded" or "rate limit" in error messages
- Parses retry delay from messages (e.g., "retry in 25.032949621s")
- Handles HTTP 429 status codes
- Falls back to generic error handling

### 2. Retry Delay Parsing

**Regex-based extraction:**
```swift
private static func parseRetryDelay(from message: String) -> TimeInterval? {
    // Pattern: "retry in 25.032949621s" or "retry in 25s"
    let pattern = "retry in ([0-9.]+)s"
    // ... extract and return TimeInterval
}
```

**Benefits:**
- Tells user exactly how long to wait
- More helpful than generic "try again later"
- Uses Gemini's own recommendation

### 3. Progress Tracking

**New `GenerationProgress` struct:**
```swift
struct GenerationProgress {
    let currentTurn: Int          // Current conversation turn (1-20)
    let maxTurns: Int             // Maximum turns (20)
    let verifiedPlacesCount: Int  // Places verified so far
    let currentActivity: String   // e.g., "Verifying Blue Bottle Coffee..."
}
```

**Progress callbacks throughout generation:**
1. "Starting generation..." (initial)
2. "Processing request..." (each turn)
3. "Verifying [Place Name]..." (during tool call)
4. "Verified [Place Name]" (after successful verification)
5. "Completed! Found N places" (final)

### 4. UI Integration

**Real-time progress display:**
```swift
if isGenerating {
    HStack {
        ProgressView()
        Text(generationProgress)  // "Verifying Blue Bottle Coffee..."
    }
    
    if verifiedCount > 0 {
        Text("Verified \(verifiedCount) places so far")
    }
}
```

**Features:**
- ✅ Text input disabled during generation
- ✅ Live progress updates
- ✅ Verified place counter
- ✅ Estimated time ("This may take 20-30 seconds")
- ✅ User-friendly error alerts

### 5. Error Messages

**Rate Limited:**
```
Rate limited. Please wait 25 seconds before trying again.
```

**Quota Exceeded:**
```
API quota exceeded. Please retry in 25 seconds, or check your API plan at ai.google.dev.
```

**No API Key:**
```
No API key configured. Please add your Gemini API key in settings.
```

**Network Error:**
```
Network error. Please check your internet connection and try again.
```

## Implementation Details

### GeminiPlaceGenerator.swift

**1. Error Classification Function:**
```swift
private static func classifyAPIError(_ message: String) -> GeminiError {
    let lowercased = message.lowercased()
    
    // Check for quota exceeded
    if lowercased.contains("quota exceeded") || lowercased.contains("quota_exceeded") {
        let retryDelay = parseRetryDelay(from: message)
        return .quotaExceeded(retryAfter: retryDelay)
    }
    
    // Check for rate limit
    if lowercased.contains("rate limit") || lowercased.contains("too many requests") {
        let retryDelay = parseRetryDelay(from: message)
        return .rateLimited(retryAfter: retryDelay)
    }
    
    return .apiError(message)
}
```

**2. Progress Reporting:**
```swift
// At start
progressHandler?(GenerationProgress(
    currentTurn: 0,
    maxTurns: 20,
    verifiedPlacesCount: 0,
    currentActivity: "Starting generation..."
))

// During verification
progressHandler?(GenerationProgress(
    currentTurn: currentTurn,
    maxTurns: maxTurns,
    verifiedPlacesCount: verifiedPlacesCount,
    currentActivity: "Verifying \(locationName)..."
))

// After verification
verifiedPlacesCount += 1
progressHandler?(GenerationProgress(
    currentTurn: currentTurn,
    maxTurns: maxTurns,
    verifiedPlacesCount: verifiedPlacesCount,
    currentActivity: "Verified \(result.name)"
))
```

### NewMapSheet.swift

**1. State Management:**
```swift
@State private var generationProgress: String = ""
@State private var verifiedCount: Int = 0
@State private var showErrorAlert: Bool = false
@State private var errorMessage: String = ""
```

**2. Progress Handler:**
```swift
(places, usedPCC) = try await GeminiPlaceGenerator.generatePlaces(
    userPrompt: trimmed,
    maxCount: 20,
    progressHandler: { progress in
        generationProgress = progress.currentActivity
        verifiedCount = progress.verifiedPlacesCount
    }
)
```

**3. Error Handling:**
```swift
catch let error as GeminiPlaceGenerator.GeminiError {
    switch error {
    case .rateLimited(let retryAfter):
        if let delay = retryAfter {
            errorMessage = "Rate limited. Please wait \(Int(delay)) seconds..."
        }
    case .quotaExceeded(let retryAfter):
        if let delay = retryAfter {
            errorMessage = "API quota exceeded. Please retry in \(Int(delay)) seconds..."
        }
    // ... other cases
    }
    showErrorAlert = true
}
```

## User Experience

### Before (No Progress or Error Handling)
```
User: Clicks "Generate"
App: Shows spinning indicator
... waits ...
... waits ...
Error: "API error: [long technical message]"
User: 😕 What happened? How long should I wait?
```

### After (With Progress & Error Handling)
```
User: Clicks "Generate"
App: Shows "Starting generation..."
App: Shows "Verifying Blue Bottle Coffee..."
App: Shows "Verified 3 places so far"
App: Shows "Verifying Summer Moon Coffee..."
Error: "Rate limited. Please wait 25 seconds before trying again."
User: ✅ Clear message, knows exactly what to do
```

## Testing

### Test 1: Rate Limit Error
1. Make 10+ requests quickly
2. Trigger rate limit
3. Verify error message shows retry delay
4. Wait specified time and retry
5. Should succeed

### Test 2: Quota Exceeded
1. Exhaust API quota
2. Trigger quota error
3. Verify message shows:
   - Retry delay
   - Link to ai.google.dev
4. User knows to check billing

### Test 3: Progress Tracking
1. Generate places (e.g., "coffee shops in Austin")
2. Watch console logs
3. UI should show:
   - "Verifying [Place 1]..."
   - "Verified 1 places so far"
   - "Verifying [Place 2]..."
   - "Verified 2 places so far"
   - etc.

### Test 4: Input Disabled
1. Start generation
2. Try to edit text field
3. Text field should be disabled
4. Generate button should show progress indicator
5. After completion/error, re-enabled

## Console Output

**With Progress Tracking:**
```
🔄 [Gemini] Starting place generation with tool calling...
🔄 [Gemini] Turn 1/20
🔧 [Gemini] Called function: search_location with args: ["location_name": "Blue Bottle Coffee Austin"]
🔧 [searchLocation(locationName:)] Tool called with input: "Blue Bottle Coffee Austin"
✅ [searchLocation(locationName:)] Found: "Blue Bottle Coffee" at 315 Linden Street, Austin, TX, 78704, United States
✅ [Gemini] Location found: Blue Bottle Coffee at 315 Linden Street, Austin, TX, 78704, United States
🔄 [Gemini] Turn 2/20
🔧 [Gemini] Called function: search_location with args: ["location_name": "Summer Moon Coffee Austin"]
...
📝 [Gemini] Received final response
✅ [Gemini] Successfully parsed 10 places
```

**With Rate Limit Error:**
```
🔄 [Gemini] Turn 11/20
🔧 [Gemini] Called function: search_location with args: ["location_name": "Oak Long Bar + Kitchen Boston"]
AI generation failed: API quota exceeded. Please retry in 25 seconds, or check your API plan at ai.google.dev.
```

## API Limits (Gemini Free Tier)

| Metric                  | Limit           |
| ----------------------- | --------------- |
| **Requests Per Minute** | 10 RPM          |
| **Tokens Per Minute**   | Varies by model |
| **Requests Per Day**    | Varies          |

**Our Usage:**
- Each place generation = 1 initial request + N tool calls
- For 10 places ≈ 11-15 total requests (multi-turn conversation)
- Can easily hit 10 RPM limit with tool calling

**Solutions:**
1. ✅ Parse retry delay and show to user
2. ✅ User-friendly error messages
3. ⚠️ Consider caching verified places (future)
4. ⚠️ Upgrade to paid tier for higher limits

## Benefits

### For Users
1. ✅ **Know what's happening** - Real-time progress updates
2. ✅ **Know how long to wait** - Exact retry delays
3. ✅ **Clear error messages** - No technical jargon
4. ✅ **Can't interrupt** - Input disabled during generation
5. ✅ **See progress** - "Verified 5 places so far"

### For Developers
1. ✅ **Intelligent error handling** - Automatic error classification
2. ✅ **Detailed logging** - Easy debugging
3. ✅ **Type-safe errors** - Swift enum for error handling
4. ✅ **Extensible** - Easy to add new error types
5. ✅ **Testable** - Clear error states

## Future Enhancements

### 1. Exponential Backoff (Auto-retry)
```swift
var retryCount = 0
let maxRetries = 3

while retryCount < maxRetries {
    do {
        return try await generatePlaces(...)
    } catch .rateLimited(let delay) {
        retryCount += 1
        let backoff = delay ?? (pow(2.0, Double(retryCount)))
        await Task.sleep(nanoseconds: UInt64(backoff * 1_000_000_000))
    }
}
```

### 2. Result Caching
```swift
private static var placeCache: [String: [TemplatePlace]] = [:]

// Check cache before making API call
if let cached = placeCache[cacheKey] {
    return (cached, false)
}
```

### 3. Rate Limit Prediction
```swift
private static var requestTimes: [Date] = []

func canMakeRequest() -> Bool {
    // Check if we're close to rate limit
    let recentRequests = requestTimes.filter { 
        $0.timeIntervalSinceNow > -60 
    }
    return recentRequests.count < 9 // Leave buffer
}
```

### 4. Analytics
```swift
// Track error rates
struct ErrorMetrics {
    var rateLimitCount: Int = 0
    var quotaExceededCount: Int = 0
    var successCount: Int = 0
}
```

## Comparison: Before vs After

| Aspect                   | Before               | After                          |
| ------------------------ | -------------------- | ------------------------------ |
| **Error Messages**       | Technical API errors | User-friendly messages         |
| **Retry Guidance**       | "Try again later"    | "Wait 25 seconds"              |
| **Progress Visibility**  | None                 | Real-time updates              |
| **Input State**          | Always enabled       | Disabled during generation     |
| **Verified Count**       | Unknown              | "Verified 5 places so far"     |
| **Error Classification** | Generic              | Specific (rate limit vs quota) |
| **User Experience**      | Confusing            | Clear and informative          |

## Conclusion

**This implementation provides:**
- ✅ Intelligent error detection and classification
- ✅ User-friendly error messages with actionable guidance
- ✅ Real-time progress tracking
- ✅ Disabled input during generation
- ✅ Parsed retry delays from API responses
- ✅ Type-safe error handling
- ✅ Comprehensive logging

**Result:** Users know exactly what's happening and what to do when errors occur!

---

**Status:** ✅ Fully Implemented  
**Testing:** Ready for production  
**User Experience:** Dramatically improved  
**Documentation:** Complete

