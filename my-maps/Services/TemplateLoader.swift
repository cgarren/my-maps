import Foundation

enum TemplateLoaderError: Error {
    case metadataNotFound
    case templateFileNotFound
    case decodingFailed
}

struct TemplateLoader {
    /// Returns list of available templates from templates.json metadata file
    static func availableTemplates() -> [MapTemplate] {
        guard let url = Bundle.main.url(forResource: "templates", withExtension: "json"),
              let data = try? Data(contentsOf: url),
              let templates = try? JSONDecoder().decode([MapTemplate].self, from: data) else {
            return []
        }
        return templates
    }
    
    /// Loads places from a template and converts them to ExtractedAddress objects
    static func loadPlaces(from template: MapTemplate) throws -> [ExtractedAddress] {
        guard let url = Bundle.main.url(forResource: template.fileName, withExtension: "json") else {
            throw TemplateLoaderError.templateFileNotFound
        }
        
        let data = try Data(contentsOf: url)
        let places = try JSONDecoder().decode([TemplatePlace].self, from: data)
        
        return places.map { place in
            convertToExtractedAddress(place)
        }
    }
    
    /// Converts an array of `TemplatePlace` to `ExtractedAddress` format
    /// Exposed for use by AI-generated template flows
    /// Filters out places with incomplete or invalid addresses
    static func convertToExtractedAddresses(_ places: [TemplatePlace]) -> [ExtractedAddress] {
        var validPlaces: [ExtractedAddress] = []
        var filteredCount = 0
        
        for place in places {
            // Validate the place has all required address components
            if let reason = validatePlace(place) {
                filteredCount += 1
                print("⚠️ [TemplateLoader] Filtered out '\(place.name)': \(reason)")
                continue
            }
            
            // Convert valid place
            validPlaces.append(convertToExtractedAddress(place))
        }
        
        if filteredCount > 0 {
            print("📋 [TemplateLoader] Filtered \(filteredCount) place(s) with incomplete addresses. Kept \(validPlaces.count) valid places.")
        } else {
            print("✅ [TemplateLoader] All \(validPlaces.count) places have complete addresses.")
        }
        
        return validPlaces
    }
    
    /// Validates that a place has all required address components
    /// - Parameter place: The place to validate
    /// - Returns: A string describing the validation failure, or nil if valid
    private static func validatePlace(_ place: TemplatePlace) -> String? {
        // 1. Validate street address
        let street = place.streetAddress1.trimmingCharacters(in: .whitespacesAndNewlines)
        if street.isEmpty {
            return "Missing street address"
        }
        
        // Check that street address contains at least one digit (e.g., "123 Main St")
        if !street.contains(where: { $0.isNumber }) {
            return "Street address '\(street)' missing street number"
        }
        
        // Check for placeholder values
        let invalidPlaceholders = ["n/a", "na", "unknown", "tbd", "none", "null"]
        if invalidPlaceholders.contains(street.lowercased()) {
            return "Street address is placeholder: '\(street)'"
        }
        
        // 2. Validate city
        let city = place.city.trimmingCharacters(in: .whitespacesAndNewlines)
        if city.isEmpty {
            return "Missing city"
        }
        
        if invalidPlaceholders.contains(city.lowercased()) {
            return "City is placeholder: '\(city)'"
        }
        
        // 3. Validate state (optional but should be valid if present)
        if let state = place.state {
            let trimmedState = state.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmedState.isEmpty {
                // If state is provided, check it's reasonable (2-3 characters for US, or full name)
                if trimmedState.count == 1 || invalidPlaceholders.contains(trimmedState.lowercased()) {
                    return "Invalid state: '\(trimmedState)'"
                }
            }
        }
        
        // 4. Validate postal code (optional but should be valid if present)
        if let postalCode = place.postalCode {
            let trimmedPostal = postalCode.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmedPostal.isEmpty {
                // Check for placeholder values
                if invalidPlaceholders.contains(trimmedPostal.lowercased()) {
                    return "Postal code is placeholder: '\(trimmedPostal)'"
                }
                
                // US ZIP codes should be 5 digits or 5+4 format
                let zipPattern = "^\\d{5}(-\\d{4})?$"
                if let regex = try? NSRegularExpression(pattern: zipPattern),
                   regex.firstMatch(in: trimmedPostal, range: NSRange(trimmedPostal.startIndex..., in: trimmedPostal)) == nil {
                    // Allow non-US postal codes (letters and numbers), but not pure placeholders
                    if !trimmedPostal.contains(where: { $0.isLetter || $0.isNumber }) {
                        return "Invalid postal code format: '\(trimmedPostal)'"
                    }
                }
            }
        }
        
        // 5. Validate country (optional but should be valid if present)
        if let country = place.country {
            let trimmedCountry = country.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmedCountry.isEmpty && invalidPlaceholders.contains(trimmedCountry.lowercased()) {
                return "Country is placeholder: '\(trimmedCountry)'"
            }
        }
        
        // All validations passed
        return nil
    }
    
    /// Converts a TemplatePlace to ExtractedAddress format
    private static func convertToExtractedAddress(_ place: TemplatePlace) -> ExtractedAddress {
        var addressLines: [String] = []
        
        // Add street addresses
        addressLines.append(place.streetAddress1)
        if let street2 = place.streetAddress2, !street2.isEmpty {
            addressLines.append(street2)
        }
        
        // Build city, state, zip line
        var cityStateZip: [String] = []
        cityStateZip.append(place.city)
        if let state = place.state, !state.isEmpty {
            cityStateZip.append(state)
        }
        if let postalCode = place.postalCode, !postalCode.isEmpty {
            cityStateZip.append(postalCode)
        }
        
        if !cityStateZip.isEmpty {
            addressLines.append(cityStateZip.joined(separator: ", "))
        }
        
        // Add country if present
        if let country = place.country, !country.isEmpty {
            addressLines.append(country)
        }
        
        let normalizedText = addressLines.joined(separator: "\n")
        
        return ExtractedAddress(
            rawText: normalizedText,
            normalizedText: normalizedText,
            displayName: place.name,
            city: place.city,
            state: place.state,
            postalCode: place.postalCode
        )
    }
}

