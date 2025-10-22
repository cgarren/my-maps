import SwiftUI
import SwiftData

struct MapsListView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \MapCollection.name) private var maps: [MapCollection]
    @State private var isPresentingNewMap = false
    @State private var renamingMap: MapCollection? = nil
    @State private var renameText: String = ""
    @State private var mapToDelete: MapCollection? = nil
    @State private var showSettings = false

    var body: some View {
        NavigationStack {
            List {
                if maps.isEmpty {
                    Section {
                        Text("No maps found")
                            .foregroundStyle(.secondary)
                            #if os(macOS)
                            .padding(.vertical, 8)
                            #endif
                    }
                    Section {
                        Button("Create a map") { isPresentingNewMap = true }
                            #if os(macOS)
                            .buttonStyle(.borderless)
                            #endif
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
                            #if os(macOS)
                            .padding(.vertical, 6)
                            #endif
                        }
                        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                            Button(role: .destructive) {
                                mapToDelete = map
                            } label: {
                                Label("Delete", systemImage: "trash")
                            }
                        }
                        .swipeActions(edge: .leading, allowsFullSwipe: false) {
                            Button {
                                renameText = map.name
                                renamingMap = map
                            } label: {
                                Label("Rename", systemImage: "pencil")
                            }
                            .tint(.blue)
                        }
                    }
                }
            }
            .navigationTitle("My Maps")
            .toolbar {
                ToolbarItem(placement: .automatic) {
                    Button {
                        showSettings = true
                    } label: {
                        #if os(macOS)
                        Label("Settings", systemImage: "gearshape")
                        #else
                        Label("AI Settings", systemImage: "gearshape")
                        #endif
                    }
                    #if os(macOS)
                    .help("Configure AI provider and API keys")
                    #endif
                }
                ToolbarItem(placement: .primaryAction) {
                    Button { isPresentingNewMap = true } label: { Label("New Map", systemImage: "plus") }
                }
            }
        }
        .sheet(isPresented: $isPresentingNewMap) {
            NewMapSheet()
        }
        .alert("Rename Map", isPresented: Binding(
            get: { renamingMap != nil },
            set: { if !$0 { renamingMap = nil } }
        )) {
            TextField("Map Name", text: $renameText)
                #if os(iOS)
                .textInputAutocapitalization(.words)
                #endif
            Button("Cancel", role: .cancel) {
                renamingMap = nil
                renameText = ""
            }
            Button("Rename") {
                if let map = renamingMap {
                    let trimmed = renameText.trimmingCharacters(in: .whitespacesAndNewlines)
                    if !trimmed.isEmpty {
                        map.name = trimmed
                    }
                }
                renamingMap = nil
                renameText = ""
            }
            .disabled(renameText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        } message: {
            Text("Enter a new name for this map")
        }
        .alert("Delete Map", isPresented: Binding(
            get: { mapToDelete != nil },
            set: { if !$0 { mapToDelete = nil } }
        )) {
            Button("Cancel", role: .cancel) {
                mapToDelete = nil
            }
            Button("Delete", role: .destructive) {
                if let map = mapToDelete {
                    modelContext.delete(map)
                }
                mapToDelete = nil
            }
        } message: {
            if let map = mapToDelete {
                Text("Are you sure you want to delete \"\(map.name)\"? This action cannot be undone.")
            }
        }
        .sheet(isPresented: $showSettings) {
            SettingsView()
        }
    }
}


