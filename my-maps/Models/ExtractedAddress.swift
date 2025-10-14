import Foundation
import CoreLocation

enum GeocodeStatus: Equatable {
    case pending
    case resolving
    case resolved
    case failed
}

struct ExtractedAddress: Identifiable, Hashable {
    let id: UUID
    var displayName: String?
    var rawText: String
    var normalizedText: String
    // Parsed components (if available) to improve geocoding
    var city: String?
    var state: String?
    var postalCode: String?
    var latitude: Double?
    var longitude: Double?
    var geocodeStatus: GeocodeStatus

    init(id: UUID = UUID(), rawText: String, normalizedText: String, displayName: String? = nil, city: String? = nil, state: String? = nil, postalCode: String? = nil) {
        self.id = id
        self.displayName = displayName
        self.rawText = rawText
        self.normalizedText = normalizedText
        self.city = city
        self.state = state
        self.postalCode = postalCode
        self.latitude = nil
        self.longitude = nil
        self.geocodeStatus = .pending
    }

    var coordinate: CLLocationCoordinate2D? {
        guard let lat = latitude, let lon = longitude else { return nil }
        return CLLocationCoordinate2D(latitude: lat, longitude: lon)
    }
}


