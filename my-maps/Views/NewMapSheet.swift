import SwiftUI
import SwiftData
import CoreLocation

enum MapCreationMethod: Identifiable {
    case blank
    case template
    case url
    case ai
    
    var id: String {
        switch self {
        case .blank: return "blank"
        case .template: return "template"
        case .url: return "url"
        case .ai: return "ai"
        }
    }
    
    var title: String {
        switch self {
        case .blank: return "Start Blank"
        case .template: return "Use Template"
        case .url: return "Import from URL"
        case .ai: return "Generate with AI"
        }
    }
    
    var subtitle: String {
        switch self {
        case .blank: return "Create an empty map"
        case .template: return "Choose from predefined places"
        case .url: return "Extract places from a webpage"
        case .ai: return "Let AI find places for you"
        }
    }
    
    var icon: String {
        switch self {
        case .blank: return "map"
        case .template: return "doc.on.doc"
        case .url: return "link"
        case .ai: return "sparkles"
        }
    }
}

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
    @State private var aiQuery: String = ""
    @State private var isGenerating: Bool = false
    @State private var showSettings: Bool = false
    @AppStorage("selected_ai_provider") private var selectedProviderRaw: String = AIProvider.appleFM.rawValue
    @State private var selectedMethod: MapCreationMethod? = nil
    @State private var generationProgress: String = ""
    @State private var verifiedCount: Int = 0
    @State private var showErrorAlert: Bool = false
    @State private var errorMessage: String = ""
    
    private var selectedProvider: AIProvider {
        AIProvider(rawValue: selectedProviderRaw) ?? .appleFM
    }

    var body: some View {
        NavigationStack {
            if selectedMethod == nil {
                methodSelectionView
                    } else {
                configurationView
            }
        }
        #if os(macOS)
        .frame(minWidth: 500, idealWidth: 550, minHeight: 400, idealHeight: 500)
        #else
        .frame(minWidth: 320, minHeight: 150)
        #endif
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
        .sheet(isPresented: $showSettings) {
            SettingsView()
        }
        .alert("Generation Error", isPresented: $showErrorAlert) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(errorMessage)
        }
    }
    
    // MARK: - Method Selection View
    
    private var methodSelectionView: some View {
        List {
            Section {
                ForEach([MapCreationMethod.blank, .template, .ai, .url]) { method in
                    Button {
                        selectedMethod = method
                    } label: {
                        HStack(spacing: 16) {
                            Image(systemName: method.icon)
                                .font(.title2)
                                .foregroundColor(.accentColor)
                                .frame(width: 32)
                            
                            VStack(alignment: .leading, spacing: 4) {
                                Text(method.title)
                                    .font(.headline)
                                    .foregroundColor(.primary)
                                Text(method.subtitle)
                                    .font(.subheadline)
                                    .foregroundColor(.secondary)
                            }
                            
                            Spacer()
                            
                            Image(systemName: "chevron.right")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                        #if os(macOS)
                        .padding(.vertical, 8)
                        #endif
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .disabled(method == .url)
                    .opacity(method == .url ? 0.5 : 1.0)
                }
            } header: {
                Text("How would you like to start?")
            } footer: {
                Text("Import from URL is temporarily unavailable.")
            }
        }
        .navigationTitle("New Map")
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Cancel") { dismiss() }
            }
        }
    }
    
    // MARK: - Configuration View
    
    private var configurationView: some View {
        Form {
            Section {
                TextField("Map Name", text: $name)
                #if os(iOS)
                    .textInputAutocapitalization(.words)
                #elseif os(macOS)
                    .textFieldStyle(.roundedBorder)
                #endif
                    .focused($isNameFocused)
                    .onSubmit {
                        if canCreate {
                            create()
                        }
                    }
            }
            
            // Show different sections based on selected method
            if let method = selectedMethod {
                switch method {
                case .blank:
                    Section {
                        Text("Your map will start empty. You can add places manually after creation.")
                            .foregroundColor(.secondary)
                    }
                    
                case .template:
                    Section {
                        Picker("Template", selection: $selectedTemplate) {
                            Text("Select a template...").tag(nil as MapTemplate?)
                            ForEach(availableTemplates) { template in
                                Text(template.displayName).tag(template as MapTemplate?)
                            }
                        }
                        #if os(macOS)
                        .pickerStyle(.menu)
                        #endif
                    } header: {
                        Text("Choose Template")
                            .font(.headline)
                    } footer: {
                        Text("Your map will be prefilled with places from the selected template.")
                            .font(.caption)
                    }
                    
                case .url:
                    Section {
                        TextField("https://", text: $urlString)
                            #if os(iOS)
                            .keyboardType(.URL)
                            .textInputAutocapitalization(.never)
                            .disableAutocorrection(true)
                            #endif
                    } header: {
                        Text("Website URL")
                    } footer: {
                        Text("AI will extract addresses and locations from the webpage.")
                    }
                    
                case .ai:
                    Section {
                        VStack(alignment: .leading, spacing: 12) {
                            TextField("e.g. Top coffee shops in Austin", text: $aiQuery)
                                #if os(iOS)
                                .textInputAutocapitalization(.sentences)
                                .disableAutocorrection(false)
                                #elseif os(macOS)
                                .textFieldStyle(.roundedBorder)
                                #endif
                                .disabled(!selectedProvider.isAvailable || isGenerating)
                            
                            // Show progress when generating
                            if isGenerating {
                                VStack(alignment: .leading, spacing: 8) {
                                    HStack {
                                        ProgressView()
                                            .scaleEffect(0.8)
                                        Text(generationProgress)
                                            .font(.subheadline)
                                            .foregroundStyle(.secondary)
                                    }
                                    
                                    if verifiedCount > 0 {
                                        Text("Verified \(verifiedCount) places so far")
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                    }
                                }
                                .padding(.vertical, 4)
                            }
                        }
                    } header: {
                        Text("Describe What You Want")
                            .font(.headline)
                    } footer: {
                        VStack(alignment: .leading, spacing: 4) {
                            if !selectedProvider.isAvailable {
                                if selectedProvider == .appleFM {
                                    Text("Requires iOS 26+ or macOS 26+ with Apple Intelligence.")
                                } else {
                                    #if os(macOS)
                                    Text("Requires API key configuration. Click the settings button to configure.")
                                    #else
                                    Text("Requires API key configuration. Tap the settings button to configure.")
                                    #endif
                                }
                            } else if isGenerating {
                                Text("Generating and verifying places... This may take 20-30 seconds.")
                            } else {
                                Text("Uses \(selectedProvider.displayName) to generate places. You'll review results before adding to your map.")
                            }
                        }
                        .font(.caption)
                    }
                }
            }
        }
        .navigationTitle("New Map")
        #if os(macOS)
        .formStyle(.grouped)
        .padding(20)
        #endif
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Back") {
                    selectedMethod = nil
                }
            }
            
            if selectedMethod == .ai {
                #if os(iOS)
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        showSettings = true
                    } label: {
                        Label("AI Settings", systemImage: "gearshape")
                    }
                }
                #elseif os(macOS)
                ToolbarItem(placement: .automatic) {
                    Button {
                        showSettings = true
                    } label: {
                        Label("Settings", systemImage: "gearshape")
                    }
                    .help("Configure AI provider and API keys")
                }
                #endif
            }
            
            ToolbarItem(placement: .confirmationAction) {
                Button {
                    if selectedMethod == .ai && canGenerateWithAI {
                        Task { await generateWithAI() }
                    } else {
                        create()
                    }
                } label: {
                    if isGenerating {
                        ProgressView()
                    } else {
                        Text(selectedMethod == .ai ? "Generate" : "Create")
                    }
                }
                .disabled(!canCreate)
                #if os(macOS)
                .buttonStyle(.borderedProminent)
                #endif
            }
        }
        .task { isNameFocused = true }
    }
    
    // MARK: - Computed Properties
    
    private var canCreate: Bool {
        let hasName = !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        
        guard let method = selectedMethod else {
            return false
        }
        
        switch method {
        case .blank:
            return hasName
        case .template:
            return hasName && selectedTemplate != nil
        case .url:
            let hasURL = !urlString.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            return hasName && hasURL && AIAddressExtractor.isSupported
        case .ai:
            return hasName && canGenerateWithAI && !isGenerating
        }
    }
    
    private var canGenerateWithAI: Bool {
        let hasQuery = !aiQuery.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        return selectedProvider.isAvailable && hasQuery
    }
    
    // MARK: - Methods

    private func create() {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let map = MapCollection(name: trimmed.isEmpty ? "Untitled Map" : trimmed)
        modelContext.insert(map)
        createdMap = map

        guard let method = selectedMethod else {
            dismiss()
            return
        }
        
        switch method {
        case .blank:
            // Just create an empty map and dismiss
            dismiss()
            
        case .template:
            // Load places from template
        if let template = selectedTemplate {
            do {
                let places = try TemplateLoader.loadPlaces(from: template)
                isImporting = true
                importer.startFromTemplate(places)
            } catch {
                print("Failed to load template: \(error)")
                dismiss()
            }
            } else {
                dismiss()
        }
        
        case .url:
            // Import from URL
        let urlTrimmed = urlString.trimmingCharacters(in: .whitespacesAndNewlines)
        if !urlTrimmed.isEmpty, AIAddressExtractor.isSupported, URL(string: urlTrimmed) != nil {
            isImporting = true
            importer.start(urlString: urlTrimmed, allowPCC: true)
        } else {
                dismiss()
            }
            
        case .ai:
            // AI generation is handled by generateWithAI()
            // This should not be called for AI method
            dismiss()
        }
    }

    @MainActor private func generateWithAI() async {
        guard !isGenerating else { return }
        isGenerating = true
        generationProgress = "Preparing..."
        verifiedCount = 0
        
        defer {
            isGenerating = false
            generationProgress = ""
            verifiedCount = 0
        }
        
        do {
            let trimmed = aiQuery.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { return }
            
            // Ensure a map exists so the review step can add places
            if createdMap == nil {
                let mapName = name.trimmingCharacters(in: .whitespacesAndNewlines)
                let map = MapCollection(name: mapName.isEmpty ? "Untitled Map" : mapName)
                modelContext.insert(map)
                createdMap = map
            }
            
            // Generate places using the selected provider
            let (places, usedPCC): ([TemplatePlace], Bool)
            switch selectedProvider {
            case .appleFM:
                (places, usedPCC) = try await LLMPlaceGenerator.generatePlaces(userPrompt: trimmed, maxCount: 20)
            case .gemini:
                (places, usedPCC) = try await GeminiPlaceGenerator.generatePlaces(
                    userPrompt: trimmed,
                    maxCount: 20,
                    progressHandler: { progress in
                        // Update UI with progress
                        generationProgress = progress.currentActivity
                        verifiedCount = progress.verifiedPlacesCount
                    }
                )
            }
            
            // Start importer from generated places (converted to ExtractedAddress inside)
            isImporting = true
            importer.startFromGenerated(places, usedPCC: usedPCC)
            
        } catch let error as GeminiPlaceGenerator.GeminiError {
            // Handle Gemini-specific errors with user-friendly messages
            print("AI generation failed: \(error.localizedDescription)")
            
            switch error {
            case .rateLimited(let retryAfter):
                if let delay = retryAfter {
                    errorMessage = "Rate limited. Please wait \(Int(delay)) seconds before trying again."
                } else {
                    errorMessage = "Too many requests. Please wait a moment and try again."
                }
            case .quotaExceeded(let retryAfter):
                if let delay = retryAfter {
                    errorMessage = "API quota exceeded. Please retry in \(Int(delay)) seconds, or check your API plan at ai.google.dev."
                } else {
                    errorMessage = "API quota exceeded. Please check your plan and billing at ai.google.dev, or try again later."
                }
            case .noAPIKey:
                errorMessage = "No API key configured. Please add your Gemini API key in settings."
            case .networkError:
                errorMessage = "Network error. Please check your internet connection and try again."
            default:
                errorMessage = error.localizedDescription
            }
            
            showErrorAlert = true
            
        } catch {
            // Generic error handling
            print("AI generation failed: \(error.localizedDescription)")
            print(error)
            errorMessage = "Generation failed: \(error.localizedDescription)"
            showErrorAlert = true
        }
    }
}


