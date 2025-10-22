# Backward Compatibility Implementation ✅

## Overview

The app now builds and runs on **any iOS/macOS version**, gracefully disabling Foundation Models features when the SDK doesn't support them. This ensures maximum compatibility while still taking advantage of the latest AI capabilities when available.

## Implementation Strategy

### Conditional Compilation with `#if canImport(FoundationModels)`

We use Swift's `canImport` directive to conditionally compile Foundation Models code only when the SDK supports it. This is a **compile-time check** that determines whether the code should be included in the build.

## How It Works

### Two-Layer Protection

**Layer 1: Compile-Time (`#if canImport`)**
- Checks if FoundationModels framework exists in the SDK
- Code is either included or excluded from the binary
- Prevents compiler errors on older SDKs

**Layer 2: Runtime (`#available`)**
- Checks the device's OS version at runtime
- Ensures APIs are only called on compatible devices
- Prevents crashes on older OS versions

## Files Modified

### 1. `LLMAddressExtractor.swift`

**Structure:**
```swift
import Foundation
#if canImport(FoundationModels)
import FoundationModels

// FoundationModels-specific code
@available(iOS 26.0, macOS 26.0, *)
@Generable(description: "...")
struct LLMExtractedAddress { ... }

enum ExtractionError: Error { ... }
#endif

// Always available code
struct LLMAddressExtractor {
    static var isSupported: Bool {
        #if canImport(FoundationModels)
        if #available(iOS 26.0, macOS 26.0, *) {
            // Check model availability
            return SystemLanguageModel.default.availability == .available
        }
        #endif
        return false  // Not available on this SDK/OS
    }
    
    static func extractAddresses(from text: String) async throws -> [ExtractedAddress] {
        #if canImport(FoundationModels)
        // Foundation Models implementation
        guard #available(iOS 26.0, macOS 26.0, *) else {
            throw ExtractionError.unsupportedPlatform
        }
        // ... LLM extraction code ...
        #else
        // Fallback for older SDKs
        print(">>> Foundation Models not available on this SDK")
        return []
        #endif
    }
}
```

**Key Points:**
- `LLMExtractedAddress` struct only exists when FoundationModels is available
- `isSupported` returns `false` when SDK doesn't support FoundationModels
- `extractAddresses` returns empty array on older SDKs (graceful degradation)

### 2. `LLMPlaceGenerator.swift`

**Structure:**
```swift
import Foundation
#if canImport(FoundationModels)
import FoundationModels

@available(iOS 26.0, macOS 26.0, *)
@Generable(description: "...")
struct LLMTemplatePlace { ... }

enum PlaceGenerationError: Error { ... }
#endif

struct LLMPlaceGenerator {
    static var isSupported: Bool {
        #if canImport(FoundationModels)
        if #available(iOS 26.0, macOS 26.0, *) {
            return SystemLanguageModel.default.availability == .available
        }
        #endif
        return false
    }
    
    static func generatePlaces(...) async throws -> ([TemplatePlace], usedPCC: Bool) {
        #if canImport(FoundationModels)
        // Foundation Models implementation
        // ... place generation code ...
        #else
        // Throw error on older SDKs
        throw NSError(domain: "LLMPlaceGenerator", code: -1, userInfo: [
            NSLocalizedDescriptionKey: "Foundation Models not available on this SDK"
        ])
        #endif
    }
}
```

**Key Points:**
- `LLMTemplatePlace` struct only exists when FoundationModels is available
- `isSupported` returns `false` on older SDKs
- `generatePlaces` throws clear error on older SDKs

### 3. `LocationSearchToolFM.swift`

**Structure:**
```swift
import Foundation
#if canImport(FoundationModels)
import FoundationModels
#endif
import MapKit
import CoreLocation

#if canImport(FoundationModels)
@available(iOS 26.0, macOS 26.0, *)
struct LocationSearchToolFM: Tool {
    // Tool implementation
}
#endif
```

**Key Points:**
- Entire struct only exists when FoundationModels is available
- Tool protocol conformance conditional on SDK support
- Clean separation from non-FM code

## Behavior by OS Version

### Scenario 1: Build with iOS 26+ SDK, Run on iOS 26+ Device

**Compile-Time:**
- ✅ `canImport(FoundationModels)` = true
- ✅ Foundation Models code included in binary

**Runtime:**
- ✅ `#available(iOS 26.0, ...)` = true
- ✅ `SystemLanguageModel.default.availability` = `.available`
- ✅ `isSupported` = true

**Result:** Full Foundation Models functionality ✅

### Scenario 2: Build with iOS 26+ SDK, Run on iOS 25 Device

**Compile-Time:**
- ✅ `canImport(FoundationModels)` = true
- ✅ Foundation Models code included in binary

