import Foundation
#if canImport(FoundationModels)
import FoundationModels
#endif
import MapKit
import CoreLocation

/// Foundation Models Tool for searching locations
/// Conforms to the Tool protocol for use with LanguageModelSession
#if canImport(FoundationModels)
@available(iOS 26.0, macOS 26.0, *)
struct LocationSearchToolFM: Tool {
    let name = "search_location"
    let description = "Searches for a location by name and returns its verified address. Use this when you need to verify an address or when you're not confident about the exact address details. The search works best with specific place names (e.g., 'Space Needle Seattle' or 'Central Park New York')."
    
    @Generable(description: "Arguments for searching a location")
    struct Arguments {
        @Guide(description: "The name of the location to search for. Include the city or region for better results (e.g., 'Blue Bottle Coffee San Francisco' or 'Pike Place Market Seattle').")
        let locationName: String
    }
    
    func call(arguments: Arguments) async throws -> String {
        // Log tool invocation
        print("🔧 [Apple FM Tool] search_location called with input: \"\(arguments.locationName)\"")
        
        do {
            let result = try await LocationSearchTool.searchLocation(locationName: arguments.locationName)
            
            // Return formatted result as JSON string
            let resultDict: [String: Any] = [
                "name": result.name,
                "streetAddress": result.streetAddress,
                "city": result.city,
                "state": result.state,
                "postalCode": result.postalCode,
                "country": result.country,
                "latitude": result.latitude,
                "longitude": result.longitude
            ]
            
            let jsonData = try JSONSerialization.data(withJSONObject: resultDict, options: .prettyPrinted)
            let jsonString = String(data: jsonData, encoding: .utf8) ?? "{}"
            
            print("✅ [Apple FM Tool] Returning result: \(result.name) at \(await result.formattedAddress)")
            
            return jsonString
        } catch {
            print("❌ [Apple FM Tool] Search failed: \(error.localizedDescription)")
            
            // Return error as JSON
            let errorDict: [String: String] = [
                "error": error.localizedDescription
            ]
            let jsonData = try JSONSerialization.data(withJSONObject: errorDict)
            return String(data: jsonData, encoding: .utf8) ?? "{\"error\": \"Unknown error\"}"
        }
    }
}
#endif

