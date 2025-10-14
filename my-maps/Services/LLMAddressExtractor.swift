import Foundation
import FoundationModels

@Generable(description: "A US postal address extracted from text")
struct LLMExtractedAddress {
    var organizationName: String?
    var streetAddress: String
    var suite: String?
    var city: String
    var state: String
    var postalCode: String
    var country: String?
}

enum ExtractionError: Error {
    case unsupportedPlatform
    case modelUnavailable
    case invalidResponse
    
    var localizedDescription: String {
        switch self {
        case .unsupportedPlatform:
            return "Foundation Models requires iOS 18+ or macOS 15+"
        case .modelUnavailable:
            return "Apple Intelligence is not available on this device"
        case .invalidResponse:
            return "The model returned an invalid response"
        }
    }
}

struct LLMAddressExtractor {
    static var isSupported: Bool {
        if #available(iOS 18, macOS 15, *) {
            // Check if Apple Intelligence is available
            let model = SystemLanguageModel.default
            if case .available = model.availability {
                return true
            }
        }
        return false
    }
    
    static func extractAddresses(from text: String) async throws -> [ExtractedAddress] {
        guard #available(iOS 18, macOS 15, *) else {
            throw ExtractionError.unsupportedPlatform
        }
        
        let model = SystemLanguageModel.default
        guard case .available = model.availability else {
            throw ExtractionError.modelUnavailable
        }
        
        let session = LanguageModelSession()
        
        print("Analyzing text: \n\(text)")
        
        let prompt = """
        Extract all US postal addresses from the following text.
        For each address found, extract:
        - Organization/business name (if mentioned near the address)
        - Street address with number
        - Suite/floor number (if mentioned)
        - City
        - State (2-letter abbreviation)
        - Postal code (5 or 9 digits)
        
        If multiple addresses are present, extract all of them.
        Only extract addresses that appear to be complete and valid.
        ONly extract each exact address one time
        
        Text to analyze:
        \(text)
        """
        
        let response = try await session.respond(
            to: prompt,
            generating: [LLMExtractedAddress].self
        )
        
        print("Extracted \(response.content.count) addresses")
        print("LLM Addresses: \(response.content)")
        
        // Convert LLM output to ExtractedAddress format
        return response.content.map { llmAddr in
            convertToExtractedAddress(llmAddr)
        }
    }
    
    private static func convertToExtractedAddress(_ llm: LLMExtractedAddress) -> ExtractedAddress {
        var parts: [String] = []
        parts.append(llm.streetAddress)
        if let suite = llm.suite, !suite.isEmpty {
            parts.append(suite)
        }
        let csz = [llm.city, llm.state, llm.postalCode].joined(separator: ", ")
        parts.append(csz)
        if let country = llm.country, !country.isEmpty {
            parts.append(country)
        }
        
        let normalized = parts.joined(separator: "\n")
        
        return ExtractedAddress(
            rawText: normalized,
            normalizedText: normalized,
            displayName: llm.organizationName,
            city: llm.city,
            state: llm.state,
            postalCode: llm.postalCode
        )
    }
}