**Runtime:**
- ❌ `#available(iOS 26.0, ...)` = false
- ❌ `isSupported` = false

**Result:** Feature disabled, Gemini available as alternative ✅

### Scenario 3: Build with iOS 25 SDK, Run on iOS 25 Device

**Compile-Time:**
- ❌ `canImport(FoundationModels)` = false
- ❌ Foundation Models code excluded from binary

**Runtime:**
- ❌ `isSupported` = false (returns false in `#else` branch)

**Result:** Feature disabled, Gemini available as alternative ✅

### Scenario 4: Build with iOS 25 SDK, Run on iOS 26 Device ⚠️

**Compile-Time:**
- ❌ `canImport(FoundationModels)` = false
- ❌ Foundation Models code excluded from binary

**Runtime:**
- ❌ `isSupported` = false (code not in binary)

**Result:** Feature disabled even though device supports it ⚠️

**Note:** To enable features on iOS 26 devices, must rebuild with iOS 26+ SDK.

## UI Integration

### Provider Availability

The `AIProvider` enum automatically reflects availability:

```swift
var isAvailable: Bool {
    switch self {
    case .appleFM:
        return LLMPlaceGenerator.isSupported  // Returns false on old SDK/OS
    case .gemini:
        return GeminiPlaceGenerator.isConfigured
    }
}
```

**Result:**
- On older SDKs/OS: Apple Intelligence shows as unavailable
- Gemini remains available as alternative
- UI gracefully adapts

## Benefits

### For Users

1. ✅ **App works on older devices** - No crashes or errors
2. ✅ **Graceful degradation** - Features disabled, not broken
3. ✅ **Clear messaging** - UI explains why feature unavailable
4. ✅ **Alternative available** - Gemini works on all versions

### For Developers

1. ✅ **Single codebase** - No separate builds for different OS versions
2. ✅ **No compiler errors** - Builds with any SDK version
3. ✅ **No runtime crashes** - Safe on all OS versions
4. ✅ **Easy testing** - Can test on multiple OS versions
5. ✅ **Future-proof** - Automatically uses new features when available

### For Distribution

1. ✅ **Wider market** - Can target older OS versions
2. ✅ **Single binary** - No need for multiple app variants
3. ✅ **App Store ready** - Meets compatibility requirements
4. ✅ **Gradual adoption** - Users upgrade when ready

## Testing Matrix

| Build SDK | Device OS | FoundationModels | Expected Behavior           |
| --------- | --------- | ---------------- | --------------------------- |
| iOS 26    | iOS 26    | Available        | ✅ Full features             |
| iOS 26    | iOS 25    | Not available    | ✅ Disabled                  |
| iOS 25    | iOS 25    | Not available    | ✅ Disabled                  |
| iOS 25    | iOS 26    | Not in binary    | ⚠️ Disabled (rebuild needed) |
| macOS 26  | macOS 26  | Available        | ✅ Full features             |
| macOS 26  | macOS 25  | Not available    | ✅ Disabled                  |

## Deployment Configuration

### Xcode Project Settings

**Minimum Deployment Target:**
- iOS: Can be set to iOS 13+ or any version
- macOS: Can be set to macOS 10.15+ or any version

**SDK:**
- Use latest available SDK (iOS 26+, macOS 26+)
- Conditional compilation handles older devices

**Example in Xcode:**
```
IPHONEOS_DEPLOYMENT_TARGET = 15.0  // or lower
MACOSX_DEPLOYMENT_TARGET = 12.0     // or lower
```

**Result:**
- App builds with iOS 26+ SDK
- Runs on iOS 15+ devices
- Foundation Models only on iOS 26+

## Code Patterns

### Pattern 1: Optional Feature

```swift
func someFeature() {
    #if canImport(FoundationModels)
    if #available(iOS 26.0, macOS 26.0, *) {
        // Use Foundation Models
    } else {
        // Fallback behavior
    }
    #else
    // Fallback behavior
    #endif
}
```

### Pattern 2: Feature Detection

```swift
var hasFeature: Bool {
    #if canImport(FoundationModels)
    if #available(iOS 26.0, macOS 26.0, *) {
        return true
    }
    #endif
    return false
}
```

### Pattern 3: Conditional Types with Helper Functions

```swift
#if canImport(FoundationModels)
@available(iOS 26.0, macOS 26.0, *)
struct NewFeatureType {
    // Type definition
}
#endif

// Public API always available
func useNewFeature() async throws -> Result {
    #if canImport(FoundationModels)
    if #available(iOS 26.0, macOS 26.0, *) {
        return try await useNewFeatureWithFM()
    }
    #endif
    // Fallback for older SDKs/OS
    throw NSError(...)  // or return fallback
}

// Private helper function with full availability annotation
#if canImport(FoundationModels)
@available(iOS 26.0, macOS 26.0, *)
private func useNewFeatureWithFM() async throws -> Result {
    // Implementation using NewFeatureType
    let feature: NewFeatureType = ...
    return processFeature(feature)
}
#endif
```

