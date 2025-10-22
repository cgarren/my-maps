import Foundation
import MapKit
import CoreLocation

/// Tool for searching locations and retrieving their addresses
/// Can be called by AI models (Gemini or Apple FM) to verify addresses
struct LocationSearchTool {
    
    /// Result from a location search
    struct SearchResult: Codable {
        let name: String
        let streetAddress: String
        let city: String
        let state: String
        let postalCode: String
        let country: String
        let latitude: Double
        let longitude: Double
        
        var formattedAddress: String {
            var parts = [streetAddress, city, state, postalCode, country]
            parts.removeAll { $0.isEmpty }
            return parts.joined(separator: ", ")
        }
    }
    
    enum SearchError: Error {
        case noResults
        case invalidQuery
        case searchFailed(String)
    }
    
    /// Searches for a location by name and returns its address
    /// - Parameter locationName: The name of the place to search for (e.g., "Central Park New York" or "Space Needle Seattle")
    /// - Returns: A SearchResult containing the address details
    static func searchLocation(locationName: String) async throws -> SearchResult {
        let trimmed = locationName.trimmingCharacters(in: .whitespacesAndNewlines)
        
        // Log tool invocation
        print("🔧 [\(#function)] Tool called with input: \"\(trimmed)\"")
        
        guard !trimmed.isEmpty else {
            throw SearchError.invalidQuery
        }
        
        // Use MKLocalSearch to find the location
        let request = MKLocalSearch.Request()
        request.naturalLanguageQuery = trimmed
        
        // Bias search to US if not specified
        let usCenter = CLLocationCoordinate2D(latitude: 39.8283, longitude: -98.5795)
        request.region = MKCoordinateRegion(
            center: usCenter,
            span: MKCoordinateSpan(latitudeDelta: 30, longitudeDelta: 60)
        )
        
        let search = MKLocalSearch(request: request)
        
        do {
            let response = try await search.start()
            
            guard let firstResult = response.mapItems.first else {
                throw SearchError.noResults
            }
            
            let placemark = firstResult.placemark
            let coordinate = placemark.coordinate
            
            // Extract address components
            let name = firstResult.name ?? placemark.name ?? trimmed
            let street = [placemark.subThoroughfare, placemark.thoroughfare]
                .compactMap { $0 }
                .joined(separator: " ")
            let city = placemark.locality ?? ""
            let state = placemark.administrativeArea ?? ""
            let postalCode = placemark.postalCode ?? ""
            let country = placemark.country ?? ""
            
            let result = SearchResult(
                name: name,
                streetAddress: street,
                city: city,
                state: state,
                postalCode: postalCode,
                country: country,
                latitude: coordinate.latitude,
                longitude: coordinate.longitude
            )
            
            // Log successful result
            print("✅ [\(#function)] Found: \"\(result.name)\" at \(result.formattedAddress)")
            
            return result
        } catch {
            // Log failure
            print("❌ [\(#function)] Search failed: \(error.localizedDescription)")
            throw SearchError.searchFailed(error.localizedDescription)
        }
    }
    
    /// Gemini function declaration for tool calling
    static var geminiFunctionDeclaration: [String: Any] {
        [
            "name": "search_location",
            "description": "Searches for a location by name and returns its verified address. Use this when you need to verify an address or when you're not confident about the exact address details. The search works best with specific place names (e.g., 'Space Needle Seattle' or 'Central Park New York').",
            "parameters": [
                "type": "OBJECT",
                "properties": [
                    "location_name": [
                        "type": "STRING",
                        "description": "The name of the location to search for. Include the city or region for better results (e.g., 'Blue Bottle Coffee San Francisco' or 'Pike Place Market Seattle')."
                    ]
                ],
                "required": ["location_name"]
            ]
        ]
    }
}

