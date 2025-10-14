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
    static func convertToExtractedAddresses(_ places: [TemplatePlace]) -> [ExtractedAddress] {
        places.map { convertToExtractedAddress($0) }
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