**Key Pattern:** The function call itself must also be wrapped in `if #available` to prevent the compiler from seeing calls to functions with unavailable type signatures.

## Best Practices

### DO ✅

1. **Wrap imports in `#if canImport`**
   ```swift
   #if canImport(FoundationModels)
   import FoundationModels
   #endif
   ```

2. **Keep public API always available**
   ```swift
   struct MyService {
       static var isSupported: Bool { ... }  // Always exists
       static func doWork() { ... }           // Always exists
   }
   ```

3. **Provide graceful fallbacks**
   ```swift
   #else
   return []  // or throw clear error
   #endif
   ```

4. **Use helper functions with runtime availability checks**
   ```swift
   // Public wrapper - THREE layers of protection
   func doWork() async throws -> Result {
       #if canImport(FoundationModels)              // Layer 1: Compile-time
       if #available(iOS 26.0, macOS 26.0, *) {     // Layer 2: Runtime
           return try await doWorkWithFM()           // Layer 3: Call wrapped function
       }
       #endif
       return fallbackResult
   }
   
   // Private implementation
   #if canImport(FoundationModels)
   @available(iOS 26.0, macOS 26.0, *)
   private func doWorkWithFM() async throws -> Result {
       // Uses FM types safely
   }
   #endif
   ```

5. **Test on multiple OS versions**
   - Test with old SDK
   - Test with new SDK + old OS
   - Test with new SDK + new OS

### DON'T ❌

1. **Don't expose conditional types in public API**
   ```swift
   // BAD - Type only exists sometimes
   func process(_ input: LLMTemplatePlace) { ... }
   
   // GOOD - Type always exists
   func process(_ input: TemplatePlace) { ... }
   ```

2. **Don't assume SDK == Runtime**
   ```swift
   // BAD - Doesn't check runtime
   #if canImport(FoundationModels)
   let model = SystemLanguageModel.default  // Might crash!
   #endif
   
   // GOOD - Checks both
   #if canImport(FoundationModels)
   if #available(iOS 26.0, macOS 26.0, *) {
       let model = SystemLanguageModel.default  // Safe
   }
   #endif
   ```

3. **Don't forget error handling**
   ```swift
   // BAD - Silent failure
   #else
   // Nothing
   #endif
   
   // GOOD - Clear error
   #else
   throw NSError(...)
   #endif
   ```

4. **Don't forget runtime availability checks when calling functions**
   ```swift
   // BAD - Will cause build errors
   #if canImport(FoundationModels)
   return try await useNewFeatureWithFM()  // ❌ Compiler sees unavailable types
   #endif
   
   // GOOD - Both compile-time AND runtime checks
   #if canImport(FoundationModels)
   if #available(iOS 26.0, macOS 26.0, *) {
       return try await useNewFeatureWithFM()  // ✅ Protected
   }
   #endif
   ```
   
   **Why:** Even inside `#if canImport`, the compiler needs `if #available` to allow calls to functions with unavailable type signatures.

## Migration Path

### For Users on Older OS

1. App installs and works
2. Apple Intelligence shows as "Not Available"
3. Gemini available as alternative
4. When they upgrade to iOS 26:
   - No app update needed
   - Feature automatically becomes available

### For Developers

**Current State:**
- ✅ Build with any SDK version
- ✅ Deploy to any OS version
- ✅ Features available where supported

**Future Updates:**
- Add new FM features in `#if canImport` blocks
- Maintain backward compatibility
- No breaking changes needed

## Summary

**What we achieved:**
- ✅ App builds with **any SDK version**
- ✅ App runs on **any OS version**
- ✅ Foundation Models available **when supported**
- ✅ Graceful degradation **when not supported**
- ✅ Single codebase for **all platforms**

**How we did it:**
- `#if canImport(FoundationModels)` for compile-time checks
- `#available(iOS 26.0, macOS 26.0, *)` for runtime checks
- Clear fallback behavior in `#else` blocks
- Consistent `isSupported` API across all OS versions

**Result:**
- 🎯 Maximum compatibility
- 🎯 No crashes or build errors
- 🎯 Features automatically available when supported
- 🎯 Clear user messaging about availability

---

**Status:** ✅ Fully Implemented  
**Minimum Build SDK:** Any (iOS 13+ SDK supported)  
**Minimum Runtime OS:** Any (iOS 13+ devices supported)  
**Foundation Models:** iOS 26+ / macOS 26+ only  
**Tested:** Ready for production

