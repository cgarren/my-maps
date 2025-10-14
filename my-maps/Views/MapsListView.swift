import SwiftUI
import SwiftData

struct MapsListView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \MapCollection.name) private var maps: [MapCollection]
    @State private var isPresentingNewMap = false

    var body: some View {
        NavigationStack {
            List {
                if maps.isEmpty {
                    Section {
                    Text("No maps found")
                            .foregroundStyle(.secondary)
                    }
                    Section {
                        Button("Create a map") { isPresentingNewMap = true }
                    }
                } else {
                    ForEach(maps) { map in
                        NavigationLink {
                            MapDetailView(map: map)
                        } label: {
                            HStack(spacing: 12) {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(map.name)
                                        .font(.headline)
                                    if map.totalCount > 0 {
                                        Text("\(map.visitedCount) of \(map.totalCount) visited")
                                            .foregroundStyle(.secondary)
                                            .font(.subheadline)
                                    } else {
                                        Text("No places yet")
                                            .foregroundStyle(.tertiary)
                                            .font(.subheadline)
                                    }
                                }
                                Spacer()
                                VStack(alignment: .trailing, spacing: 6) {
                                    Text("\(map.completionPercent)%")
                                        .monospacedDigit()
                                        .font(.subheadline)
                                        .foregroundStyle(.secondary)
                                    ProgressView(value: map.completionFraction)
                                        .frame(width: 80)
                                }
                            }
                        }
                    }
                    .onDelete { indexSet in
                        indexSet.map { maps[$0] }.forEach(modelContext.delete)
                    }
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


