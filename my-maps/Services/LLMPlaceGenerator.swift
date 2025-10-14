import Foundation
import FoundationModels

/// Internal generable type used to ensure the model returns structured output
@Generable(description: "A place item for a map template (US addresses only)")
struct LLMTemplatePlace: Sendable {
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

struct LLMPlaceGenerator {
    static var isSupported: Bool {
        if #available(iOS 18, macOS 15, *) {
            let model = SystemLanguageModel.default
            if case .available = model.availability { return true }
        }
        return false
    }

    /// Generates a list of places as template items using Foundation Models
    /// - Parameters:
    ///   - userPrompt: Freeform instruction like "best pizza in Brooklyn" or "state capitol buildings"
    ///   - maxCount: Upper bound for number of items to return
    /// - Returns: An array of `TemplatePlace` and a flag indicating if PCC was used
    static func generatePlaces(userPrompt: String, maxCount: Int = 30) async throws -> ([TemplatePlace], usedPCC: Bool) {
        guard #available(iOS 18, macOS 15, *) else { throw PlaceGenerationError.unsupportedPlatform }

        let model = SystemLanguageModel.default
        guard case .available = model.availability else { throw PlaceGenerationError.modelUnavailable }

        let session = LanguageModelSession()

        // Keep the prompt concise and instruction-oriented; @Generable enforces schema
        let bounded = max(1, min(maxCount, 100))
        let prompt = """
        You are Applied Intelligence using Private Cloud Compute. Generate realistic, verifiable US places for the user's request.

        Return between 5 and \(bounded) unique places that best satisfy the request. Each place MUST include:
        - name: the official place or venue name
        - streetAddress1: street number and name (required)
        - streetAddress2: secondary unit like Suite/Floor if known, else omit
        - city: city name
        - state: two-letter state code if in the US; otherwise provide full region name
        - postalCode: 5-digit or ZIP+4 if known
        - country: "United States" when applicable

        Rules:
        - Prefer well-known or authoritative places consistent with the request
        - Ensure addresses are mailable-format and not duplicates
        - Do not include coordinates; only postal fields
        - If the prompt is regional (e.g., Austin coffee), focus results to that region
        - Output strictly as an array of objects per the requested schema

        User request:
        \(userPrompt)
        """

        let response = try await session.respond(
            to: prompt,
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
}

import Foundation
import FoundationModels

@Generable(description: "A place suitable for a map template with full postal address")
struct LLMTemplatePlace {
    var name: String
    var streetAddress1: String
    var streetAddress2: String?
    var city: String
    var state: String?
    var postalCode: String?
    var country: String?
}

struct LLMPlaceGenerator {
    struct Result {
        let places: [TemplatePlace]
        let usedPCC: Bool
    }
    
    static var isSupported: Bool {
        if #available(iOS 18, macOS 15, *) {
            let model = SystemLanguageModel.default
            if case .available = model.availability { return true }
        }
        return false
    }
    
    @discardableResult
    static func generatePlaces(for query: String, targetCount: Int = 20) async throws -> Result {
        guard #available(iOS 18, macOS 15, *) else {
            throw ExtractionError.unsupportedPlatform
        }
        let model = SystemLanguageModel.default
        guard case .available = model.availability else {
            throw ExtractionError.modelUnavailable
        }
        
        let session = LanguageModelSession()
        
        let boundedCount = max(5, min(50, targetCount))
        
        let prompt = """
        You are Applied Intelligence Private Cloud Compute. Generate a high-quality list of unique, real places in the United States matching the request below. For each place include:
        - name: The display name (organization, venue, office, or landmark)
        - streetAddress1: Street number and name
        - streetAddress2: Optional suite/floor/building
        - city: City name
        - state: 2-letter state code when in the U.S. (may be omitted for territories if unknown)
        - postalCode: 5-digit or ZIP+4 if available
        - country: Always "United States" when applicable
        
        Requirements:
        - Return between 10 and \(boundedCount) items depending on availability
        - Prefer authoritative or well-known locations relevant to the request
        - Avoid duplicates and PO boxes
        - Ensure addresses are complete and geocodable
        - If a field is unknown, omit it rather than guessing
        - Focus on U.S. results unless the request specifies otherwise
        
        Request: \(query)
        """
        
        let response = try await session.respond(
            to: prompt,
            generating: [LLMTemplatePlace].self
        )
        
        let mapped: [TemplatePlace] = response.content.map { p in
            TemplatePlace(
                name: p.name,
                streetAddress1: p.streetAddress1,
                streetAddress2: p.streetAddress2,
                city: p.city,
                state: p.state,
                postalCode: p.postalCode,
                country: p.country
            )
        }
        
        // NOTE: Detecting exact PCC usage is not currently exposed; default to false.
        // System may route via on-device or PCC per platform policy.
        return Result(places: mapped, usedPCC: false)
    }
}
