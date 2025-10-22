import Foundation
#if canImport(FoundationModels)
import FoundationModels

/// Internal generable type used to ensure the model returns structured output
@available(iOS 26.0, macOS 26.0, *)
@Generable(description: "A place item for a map template (US addresses only)")
struct LLMTemplatePlace {
    var name: String
    var streetAddress1: String
    var streetAddress2: String?
    var city: String
    var state: String?
    var postalCode: String?
    var country: String?
}

enum PlaceGenerationError: Error {
    case unsupportedPlatform
    case modelUnavailable
    case invalidResponse
}
#endif

struct LLMPlaceGenerator {
    static var isSupported: Bool {
        #if canImport(FoundationModels)
        if #available(iOS 26.0, macOS 26.0, *) {
            let model = SystemLanguageModel.default
            if case .available = model.availability { return true }
        }
        #endif
        return false
    }

    /// Generates a list of places as template items using Foundation Models
    /// - Parameters:
    ///   - userPrompt: Freeform instruction like "best pizza in Brooklyn" or "state capitol buildings"
    ///   - maxCount: Upper bound for number of items to return
    /// - Returns: An array of `TemplatePlace` and a flag indicating if PCC was used
    static func generatePlaces(userPrompt: String, maxCount: Int = 30) async throws -> ([TemplatePlace], usedPCC: Bool) {
        #if canImport(FoundationModels)
        if #available(iOS 26.0, macOS 26.0, *) {
            return try await generateWithFoundationModels(userPrompt: userPrompt, maxCount: maxCount)
        }
        #endif
        // Foundation Models not available - throw error
        throw NSError(domain: "LLMPlaceGenerator", code: -1, userInfo: [
            NSLocalizedDescriptionKey: "Foundation Models not available on this SDK"
        ])
    }
    
    #if canImport(FoundationModels)
    @available(iOS 26.0, macOS 26.0, *)
    private static func generateWithFoundationModels(userPrompt: String, maxCount: Int) async throws -> ([TemplatePlace], usedPCC: Bool) {
        let model = SystemLanguageModel.default
        guard case .available = model.availability else { throw PlaceGenerationError.modelUnavailable }

        // Keep the prompt concise and instruction-oriented; @Generable enforces schema
        let bounded = max(1, min(maxCount, 100))
        let instructions = """
        You are an expert in finding recommended places around. You come up with real and verifiable places for the user's request.
        
        You have access to a 'search_location' tool that can search for specific places and return verified addresses.
        Use this tool when you're not confident about exact address details or need to verify a location.
        The tool is OPTIONAL - only use it if needed for verification. For well-known places, provide addresses directly.

        Return between 5 and \(bounded) unique places that best satisfy the request. Each place MUST include:
        - name: the official place or venue name
        - streetAddress1: REQUIRED - street number AND name (e.g., "123 Main Street", NOT just "Main Street")
        - streetAddress2: secondary unit like Suite/Floor if known, else omit
        - city: REQUIRED - city name (e.g., "Austin", "New York")
        - state: two-letter state code if in the US (e.g., "TX", "NY"); otherwise provide full region name
        - postalCode: 5-digit ZIP or ZIP+4 if known (e.g., "78701" or "78701-1234")
        - country: "United States" when applicable

        CRITICAL ADDRESS REQUIREMENTS:
        - streetAddress1 MUST contain a street number (digits) - never just the street name alone
        - city MUST be populated - never use "N/A", "Unknown", or leave blank
        - NEVER use placeholder values like "N/A", "TBD", "Unknown", "None"
        - Every address must be complete enough to mail a letter
        - If you can't find a complete address, DO NOT include that place

        Rules:
        - Prefer well-known or authoritative places consistent with the request
        - Ensure addresses are mailable-format and not duplicates
        - Do not include coordinates; only postal fields
        - If the prompt is regional (e.g., Austin coffee), focus results to that region
        - Output strictly as an array of objects per the requested schema
        - Be confident with well-known landmarks and businesses
        - ALWAYS use the search_location tool to verify addresses
        """
        
        // Create session with tool support
        let tool = LocationSearchToolFM()
        let session = LanguageModelSession(tools: [tool], instructions: instructions)

        let response = try await session.respond(
            to: userPrompt,
            generating: [LLMTemplatePlace].self
        )

        // Convert to TemplatePlace for downstream template-conversion and geocoding
        let items: [TemplatePlace] = response.content.map { item in
            TemplatePlace(
                name: item.name,
                streetAddress1: item.streetAddress1,
                streetAddress2: item.streetAddress2,
                city: item.city,
                state: item.state,
                postalCode: item.postalCode,
                country: item.country
            )
        }

        // NOTE: In a full implementation we would reflect PCC usage via the FM APIs.
        // For now, assume on-device availability; set usedPCC to false.
        return (items, false)
    }
    #endif
}
