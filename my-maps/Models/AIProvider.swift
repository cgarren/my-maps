import Foundation

/// Represents the AI provider to use for place generation
enum AIProvider: String, Codable, CaseIterable, Identifiable {
    case appleFM = "Apple Foundation Models"
    case gemini = "Google Gemini"
    
    var id: String { rawValue }
    
    var displayName: String {
        switch self {
        case .appleFM:
            return "Apple Intelligence"
        case .gemini:
            return "Google Gemini"
        }
    }
    
    var description: String {
        switch self {
        case .appleFM:
            return "On-device AI using Apple Intelligence (iOS 18+)"
        case .gemini:
            return "Cloud-based AI using Google Gemini API"
        }
    }
    
    var isAvailable: Bool {
        switch self {
        case .appleFM:
            return LLMPlaceGenerator.isSupported
        case .gemini:
            return GeminiPlaceGenerator.isConfigured
        }
    }
    
    var requiresAPIKey: Bool {
        switch self {
        case .appleFM:
            return false
        case .gemini:
            return true
        }
    }
}

/// UserDefaults key for storing the selected AI provider
extension UserDefaults {
    private static let aiProviderKey = "selected_ai_provider"
    
    var selectedAIProvider: AIProvider {
        get {
            guard let rawValue = string(forKey: Self.aiProviderKey),
                  let provider = AIProvider(rawValue: rawValue) else {
                return .appleFM // Default to Apple FM
            }
            return provider
        }
        set {
            set(newValue.rawValue, forKey: Self.aiProviderKey)
        }
    }
}

