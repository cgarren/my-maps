# Gemini AI Integration

## Overview

This implementation adds **Google Gemini API** support alongside **Apple Foundation Models** for AI-powered place generation. Users can choose their preferred AI provider and securely store API keys.

## Features

### 1. **Dual AI Provider Support**
- **Apple Foundation Models** (iOS 18+, macOS 15+)
  - On-device processing
  - Privacy-preserving
  - No API key required
  
- **Google Gemini** (Cloud-based)
  - Works on any iOS/macOS version
  - Requires API key
  - Uses Gemini 2.0 Flash model

### 2. **Secure API Key Storage**
- API keys stored in **iOS Keychain**
- Never stored in UserDefaults or plain text
- Accessible only to the app
- Survives app reinstalls

### 3. **Structured Output**
Both providers return structured JSON following the `TemplatePlace` schema:
```swift
struct TemplatePlace {
    let name: String
    let streetAddress1: String
    let streetAddress2: String?
    let city: String
    let state: String?
    let postalCode: String?
    let country: String?
}
```

## Implementation Details

### New Files Created

#### 1. `KeychainHelper.swift`
Secure storage helper for API keys using iOS Keychain.

**Key Methods:**
- `save(key:value:)` - Saves or updates a key-value pair
- `retrieve(key:)` - Retrieves a stored value
- `delete(key:)` - Removes a key-value pair

**Security Features:**
- Uses `kSecClassGenericPassword` for secure storage
- `kSecAttrAccessibleWhenUnlocked` ensures data is only accessible when device is unlocked
- Handles duplicate entries gracefully

#### 2. `GeminiPlaceGenerator.swift`
REST API client for Google Gemini API.

