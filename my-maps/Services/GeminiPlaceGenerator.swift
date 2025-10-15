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
    
    /// Generates places using Gemini API with structured JSON output
    static func generatePlaces(userPrompt: String, maxCount: Int = 30) async throws -> ([TemplatePlace], usedPCC: Bool) {
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
        
        // Define the JSON schema for structured output
        let bounded = max(1, min(maxCount, 100))
        let schema: [String: Any] = [
            "type": "ARRAY",
            "items": [
                "type": "OBJECT",
                "properties": [
                    "name": ["type": "STRING"],
                    "streetAddress1": ["type": "STRING"],
                    "streetAddress2": ["type": "STRING"],
                    "city": ["type": "STRING"],
                    "state": ["type": "STRING"],
                    "postalCode": ["type": "STRING"],
                    "country": ["type": "STRING"]
                ],
                "required": ["name", "streetAddress1", "city"]
            ]
        ]
        
        // Build the request body with separated system instructions and user prompt
        let requestBody: [String: Any] = [
            "system_instruction": [
                "parts": [
                    [
                        "text": """
                        You are an expert in finding recommended places. Generate realistic, verifiable places for user requests.
                        
                        For each request, return between 5 and \(bounded) unique places. Each place MUST include:
                        - name: the official place or venue name
                        - streetAddress1: street number and name (required)
                        - streetAddress2: secondary unit like Suite/Floor (optional, can be empty string. ONLY output when necessary)
                        - city: city name
                        - state: two-letter state code (e.g., "TX", "CA") or full region name for non-US
                        - postalCode: 5-digit ZIP or postal code if known (optional, can be empty string)
                        - country: full country name (e.g., "United States", "Canada", "United Kingdom")
                        
                        Example output for a single place:
                        {
                          "name": "Blue Bottle Coffee",
                          "streetAddress1": "315 Linden Street",
                          "streetAddress2": "",
                          "city": "San Francisco",
                          "state": "CA",
                          "postalCode": "94102",
                          "country": "United States"
                        }
                        
                        Rules:
                        - Prefer well-known, reputable, or authoritative places
                        - Ensure addresses are real, verifiable, and mailable
                        - No duplicate places in the results
                        - If the request specifies a region (e.g., "Austin coffee shops"), focus results to that region
                        - Prioritize places that are currently open/operational
                        - Use official business names, not colloquial names
                        """
                    ]
                ]
            ],
            "contents": [
                [
                    "parts": [
                        [
                            "text": userPrompt
                        ]
                    ]
                ]
            ],
            "generationConfig": [
                "response_mime_type": "application/json",
                "response_schema": schema
            ]
        ]
        
        // Create the request
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: requestBody)
        request.timeoutInterval = 60
        
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
                throw GeminiError.apiError(message)
            }
            throw GeminiError.apiError("HTTP \(httpResponse.statusCode)")
        }
        
        // Parse the response
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let candidates = json["candidates"] as? [[String: Any]],
              let firstCandidate = candidates.first,
              let content = firstCandidate["content"] as? [String: Any],
              let parts = content["parts"] as? [[String: Any]],
              let firstPart = parts.first,
              let text = firstPart["text"] as? String else {
            throw GeminiError.invalidResponse
        }
        
        // Parse the JSON array of places
        guard let placesData = text.data(using: .utf8) else {
            print(text.data)
            throw GeminiError.decodingError(NSError(domain: "GeminiPlaceGenerator", code: -1, userInfo: [NSLocalizedDescriptionKey: "Failed to parse places Data"]))
        }
              
        guard let placesJson = try? JSONSerialization.jsonObject(with: placesData) as? [[String: Any]] else {
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
        
        // Gemini API doesn't use PCC, it's a cloud service
        return (places, false)
    }
}

