import Foundation

/// Gemini API place generator using REST API with structured JSON output
struct GeminiPlaceGenerator {
    private static let apiEndpoint = "https://generativelanguage.googleapis.com/v1beta/models/gemini-2.5-flash:generateContent"
    private static let keychainKey = "gemini_api_key"
    
    enum GeminiError: Error {
        case noAPIKey
        case invalidURL
        case networkError(Error)
        case invalidResponse
        case decodingError(Error)
        case apiError(String)
        case rateLimited(retryAfter: TimeInterval?)
        case quotaExceeded(retryAfter: TimeInterval?)
        
        var localizedDescription: String {
            switch self {
            case .noAPIKey:
                return "Gemini API key not configured"
            case .invalidURL:
                return "Invalid API endpoint URL"
            case .networkError(let error):
                return "Network error: \(error.localizedDescription)"
            case .invalidResponse:
                return "Invalid response from Gemini API"
            case .decodingError(let error):
                return "Failed to parse response: \(error.localizedDescription)"
            case .apiError(let message):
                return "API error: \(message)"
            case .rateLimited(let retryAfter):
                if let delay = retryAfter {
                    return "Rate limited. Please wait \(Int(delay)) seconds before trying again."
                }
                return "Rate limited. Please try again in a few moments."
            case .quotaExceeded(let retryAfter):
                if let delay = retryAfter {
                    return "Quota exceeded. Please retry in \(Int(delay)) seconds."
                }
                return "Quota exceeded. Please check your API plan or try again later."
            }
        }
    }
    
    static var isConfigured: Bool {
        (try? KeychainHelper.retrieve(key: keychainKey)) != nil
    }
    
    /// Saves the Gemini API key securely to Keychain
    static func saveAPIKey(_ key: String) throws {
        try KeychainHelper.save(key: keychainKey, value: key)
    }
    
    /// Retrieves the Gemini API key from Keychain
    static func getAPIKey() throws -> String {
        try KeychainHelper.retrieve(key: keychainKey)
    }
    
    /// Deletes the Gemini API key from Keychain
    static func deleteAPIKey() throws {
        try KeychainHelper.delete(key: keychainKey)
    }
    
    /// Parses retry delay from error message (e.g., "Please retry in 25.032949621s.")
    private static func parseRetryDelay(from message: String) -> TimeInterval? {
        // Look for pattern like "retry in 25.032949621s" or "retry in 25s"
        let pattern = "retry in ([0-9.]+)s"
        guard let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive),
              let match = regex.firstMatch(in: message, options: [], range: NSRange(message.startIndex..., in: message)),
              match.numberOfRanges > 1 else {
            return nil
        }
        