**Key Features:**
- Uses Gemini 2.5 Flash model (latest)
- Structured JSON output via `response_schema`
- Separated system instructions from user prompts
- **Few-shot prompting** with example output for better accuracy
- ~~**Tool calling**: Can search for locations to verify addresses (optional)~~ (Disabled: Gemini doesn't support tools + structured JSON together)
- Comprehensive error handling with detailed logging
- Extended timeout (60s) for complex requests
- Converts Gemini response to `TemplatePlace` objects

**API Endpoint:**
```
https://generativelanguage.googleapis.com/v1beta/models/gemini-2.0-flash:generateContent
```

**Request Structure:**
```json
{
  "system_instruction": {
    "parts": [{
      "text": "System instructions defining the AI's role and constraints"
    }]
  },
  "contents": [{
    "parts": [{
      "text": "User's specific prompt/query"
    }]
  }],
  "generationConfig": {
    "response_mime_type": "application/json",
    "response_schema": {
      "type": "ARRAY",
      "items": {
        "type": "OBJECT",
        "properties": {
          "name": {"type": "STRING"},
          "streetAddress1": {"type": "STRING"},
          ...
        }
      }
    }
  }
}
```

**Why Separate System Instructions?**
- **Clarity**: System-level instructions are separate from user queries
- **Consistency**: System instructions apply to all requests in a session
- **Best Practice**: Follows Gemini API's recommended structure
- **Token Efficiency**: System instructions can be cached in multi-turn conversations
- **Few-Shot Prompting**: Includes example output to guide the model's responses

#### 3. `AIProvider.swift`
Enum defining available AI providers with availability checks.

**Properties:**
- `displayName` - User-facing name
- `description` - Provider description
- `isAvailable` - Runtime availability check
- `requiresAPIKey` - Whether API key is needed

**UserDefaults Extension:**
- `selectedAIProvider` - Persists user's provider choice

#### 4. `SettingsView.swift`
SwiftUI view for managing AI provider settings.

**Features:**
- Provider selection picker
- Secure API key input (uses `SecureField`)
- API key management (save/update/remove)
- Provider availability status
- Link to Google AI Studio for API key creation

### Modified Files

#### 1. `NewMapSheet.swift`
**Changes:**
- Added `@AppStorage` for provider selection
- Updated UI to show selected provider
- Modified `generateWithAI()` to switch between providers
- Added settings button to toolbar
- Dynamic footer text based on provider availability

**Key Code:**
```swift
switch selectedProvider {
case .appleFM:
    (places, usedPCC) = try await LLMPlaceGenerator.generatePlaces(...)
case .gemini:
    (places, usedPCC) = try await GeminiPlaceGenerator.generatePlaces(...)
}
```

#### 2. `MapsListView.swift`
**Changes:**
- Added settings button to toolbar
- Added sheet presentation for `SettingsView`

## Getting Started

### 1. Get a Gemini API Key

1. Visit [Google AI Studio](https://aistudio.google.com/apikey)
2. Sign in with your Google account
3. Click "Create API Key"
4. Copy the generated key

### 2. Configure the App

1. Open the app
2. Tap the **gear icon** (⚙️) in the toolbar
3. Select "Google Gemini" as the AI Provider
4. Enter your API key in the secure field
5. Tap "Save Key"

### 3. Generate Places

1. Create a new map
2. Scroll to "Generate with AI (Google Gemini)" section
3. Enter your prompt (e.g., "Top coffee shops in Austin")
4. Tap "Generate with AI"
5. Review the generated places
6. Select which ones to add to your map

## API Key Security

### Where is the API Key Stored?

The API key is stored in the **iOS Keychain**, which is:
- Encrypted by the operating system
- Isolated per-app (other apps cannot access it)
- Backed up securely with iCloud Keychain (if enabled)
- Survives app reinstalls

### Can I see my API key after saving?

No. For security, the key is masked as `••••••••` after saving. You can:
- Update it (overwrites the old key)
- Remove it (deletes from Keychain)

### What happens if I delete the app?

The API key is removed from the Keychain when the app is deleted.

## Error Handling

### Gemini API Errors

The implementation handles various error cases:

1. **No API Key** (`GeminiError.noAPIKey`)
   - Shown when trying to generate without configuring API key
   - Solution: Configure API key in settings

2. **Invalid URL** (`GeminiError.invalidURL`)
   - Rare error indicating malformed API endpoint
   - Solution: Check code implementation

3. **Network Error** (`GeminiError.networkError`)
   - Network connectivity issues
   - Solution: Check internet connection

4. **Invalid Response** (`GeminiError.invalidResponse`)
   - API returned unexpected format
   - Solution: Check API status

5. **API Error** (`GeminiError.apiError`)
   - API returned error message (e.g., invalid key, quota exceeded)
   - Solution: Check API key validity and quota

6. **Decoding Error** (`GeminiError.decodingError`)
   - Failed to parse JSON response
   - Solution: Check response format

### Keychain Errors

1. **Duplicate Entry** (`KeychainError.duplicateEntry`)
   - Automatically handled by updating existing entry

2. **Not Found** (`KeychainError.notFound`)
   - Key doesn't exist in Keychain
   - Solution: Save a new key

3. **Invalid Data** (`KeychainError.invalidData`)
   - Data corruption
   - Solution: Delete and re-save key

## Comparison: Apple FM vs Gemini

| Feature          | Apple Foundation Models       | Google Gemini          |
| ---------------- | ----------------------------- | ---------------------- |
| **Availability** | iOS 18+, macOS 15+            | Any iOS/macOS version  |
| **Processing**   | On-device                     | Cloud-based            |
| **Privacy**      | Maximum (never leaves device) | Data sent to Google    |
| **API Key**      | Not required                  | Required               |
| **Cost**         | Free                          | Free tier + paid tiers |
| **Speed**        | Fast (local)                  | Depends on network     |
| **Offline**      | Works offline                 | Requires internet      |
| **Quality**      | Excellent                     | Excellent              |
| **Tool Calling** | ✅ Optional                    | ✅ Mandatory (verified) |

## Tool Calling Feature ✅

**Both providers now use tool calling to verify addresses!**

### Apple Foundation Models ✅

**Status:** Fully implemented with optional usage

Apple Foundation Models support native tool calling via the `Tool` protocol. The on-device model calls `search_location` when it wants to verify addresses.

**Implementation:**
- `LocationSearchToolFM` - Conforms to `Tool` protocol
- Uses `@Generable` for type-safe arguments
- Automatically integrated into `LanguageModelSession`
- Model decides when verification is needed (optional)

**Benefits:**
- ✅ Real, verified addresses from Apple Maps when needed
- ✅ Optional usage - only calls tool when uncertain
- ✅ 100% on-device and private
- ✅ Type-safe implementation

### Google Gemini ✅ **MANDATORY VERIFICATION**

**Status:** Fully implemented with **required** verification for every place!

**The Solution:** We chose tool calling over structured JSON output because verified addresses are more important than strict schema enforcement.

**Implementation:**
- Tool calling enabled with `search_location` function
- Multi-turn conversation loop (up to 20 turns)
- System instructions **require** tool usage for every place
- JSON parsing from text response (flexible extraction)

**How It Works:**
1. User requests places (e.g., "coffee shops in Austin")
2. Gemini identifies candidate places
3. **For EACH place**, calls `search_location("Place Name City")`
4. MKLocalSearch verifies place exists, returns real address
5. Gemini uses verified data in response
6. Only verified, real places returned

**Benefits:**
- ✅ **NO MORE HALLUCINATIONS** - all places verified via Apple Maps
- ✅ **Real addresses** - every address confirmed to exist
- ✅ **Better UX** - users get places they can visit
- ✅ **Accurate geocoding** - verified addresses work

**Trade-offs:**
- ⚠️ Slower (more API calls)
- ⚠️ More API usage (multi-turn)
- ✅ **Worth it** - accuracy > speed

**See `TOOL_CALLING.md` for complete documentation.**

## Rate Limiting & Progress Tracking ✅

**Comprehensive rate limit handling with real-time progress:**

### Features
- ✅ **Intelligent error detection** - Parses retry delays from API errors
- ✅ **User-friendly messages** - "Wait 25 seconds" instead of technical errors
- ✅ **Real-time progress** - "Verifying Blue Bottle Coffee..."
- ✅ **Verified count** - "Verified 5 places so far"
- ✅ **Input disabled** - Can't interrupt generation
- ✅ **Error classification** - Rate limit vs quota exceeded

### Error Handling
```swift
case .rateLimited(retryAfter: TimeInterval?)
    -> "Rate limited. Please wait 25 seconds..."

case .quotaExceeded(retryAfter: TimeInterval?)
    -> "Quota exceeded. Please retry in 25 seconds or check your plan..."
```

### Progress Updates
- "Starting generation..."
- "Verifying [Place Name]..."
- "Verified N places so far"
- "Completed! Found 10 places"

**See `RATE_LIMIT_HANDLING.md` for complete details.**

## Best Practices

### 1. API Key Management
- Never hardcode API keys in source code
- Don't commit API keys to version control
- Use Keychain for secure storage
- Rotate keys periodically

### 2. Error Handling
- Always wrap API calls in try-catch
- Provide user-friendly error messages
- Log errors for debugging (but not API keys!)

### 3. Rate Limiting
- Gemini has rate limits (check your quota)
- Implement exponential backoff for retries
- Consider caching results when appropriate

### 4. User Experience
- Show loading indicators during generation
- Allow users to cancel long-running requests
- Provide clear feedback on errors
- Make provider selection easy to find

## Testing

### Test Gemini Integration

1. **Valid API Key:**
   ```
   Prompt: "Top 5 pizza places in New York"
   Expected: 5-20 places with valid NYC addresses
   ```

2. **Invalid API Key:**
   ```
   Expected: Error message about invalid key
   ```

3. **Network Failure:**
   ```
   Turn off WiFi/cellular
   Expected: Network error message
   ```

4. **Empty Prompt:**
   ```
   Expected: Generate button disabled
   ```

### Test Apple FM Integration

1. **iOS 18+ Device:**
   ```
   Expected: Apple Intelligence option available
   ```

2. **iOS 17 Device:**
   ```
   Expected: Apple Intelligence unavailable, Gemini as alternative
   ```

## Future Enhancements

### Potential Improvements

1. **Multiple API Keys**
   - Support for different keys per project
   - Team/organization key management

2. **Provider Fallback**
   - Automatically switch providers on failure
   - Load balancing between providers

3. **Advanced Configuration**
   - Temperature/creativity settings
   - Max tokens configuration
   - Custom system prompts

4. **Analytics**
   - Track which provider is used
   - Monitor success rates
   - Cost tracking for Gemini

5. **Caching**
   - Cache common queries
   - Reduce API calls
   - Offline mode with cached results

6. **Additional Providers**
   - OpenAI GPT-4
   - Anthropic Claude
   - Azure OpenAI

## Troubleshooting

### "Requires API key configuration"

**Problem:** Gemini selected but no API key configured.

**Solution:**
1. Tap the gear icon (⚙️)
2. Enter your API key
3. Tap "Save Key"

### "API Error: Invalid API key"

**Problem:** The API key is invalid or revoked.

**Solution:**
1. Generate a new key at [Google AI Studio](https://aistudio.google.com/apikey)
2. Update the key in settings

### "Network Error"

**Problem:** No internet connection or API unreachable.

**Solution:**
1. Check your internet connection
2. Try again in a few moments
3. Check Google Cloud status page

### "No addresses found"

**Problem:** Gemini returned places but geocoding failed.

**Solution:**
1. Check if addresses are valid US addresses
2. Try a more specific prompt (e.g., include city/state)
3. Manually edit addresses if needed

## API Costs

### Gemini API Pricing (as of 2025)

- **Free Tier:** 15 requests per minute
- **Paid Tier:** Pay-as-you-go pricing

For current pricing, visit: https://ai.google.dev/pricing

### Estimating Costs

Each place generation request:
- Input: ~200-500 tokens (prompt + schema)
- Output: ~500-2000 tokens (20 places with addresses)
- Total: ~700-2500 tokens per request

## Conclusion

This implementation provides a flexible, secure, and user-friendly way to integrate multiple AI providers for place generation. The architecture is extensible, allowing for easy addition of new providers in the future.

---

**Status:** ✅ Implementation Complete  
**Tested On:** iOS 18.0+, macOS 15.0+  
**Security:** Keychain-based secure storage  
**Privacy:** User choice between on-device and cloud AI

