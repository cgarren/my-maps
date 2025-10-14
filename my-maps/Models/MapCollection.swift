import Foundation
import SwiftData

@Model
final class MapCollection: Identifiable {
    var id: UUID
    var name: String
    @Relationship(deleteRule: .cascade) var places: [Place]

    // Computed completion metrics (not persisted)
    var totalCount: Int { places.count }
    var visitedCount: Int { places.filter { $0.visited }.count }
    var completionFraction: Double {
        guard totalCount > 0 else { return 0 }
        return Double(visitedCount) / Double(totalCount)
    }
    var completionPercent: Int { Int((completionFraction * 100).rounded()) }

    init(id: UUID = UUID(), name: String, places: [Place] = []) {
        self.id = id
        self.name = name
        self.places = places
    }
}


