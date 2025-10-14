import SwiftUI
import SwiftData
import CoreLocation

struct NewMapSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @State private var name: String = ""
    @FocusState private var isNameFocused: Bool
    @State private var urlString: String = ""
    @State private var isImporting: Bool = false
    @State private var showReview: Bool = false
    @State private var createdMap: MapCollection? = nil
    @StateObject private var importer = URLImporter()

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

                // Optional URL field (Apple Intelligence only)
                Section {
                    let fmSupported = AIAddressExtractor.isSupported
                    TextField("Import from URL (optional)", text: $urlString)
                        #if os(iOS)
                        .keyboardType(.URL)
                        .textInputAutocapitalization(.never)
                        .disableAutocorrection(true)
                        #endif
                        .disabled(!fmSupported)
                    if !fmSupported {
                        Text("URL import requires Apple Intelligence on this device.")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                }
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
        .sheet(isPresented: $isImporting) {
            ImportProgressView(importer: importer, onCancel: {
                importer.cancel()
                isImporting = false
            }, onPaste: { text in
                importer.startFromText(text, allowPCC: true)
            })
        }
        .sheet(isPresented: $showReview) {
            SelectAddressesSheet(importer: importer, usedPCC: importer.usedPCC, onConfirm: { selected in
                guard let map = createdMap else { return }
                for item in selected {
                    guard let coord = item.coordinate else { continue }
                    let trimmedName = item.displayName?.trimmingCharacters(in: .whitespacesAndNewlines)
                    let preferredName = (trimmedName?.isEmpty == false) ? trimmedName : nil
                    let title = preferredName ?? item.normalizedText.components(separatedBy: "\n").first ?? "New Place"
                    let place = Place(name: title, latitude: coord.latitude, longitude: coord.longitude, map: map)
                    modelContext.insert(place)
                    map.places.append(place)
                }
                isImporting = false
                showReview = false
                dismiss()
            }, onCancel: {
                isImporting = false
                showReview = false
            }, onPaste: { text in
                // Restart pipeline using pasted text
                showReview = false
                isImporting = true
                importer.startFromText(text, allowPCC: true)
            })
        }
        .onReceive(importer.$stage) { stage in
            switch stage {
            case .reviewing:
                isImporting = false
                showReview = true
            default:
                break
            }
        }
    }

    private func create() {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let map = MapCollection(name: trimmed.isEmpty ? "Untitled Map" : trimmed)
        modelContext.insert(map)
        createdMap = map

        let urlTrimmed = urlString.trimmingCharacters(in: .whitespacesAndNewlines)
        if !urlTrimmed.isEmpty, AIAddressExtractor.isSupported, URL(string: urlTrimmed) != nil {
            isImporting = true
            importer.start(urlString: urlTrimmed, allowPCC: true)
        } else {
            dismiss()
        }
    }
}


