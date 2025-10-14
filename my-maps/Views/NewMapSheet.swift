import SwiftUI
import SwiftData

struct NewMapSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @State private var name: String = ""
    @FocusState private var isNameFocused: Bool

    var body: some View {
        NavigationStack {
            Form {
                TextField("Map Name", text: $name)
                #if os(iOS)
                    .textInputAutocapitalization(.words)
                #endif
                    .focused($isNameFocused)
                .padding()
                .onSubmit { create() }
            }
            .navigationTitle("New Map")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .cancellationAction) {
                    EmptyView()
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Create") { create() }
                        .disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
        }
        .frame(minWidth: 320, minHeight: 150)
        .task { isNameFocused = true }
    }

    private func create() {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let map = MapCollection(name: trimmed.isEmpty ? "Untitled Map" : trimmed)
        modelContext.insert(map)
        dismiss()
    }
}


