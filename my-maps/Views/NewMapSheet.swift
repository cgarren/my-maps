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
    @State private var selectedTemplate: MapTemplate? = nil
    @State private var availableTemplates: [MapTemplate] = []
    @StateObject private var importer = URLImporter()

    var body: some View {
        NavigationStack {
            Form {
                TextField("Map Name", text: $name)
                #if os(iOS)
                    .textInputAutocapitalization(.words)
                #endif
                    .focused($isNameFocused)
                // .padding()
                .onSubmit { create() }

                // Template selection
                Section {
                    Picker("Template", selection: $selectedTemplate) {
                        Text("None").tag(nil as MapTemplate?)
                        ForEach(availableTemplates) { template in
                            Text(template.displayName).tag(template as MapTemplate?)
                        }
                    }
                    #if os(macOS)
                    .pickerStyle(.menu)
                    #endif
                } header: {
                    Text("Prefill from Template")
                } footer: {
                    Text("Choose a template to prefill your map with predefined places.")
                }
                
                let aiSupported = AIAddressExtractor.isSupported
                let templateSelected = selectedTemplate != nil

                // Optional URL field (AI-powered extraction)
                Section {
                    TextField("https://", text: $urlString)
                        #if os(iOS)
                        .keyboardType(.URL)
                        .textInputAutocapitalization(.never)
                        .disableAutocorrection(true)
                        #endif
                        .disabled(!aiSupported || templateSelected)
                } header: {
                    Text("Import from URL")
                }
                footer: {
                    if !aiSupported {
                        Text("URL import requires iOS 13+ or macOS 10.15+.")
                    } else if templateSelected {
                        Text("Disabled when using a template.")
                    } else {
                        Text("Uses AI for address extraction.")
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
        .onAppear {
            availableTemplates = TemplateLoader.availableTemplates()
        }
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

        // Priority 1: Template selection
        if let template = selectedTemplate {
            do {
                let places = try TemplateLoader.loadPlaces(from: template)
                isImporting = true
                importer.startFromTemplate(places)
            } catch {
                // If template loading fails, just create an empty map
                print("Failed to load template: \(error)")
                dismiss()
            }
            return
        }
        
        // Priority 2: URL import
        let urlTrimmed = urlString.trimmingCharacters(in: .whitespacesAndNewlines)
        if !urlTrimmed.isEmpty, AIAddressExtractor.isSupported, URL(string: urlTrimmed) != nil {
            isImporting = true
            importer.start(urlString: urlTrimmed, allowPCC: true)
        } else {
            // Priority 3: Empty map
            dismiss()
        }
    }
}


