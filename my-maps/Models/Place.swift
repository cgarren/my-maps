import Foundation
import SwiftData

@Model
final class Place: Identifiable {
    var id: UUID
    var name: String
    var latitude: Double
    var longitude: Double
    var visited: Bool
    @Relationship(inverse: \MapCollection.places) var map: MapCollection?

    init(id: UUID = UUID(), name: String, latitude: Double, longitude: Double, visited: Bool = false, map: MapCollection? = nil) {
        self.id = id
        self.name = name
        self.latitude = latitude
        self.longitude = longitude
        self.visited = visited
        self.map = map
    }
}


