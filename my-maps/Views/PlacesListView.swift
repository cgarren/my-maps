import SwiftUI
import SwiftData

struct PlacesListView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @Bindable var map: MapCollection

    private var sortedPlaces: [Place] {
        map.places.sorted { lhs, rhs in
            if lhs.visited != rhs.visited {
                // Visited first
                return lhs.visited && !rhs.visited
            }
            // Then alphabetical by name
            return lhs.name.localizedCaseInsensitiveCompare(rhs.name) == .orderedAscending
        }
    }

    var body: some View {
        List {
            ForEach(sortedPlaces, id: \.id) { place in
                NavigationLink(value: place) {
                    HStack(spacing: 12) {
                        Image(systemName: place.visited ? "checkmark.circle.fill" : "circle")
                            .foregroundStyle(place.visited ? .green : .secondary)
                        Text(place.name)
                            .foregroundStyle(.primary)
                    }
                }
                .swipeActions(edge: .leading, allowsFullSwipe: true) {
                    Button {
                        place.visited.toggle()
                    } label: {
                        Label(place.visited ? "Unvisit" : "Visit", systemImage: place.visited ? "xmark.circle" : "checkmark.circle")
                    }
                    .tint(place.visited ? .orange : .green)
                }
                .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                    Button(role: .destructive) {
                        deletePlaces([place])
                    } label: {
                        Label("Delete", systemImage: "trash")
                    }
                }
            }
            .onDelete { offsets in
                let toDelete: [Place] = offsets.map { sortedPlaces[$0] }
                deletePlaces(toDelete)
            }
        }
        #if os(iOS)
        .listStyle(.insetGrouped)
        #else
        .listStyle(.inset)
        #endif
        .navigationTitle("Places")
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
        .toolbar {
            #if os(iOS)
            ToolbarItem(placement: .topBarLeading) { EditButton() }
            ToolbarItem(placement: .topBarTrailing) {
                Button("Done") { dismiss() }
            }
            #else
            ToolbarItem(placement: .automatic) {
                Button("Done") { dismiss() }
            }
            #endif
        }
        .navigationDestination(for: Place.self) { place in
            PlaceDetailView(place: place)
        }
        #if os(macOS)
        .frame(minWidth: 400, minHeight: 400)
        #endif
    }

    private func deletePlaces(_ places: [Place]) {
        for place in places {
            if let index = map.places.firstIndex(where: { $0.id == place.id }) {
                map.places.remove(at: index)
            }
            modelContext.delete(place)
        }
    }
}