        let delayString = (message as NSString).substring(with: match.range(at: 1))
        return TimeInterval(delayString)
    }
    
    /// Checks if error is a rate limit or quota error and extracts retry delay
    private static func classifyAPIError(_ message: String) -> GeminiError {
        let lowercased = message.lowercased()
        
        // Check for quota exceeded
        if lowercased.contains("quota exceeded") || lowercased.contains("quota_exceeded") {
            let retryDelay = parseRetryDelay(from: message)
            return .quotaExceeded(retryAfter: retryDelay)
        }
        
        // Check for rate limit
        if lowercased.contains("rate limit") || lowercased.contains("too many requests") || lowercased.contains("429") {
            let retryDelay = parseRetryDelay(from: message)
            return .rateLimited(retryAfter: retryDelay)
        }
        
        // Generic API error
        return .apiError(message)
    }
    
    /// Progress update for place generation
    struct GenerationProgress {
        let currentTurn: Int
        let maxTurns: Int
        let verifiedPlacesCount: Int
        let currentActivity: String  // e.g., "Verifying Blue Bottle Coffee..."
    }
    
    /// Generates places using Gemini API with tool calling for verification
    /// - Parameters:
    ///   - userPrompt: The user's query (e.g., "coffee shops in Austin")
    ///   - maxCount: Maximum number of places to generate
    ///   - progressHandler: Optional callback for progress updates
    /// - Returns: Tuple of generated places and whether PCC was used
    @MainActor
    static func generatePlaces(
        userPrompt: String,
        maxCount: Int = 30,
        progressHandler: ((GenerationProgress) -> Void)? = nil
    ) async throws -> ([TemplatePlace], usedPCC: Bool) {
        // Get API key from Keychain
        guard let apiKey = try? getAPIKey() else {
            throw GeminiError.noAPIKey
        }
        
        // Build the URL with API key
        guard var urlComponents = URLComponents(string: apiEndpoint) else {
            throw GeminiError.invalidURL
        }
        urlComponents.queryItems = [URLQueryItem(name: "key", value: apiKey)]
        
        guard let url = urlComponents.url else {
            throw GeminiError.invalidURL
        }
        
        let bounded = max(1, min(maxCount, 100))
        
        // Build the request body with tools for verification (NO structured output - incompatible with tools)
        let initialRequestBody: [String: Any] = [
            "system_instruction": [
                "parts": [
                    [
                        "text": """
                        You are an expert in finding recommended places. Your goal is to provide REAL, VERIFIED places that actually exist with COMPLETE addresses.
                        
                        CRITICAL INSTRUCTIONS:
                        1. You MUST use the search_location tool to verify EVERY place before including it
                        2. Do NOT make up addresses or guess - only return places you've verified using the tool
                        3. Call search_location with the place name and city/region
                        4. Use the EXACT address data returned by the tool
                        5. Only include places where the tool successfully returned a COMPLETE address
                        
                        COMPLETE ADDRESS REQUIREMENTS:
                        - streetAddress1: MUST include street number AND name (e.g., "315 Linden Street", NOT just "Linden Street")
                        - city: MUST be populated (e.g., "San Francisco", NOT "N/A" or blank)
                        - state: Should be 2-letter code for US addresses (e.g., "CA", "TX")
                        - postalCode: Should be 5-digit ZIP code when available
                        - NEVER use placeholder values: "N/A", "Unknown", "TBD", "None", or empty strings
                        - If tool returns incomplete address, DO NOT include that place
                        
                        Target: Return between 5 and \(bounded) verified, real places with COMPLETE addresses
                        
                        Process:
                        - Think of candidate places matching the user's request
                        - For EACH candidate, call search_location("Place Name City")
                        - Wait for tool results
                        - VERIFY the returned address has street number, city, and other required fields
                        - Use ONLY verified addresses with all required components
                        - After verifying all places, output final JSON array
                        
                        Final Output Format (JSON array ONLY, no other text):
                        [
                          {
                            "name": "Exact name from tool",
                            "streetAddress1": "Complete street address with number from tool",
                            "streetAddress2": "",
                            "city": "Exact city from tool",
                            "state": "Exact state code from tool",
                            "postalCode": "Exact ZIP from tool",
                            "country": "Exact country from tool"
                          }
                        ]
                        
                        Remember: VERIFY FIRST, VALIDATE COMPLETENESS, then output. No incomplete addresses!
                        """
                    ]
                ]
            ],
            "tools": [
                [
                    "functionDeclarations": [
                        LocationSearchTool.geminiFunctionDeclaration
                    ]
                ]
            ]
        ]
        
        // Multi-turn conversation to handle tool calls
        var conversationHistory: [[String: Any]] = [
            [
                "role": "user",
                "parts": [["text": userPrompt]]
            ]
        ]
        
        let maxTurns = 20  // Allow more turns for verification
        var currentTurn = 0
        var verifiedPlacesCount = 0
        
        print("🔄 [Gemini] Starting place generation with tool calling...")
        
        // Report initial progress
        progressHandler?(GenerationProgress(
            currentTurn: 0,
            maxTurns: maxTurns,
            verifiedPlacesCount: 0,
            currentActivity: "Starting generation..."
        ))
        
        while currentTurn < maxTurns {
            currentTurn += 1
            print("🔄 [Gemini] Turn \(currentTurn)/\(maxTurns)")
            
            // Report turn progress
            progressHandler?(GenerationProgress(
                currentTurn: currentTurn,
                maxTurns: maxTurns,
                verifiedPlacesCount: verifiedPlacesCount,
                currentActivity: "Processing request..."
            ))
            
            // Build request with conversation history
            var currentRequestBody = initialRequestBody
            currentRequestBody["contents"] = conversationHistory
            
            // Create the request
            var request = URLRequest(url: url)
            request.httpMethod = "POST"
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.httpBody = try JSONSerialization.data(withJSONObject: currentRequestBody)
            request.timeoutInterval = 90  // Longer timeout for tool calls
            
            // Make the request
            let (data, response) = try await URLSession.shared.data(for: request)
            
            // Check HTTP response
            guard let httpResponse = response as? HTTPURLResponse else {
                throw GeminiError.invalidResponse
            }
            
            guard (200...299).contains(httpResponse.statusCode) else {
                // Try to parse error message
                if let errorJson = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                   let error = errorJson["error"] as? [String: Any],
                   let message = error["message"] as? String {
                    // Classify the error (rate limit, quota, or generic)
                    throw classifyAPIError(message)
                }
                
                // Check for 429 status code (rate limited)
                if httpResponse.statusCode == 429 {
                    throw GeminiError.rateLimited(retryAfter: nil)
                }
                
                throw GeminiError.apiError("HTTP \(httpResponse.statusCode)")
            }
            
            // Parse the response
            guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let candidates = json["candidates"] as? [[String: Any]],
                  let firstCandidate = candidates.first,
                  let content = firstCandidate["content"] as? [String: Any],
                  let parts = content["parts"] as? [[String: Any]] else {
                throw GeminiError.invalidResponse
            }
            
            // Add model's response to conversation history
            conversationHistory.append([
                "role": "model",
                "parts": parts
            ])
            
            // Check if there are function calls
            var hasFunctionCalls = false
            var functionResponses: [[String: Any]] = []
            
            for part in parts {
                if let functionCall = part["functionCall"] as? [String: Any],
                   let functionName = functionCall["name"] as? String,
                   let args = functionCall["args"] as? [String: Any] {
                    hasFunctionCalls = true
                    print("🔧 [Gemini] Called function: \(functionName) with args: \(args)")
                    
                    // Execute the function
                    if functionName == "search_location",
                       let locationName = args["location_name"] as? String {
                        
                        // Report progress for this verification
                        progressHandler?(GenerationProgress(
                            currentTurn: currentTurn,
                            maxTurns: maxTurns,
                            verifiedPlacesCount: verifiedPlacesCount,
                            currentActivity: "Verifying \(locationName)..."
                        ))
                        
                        do {
                            let result = try await LocationSearchTool.searchLocation(locationName: locationName)
                            print("✅ [Gemini] Location found: \(result.name) at \(result.formattedAddress)")
                            
                            verifiedPlacesCount += 1
                            
                            // Update progress with verified count
                            progressHandler?(GenerationProgress(
                                currentTurn: currentTurn,
                                maxTurns: maxTurns,
                                verifiedPlacesCount: verifiedPlacesCount,
                                currentActivity: "Verified \(result.name)"
                            ))
                            
                            // Create function response
                            let functionResponse: [String: Any] = [
                                "functionResponse": [
                                    "name": functionName,
                                    "response": [
                                        "name": result.name,
                                        "streetAddress": result.streetAddress,
                                        "city": result.city,
                                        "state": result.state,
                                        "postalCode": result.postalCode,
                                        "country": result.country
                                    ]
                                ]
                            ]
                            functionResponses.append(functionResponse)
                        } catch {
                            print("❌ [Gemini] Location search failed: \(error.localizedDescription)")
                            // Return error to model
                            let errorResponse: [String: Any] = [
                                "functionResponse": [
                                    "name": functionName,
                                    "response": [
                                        "error": error.localizedDescription
                                    ]
                                ]
                            ]
                            functionResponses.append(errorResponse)
                        }
                    }
                }
            }
            
            // If there were function calls, add responses and continue conversation
            if hasFunctionCalls && !functionResponses.isEmpty {
                conversationHistory.append([
                    "role": "user",
                    "parts": functionResponses
                ])
                continue  // Next turn with function responses
            }
            
            // No function calls, check for text response with JSON
            if let firstPart = parts.first,
               let text = firstPart["text"] as? String {
                print("📝 [Gemini] Received final response")
                
                // Try to extract JSON array from text
                // The response might have some text before/after the JSON
                guard let jsonStart = text.range(of: "["),
                      let jsonEnd = text.range(of: "]", options: .backwards) else {
                    print("⚠️ [Gemini] No JSON array found in response")
                    print(text)
                    throw GeminiError.decodingError(NSError(domain: "GeminiPlaceGenerator", code: -1, userInfo: [NSLocalizedDescriptionKey: "No JSON array in response"]))
                }
                
                let jsonString = String(text[jsonStart.lowerBound...jsonEnd.upperBound])
                
                guard let placesData = jsonString.data(using: .utf8),
                      let placesJson = try? JSONSerialization.jsonObject(with: placesData) as? [[String: Any]] else {
                    print("⚠️ [Gemini] Failed to parse JSON")
                    print(text)
                    throw GeminiError.decodingError(NSError(domain: "GeminiPlaceGenerator", code: -1, userInfo: [NSLocalizedDescriptionKey: "Failed to parse places JSON"]))
                }
                
                // Convert to TemplatePlace objects
                let places: [TemplatePlace] = placesJson.compactMap { placeDict in
                    guard let name = placeDict["name"] as? String,
                          let streetAddress1 = placeDict["streetAddress1"] as? String,
                          let city = placeDict["city"] as? String else {
                        return nil
                    }
                    
                    let streetAddress2 = placeDict["streetAddress2"] as? String
                    let state = placeDict["state"] as? String
                    let postalCode = placeDict["postalCode"] as? String
                    let country = placeDict["country"] as? String
                    
                    // Filter out empty optional strings
                    let cleanStreetAddress2 = streetAddress2?.isEmpty == false ? streetAddress2 : nil
                    let cleanState = state?.isEmpty == false ? state : nil
                    let cleanPostalCode = postalCode?.isEmpty == false ? postalCode : nil
                    let cleanCountry = country?.isEmpty == false ? country : nil
                    
                    return TemplatePlace(
                        name: name,
                        streetAddress1: streetAddress1,
                        streetAddress2: cleanStreetAddress2,
                        city: city,
                        state: cleanState,
                        postalCode: cleanPostalCode,
                        country: cleanCountry
                    )
                }
                
                print("✅ [Gemini] Successfully parsed \(places.count) places")
                
                // Final progress update
                progressHandler?(GenerationProgress(
                    currentTurn: currentTurn,
                    maxTurns: maxTurns,
                    verifiedPlacesCount: places.count,
                    currentActivity: "Completed! Found \(places.count) places"
                ))
                
                // Gemini API doesn't use PCC, it's a cloud service
                return (places, false)
            }
            
            // If we get here without text or function calls, something went wrong
            throw GeminiError.invalidResponse
        }
        
        throw GeminiError.apiError("Max conversation turns reached without getting results")
    }
}


