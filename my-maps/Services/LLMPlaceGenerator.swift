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
