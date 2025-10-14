import SwiftUI
import SwiftData

struct MapsListView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \MapCollection.name) private var maps: [MapCollection]
    @State private var isPresentingNewMap = false

    var body: some View {
        NavigationStack {
            List {
                ForEach(maps) { map in
                    NavigationLink(map.name) { MapDetailView(map: map) }
                }
                .onDelete { indexSet in
                    indexSet.map { maps[$0] }.forEach(modelContext.delete)
                }
            }
            .navigationTitle("My Maps")
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button { isPresentingNewMap = true } label: { Label("New Map", systemImage: "plus") }
                }
            }
        }
        .sheet(isPresented: $isPresentingNewMap) {
            NewMapSheet()
        }
    }
}


