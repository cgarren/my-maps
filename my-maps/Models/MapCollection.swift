import Foundation
import SwiftData

@Model
final class MapCollection: Identifiable {
    var id: UUID
    var name: String
    @Relationship(deleteRule: .cascade) var places: [Place]

    init(id: UUID = UUID(), name: String, places: [Place] = []) {
        self.id = id
        self.name = name
        self.places = places
    }
}


