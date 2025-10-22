import Foundation
#if canImport(FoundationModels)
import FoundationModels
#endif

/// Availability state for AI providers
enum AIProviderAvailability {
    case available              // Ready to use
    case needsConfiguration     // Requires user action (API key, enabling in Settings)
    case unavailable           // Not supported on this device/OS
    
    var isUsable: Bool {
        switch self {
        case .available, .needsConfiguration:
            return true
        case .unavailable:
            return false
        }
    }
}

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
            return "On-device AI using Apple Intelligence"
        case .gemini:
            return "Cloud-based AI using Google Gemini API"
        }
    }
    
    /// Detailed availability state for this provider
    var availabilityState: AIProviderAvailability {
        switch self {
        case .appleFM:
            #if canImport(FoundationModels)
            if #available(iOS 26.0, macOS 26.0, *) {
                let model = SystemLanguageModel.default
                // Check if the model is available
                if case .available = model.availability {
                    return .available
                } else {
                    // Model exists but not available - could be downloading or needs enabling
                    // Since the device/OS supports it, this is a configuration issue
                    return .needsConfiguration
                }
            }
            #endif
            // OS/SDK doesn't support Foundation Models
            return .unavailable
            
        case .gemini:
            if GeminiPlaceGenerator.isConfigured {
                return .available
            } else {
                // Gemini works on any device, just needs API key
                return .needsConfiguration
            }
        }
    }
    
    /// Simple availability check (backward compatibility)
    var isAvailable: Bool {
        return availabilityState == .available
    }
    
    /// Status message for unavailable/needs configuration states
    var statusMessage: String {
        switch availabilityState {
        case .available:
            return "Ready to use"
        case .needsConfiguration:
            switch self {
            case .appleFM:
                return "Enable Apple Intelligence in System Settings"
            case .gemini:
                return "API key required"
            }
        case .unavailable:
            switch self {
            case .appleFM:
                return "Requires iOS 26+ or macOS 26+ and a compatible device"
            case .gemini:
                return "Not available"
            }
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

