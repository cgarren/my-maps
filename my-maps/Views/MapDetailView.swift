import SwiftUI
import MapKit
import SwiftData
import CoreLocation
#if os(iOS)
import UIKit
#endif

struct MapDetailView: View {
    @Environment(\.modelContext) private var modelContext
    @Bindable var map: MapCollection

    @State private var selectedPlace: Place?
    @State private var cameraPosition = MapCameraPosition.region(
        .init(center: CLLocationCoordinate2D(latitude: 0, longitude: 0),
              span: .init(latitudeDelta: 0.05, longitudeDelta: 0.05))
    )
    @State private var isSelectingAtCenter = false
    @State private var showingNameSheet = false
    @State private var showingSearchSheet = false
    @State private var pickContext: PickContext?
    @State private var pendingCoordinate: CLLocationCoordinate2D?
    @State private var pendingName: String = ""
    @State private var latestCenter: CLLocationCoordinate2D?
    @State private var showingPlacesList = false
    
    // Bulk addition states
    @State private var showingTemplateSheet = false
    @State private var showingAISheet = false
    @State private var selectedTemplate: MapTemplate? = nil
    @StateObject private var bulkImporter = URLImporter()
    @State private var showBulkReview = false
    @State private var isBulkImporting = false
    @AppStorage("has_seen_places_hint") private var hasSeenPlacesHint: Bool = false
    
    // Removed mapRevision invalidation; we'll key each item by id+visited instead
    private let geocoder = CLGeocoder()
    private let locationProvider = LocationProvider()

    struct PickContext: Identifiable { let id = UUID(); let coordinate: CLLocationCoordinate2D }

    // (removed helper views; use a minimal Annotation content instead)

    var body: some View {
        MapReader { proxy in
            Map(position: $cameraPosition) {
                let keyed: [(key: String, place: Place)] = map.places.map { p in ("\(p.id.uuidString)-\(p.visited ? "v" : "u")", p) }
                ForEach(keyed, id: \.key) { item in
                    let place = item.place
                    let coord = CLLocationCoordinate2D(latitude: place.latitude, longitude: place.longitude)
                    let name = place.name
                    let visited = place.visited
                    let color: Color = visited ? .green : .red
                    let toggleTitle: String = visited ? "Mark as Unvisited" : "Mark as Visited"
                    let toggleIcon: String = visited ? "xmark.circle" : "checkmark.circle"

                    Annotation(name, coordinate: coord) {
                        Button { selectedPlace = place } label: {
                            Image(systemName: "mappin.circle.fill")
                                .font(.title)
                                .foregroundStyle(color)
                        }
                        .contextMenu {
                            Button(toggleTitle, systemImage: toggleIcon) {
                                place.visited.toggle()
                            }
                        }
                    }
                }
            }
            .mapStyle(.standard(pointsOfInterest: .excludingAll))
            #if os(iOS)
                .mapFeatureSelectionDisabled { _ in true }
            #endif
            #if os(macOS)
                .overlay {
                    RightClickOverlay(
                        onAdd: { point in
                            if let coord = proxy.convert(point, from: .local) {
                                addPlace(at: coord)
                            }
                        },
                        onZoom: { point in
                            if let coord = proxy.convert(point, from: .local) {
                                withAnimation(.easeInOut) {
                                    cameraPosition = .region(.init(center: coord, span: .init(latitudeDelta: 0.02, longitudeDelta: 0.02)))
                                }
                            }
                        }
                    )
                    .allowsHitTesting(true)
                }
            #endif
            .onMapCameraChange(frequency: .continuous) { context in
                latestCenter = context.region.center
            }
            .gesture(
                LongPressGesture(minimumDuration: 0.25)
                    .sequenced(before: DragGesture(minimumDistance: 0, coordinateSpace: .local))
                    .onEnded { value in
                        if case .second(true, let drag?) = value {
                            if let coord = proxy.convert(drag.location, from: .local) {
                                addPlace(at: coord)
                            }
                        }
                    }
            )
        }
        .navigationTitle(map.name)
        .toolbar { addToolbar }
        .sheet(item: $selectedPlace) { place in
            NavigationStack {
                PlaceDetailView(place: place)
                    .toolbar {
                        ToolbarItem(placement: .destructiveAction) {
                            Button(role: .destructive) {
                                if let idx = map.places.firstIndex(where: { $0.id == place.id }) {
                                    map.places.remove(at: idx)
                                }
                                modelContext.delete(place)
                                selectedPlace = nil
                            } label: {
                                Label("Delete", systemImage: "trash")
                            }
                        }
                        ToolbarItem(placement: .confirmationAction) {
                            Button("Done") { selectedPlace = nil }
                        }
                    }
            }
            .presentationDetents([.medium, .large])
#if os(iOS)
            .presentationBackground(.ultraThinMaterial)
#endif
        }
        .sheet(isPresented: $showingNameSheet) {
            NamePlaceSheet(name: $pendingName, onCreate: {
                if let coord = pendingCoordinate { persistPlace(name: pendingName, at: coord) }
                resetPending()
            }, onCancel: {
                resetPending()
            })
        }
        .sheet(isPresented: $showingSearchSheet) {
            SearchPlaceSheet { item in
                let coord = item.placemark.coordinate
                let preferred = item.name ?? "New Place"
                withAnimation(.easeInOut) {
                    cameraPosition = .region(
                        .init(
                            center: coord,
                            span: .init(latitudeDelta: 0.02, longitudeDelta: 0.02)
                        )
                    )
                }
                prepareNameAndConfirm(for: coord, preferredName: preferred)
            }
        }
        .sheet(isPresented: $showingPlacesList) {
            NavigationStack {
                PlacesListView(map: map)
            }
            #if os(iOS)
            .presentationDetents([.medium, .large])
            .presentationBackground(.ultraThinMaterial)
            #else
            .frame(minWidth: 400, idealWidth: 500, minHeight: 400, idealHeight: 600)
            #endif
        }
        .sheet(item: $pickContext) { ctx in
            PickNearbyPlacesSheet(
                coordinate: ctx.coordinate,
                onPick: { name, pickedCoord in
                    withAnimation(.easeInOut) {
                        cameraPosition = .region(.init(center: pickedCoord, span: .init(latitudeDelta: 0.02, longitudeDelta: 0.02)))
                    }
                    persistPlace(name: name, at: pickedCoord)
                    resetPending()
                },
                onManual: { suggested in
                    pendingCoordinate = ctx.coordinate
                    pendingName = suggested ?? pendingName
                    pickContext = nil
                    showingNameSheet = true
                },
                onCancel: {
                    resetPending()
                }
            )
        }
        .sheet(isPresented: $showingTemplateSheet) {
            BulkTemplateSheet(
                selectedTemplate: $selectedTemplate,
                onConfirm: {
                    guard let template = selectedTemplate else { return }
                    do {
                        let places = try TemplateLoader.loadPlaces(from: template)
                        isBulkImporting = true
                        bulkImporter.startFromTemplate(places)
                        showingTemplateSheet = false
                    } catch {
                        print("Failed to load template: \(error)")
                    }
                },
                onCancel: {
                    showingTemplateSheet = false
                    selectedTemplate = nil
                }
            )
        }
        .sheet(isPresented: $showingAISheet) {
            BulkAISheet(
                onGenerate: { places, usedPCC in
                    isBulkImporting = true
                    bulkImporter.startFromGenerated(places, usedPCC: usedPCC)
                    showingAISheet = false
                },
                onCancel: {
                    showingAISheet = false
                }
            )
        }
        .sheet(isPresented: $isBulkImporting) {
            ImportProgressView(importer: bulkImporter, onCancel: {
                bulkImporter.cancel()
                isBulkImporting = false
            }, onPaste: { text in
                bulkImporter.startFromText(text, allowPCC: true)
            })
        }
        .sheet(isPresented: $showBulkReview) {
            SelectAddressesSheet(importer: bulkImporter, usedPCC: bulkImporter.usedPCC, onConfirm: { selected in
                for item in selected {
                    guard let coord = item.coordinate else { continue }
                    let trimmedName = item.displayName?.trimmingCharacters(in: .whitespacesAndNewlines)
                    let preferredName = (trimmedName?.isEmpty == false) ? trimmedName : nil
                    let title = preferredName ?? item.normalizedText.components(separatedBy: "\n").first ?? "New Place"
                    let place = Place(name: title, latitude: coord.latitude, longitude: coord.longitude, map: map)
                    modelContext.insert(place)
                    map.places.append(place)
                }
                isBulkImporting = false
                showBulkReview = false
            }, onCancel: {
                isBulkImporting = false
                showBulkReview = false
            }, onPaste: { text in
                showBulkReview = false
                isBulkImporting = true
                bulkImporter.startFromText(text, allowPCC: true)
            })
        }
        .onReceive(bulkImporter.$stage) { stage in
            switch stage {
            case .reviewing:
                isBulkImporting = false
                showBulkReview = true
            default:
                break
            }
        }
        .onAppear {
            centerCamera()
        }
        .overlay(alignment: .center) {
            if isSelectingAtCenter {
                Image(systemName: "plus.viewfinder")
                    .font(.largeTitle)
                    .foregroundStyle(.tint)
                    .shadow(radius: 3)
            }
        }
        .overlay(alignment: .bottom) {
            if isSelectingAtCenter {
                GlassPanel {
                    HStack {
                        Button("Cancel") { isSelectingAtCenter = false }
                        Spacer()
                        Button("Drop Pin Here") {
                            if let center = latestCenter {
                                addPlace(at: center)
                            }
                        }
                        .buttonStyle(.borderedProminent)
                    }
                }
                .padding()
            } else {
                // Completion HUD (tap to open Places list)
                Button {
                    showingPlacesList = true
                    hasSeenPlacesHint = true
                    #if os(iOS)
                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                    #endif
                } label: {
                    GlassPanel {
                        HStack(spacing: 12) {
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Completion")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                Text("\(map.visitedCount) of \(map.totalCount) visited")
                                    .font(.subheadline)
                                if !hasSeenPlacesHint {
                                    Text("Tap to view")
                                        .font(.caption2)
                                        .foregroundStyle(.tertiary)
                                        .transition(.opacity)
                                }
                            }
                            // Keep compact: progress ring + disclosure affordance
                            let fraction = max(0, min(1, map.completionFraction))
                            ZStack {
                                Circle()
                                    .stroke(Color.secondary.opacity(0.25), lineWidth: 6)
                                Circle()
                                    .trim(from: 0, to: fraction)
                                    .stroke(.tint, style: StrokeStyle(lineWidth: 6, lineCap: .round, lineJoin: .round))
                                    .rotationEffect(.degrees(-90))
                                Text("\(map.completionPercent)%")
                                    .font(.caption2)
                                    .monospacedDigit()
                            }
                            .frame(width: 36, height: 36)
                            Image(systemName: "chevron.up")
                                .font(.footnote.weight(.semibold))
                                .foregroundStyle(.secondary)
                                .imageScale(.small)
                        }
                        .fixedSize()
                    }
                    .contentShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                }
                .buttonStyle(.plain)
                #if os(iOS)
                .hoverEffect(.highlight)
                #endif
                .accessibilityLabel("Show places list")
                .accessibilityHint("Opens the list of places in this map")
                .padding(.bottom, 8)
                .animation(.easeInOut(duration: 0.25), value: hasSeenPlacesHint)
            }
        }
    }

    private func addPlace(at coord: CLLocationCoordinate2D) {
        pickContext = PickContext(coordinate: coord)
    }

    private func centerCamera() {
        // 1) Fit all existing pins
        if !map.places.isEmpty {
            let region = regionThatFits(places: map.places)
            cameraPosition = .region(region)
            return
        }

        // 2) Try current location
        locationProvider.requestOneShot { location in
            if let loc = location {
                let coord = loc.coordinate
                withAnimation(.easeInOut) {
                    cameraPosition = .region(.init(center: coord, span: .init(latitudeDelta: 0.02, longitudeDelta: 0.02)))
                }
            } else {
                // 3) Fallback to Boston
                let boston = CLLocationCoordinate2D(latitude: 42.3601, longitude: -71.0589)
                cameraPosition = .region(.init(center: boston, span: .init(latitudeDelta: 0.1, longitudeDelta: 0.1)))
            }
        }
    }

    private func regionThatFits(places: [Place]) -> MKCoordinateRegion {
        var minLat = Double.greatestFiniteMagnitude
        var maxLat = -Double.greatestFiniteMagnitude
        var minLon = Double.greatestFiniteMagnitude
        var maxLon = -Double.greatestFiniteMagnitude

        for p in places {
            minLat = min(minLat, p.latitude)
            maxLat = max(maxLat, p.latitude)
            minLon = min(minLon, p.longitude)
            maxLon = max(maxLon, p.longitude)
        }

        let center = CLLocationCoordinate2D(latitude: (minLat + maxLat) / 2.0,
                                            longitude: (minLon + maxLon) / 2.0)
        // Add padding and clamp within reasonable bounds
        let latDelta = max((maxLat - minLat) * 1.4, 0.01) // min ~1km
        let lonDelta = max((maxLon - minLon) * 1.4, 0.01)
        let clampedLat = min(latDelta, 60)
        let clampedLon = min(lonDelta, 60)

        return MKCoordinateRegion(center: center,
                                   span: MKCoordinateSpan(latitudeDelta: clampedLat, longitudeDelta: clampedLon))
    }

    private func prepareNameAndConfirm(for coord: CLLocationCoordinate2D, preferredName: String? = nil) {
        pendingCoordinate = coord
        if let preferredName, !preferredName.isEmpty {
            pendingName = preferredName
            showingNameSheet = true
            return
        }
        pendingName = "New Place"
        showingNameSheet = true
        geocoder.reverseGeocodeLocation(CLLocation(latitude: coord.latitude, longitude: coord.longitude)) { placemarks, _ in
            if let p = placemarks?.first {
                let components = [p.name, p.locality, p.administrativeArea].compactMap { $0 }
                if let suggestion = components.first(where: { !$0.isEmpty }) {
                    pendingName = suggestion
                }
            }
        }
    }

    private func persistPlace(name: String, at coord: CLLocationCoordinate2D) {
        let place = Place(name: name, latitude: coord.latitude, longitude: coord.longitude, map: map)
        modelContext.insert(place)
        map.places.append(place)
    }

    private func resetPending() {
        showingNameSheet = false
        pickContext = nil
        pendingCoordinate = nil
        pendingName = ""
        isSelectingAtCenter = false
    }

    @ToolbarContentBuilder private var addToolbar: some ToolbarContent {
        ToolbarItem(placement: .primaryAction) {
            Menu {
                // Individual place additions
                Button {
                    isSelectingAtCenter = true
                } label: {
                    Label("Add Place at Center", systemImage: "plus.viewfinder")
                }
                
                Button {
                    locationProvider.requestOneShot { location in
                        guard let loc = location else { return }
                        prepareNameAndConfirm(for: loc.coordinate)
                    }
                } label: {
                    Label("Add Current Location", systemImage: "location.fill")
                }
                
                Button {
                    showingSearchSheet = true
                } label: {
                    Label("Search and Add Place", systemImage: "magnifyingglass")
                }
                
                Divider()
                
                // Bulk additions
                Button {
                    showingTemplateSheet = true
                } label: {
                    Label("Add Places from Template", systemImage: "doc.on.doc")
                }
                
                Button {
                    showingAISheet = true
                } label: {
                    Label("Generate Places with AI", systemImage: "sparkles")
                }
            } label: {
                Label("Add", systemImage: "plus")
            }
        }
    }
}

// MARK: - Bulk Addition Sheets

struct BulkTemplateSheet: View {
    @Binding var selectedTemplate: MapTemplate?
    var onConfirm: () -> Void
    var onCancel: () -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var availableTemplates: [MapTemplate] = []
    
    var body: some View {
        NavigationStack {
            Form {
                Section {
                    if availableTemplates.isEmpty {
                        Text("No templates available")
                            .foregroundStyle(.secondary)
                    } else {
                        Picker("Select Template", selection: $selectedTemplate) {
                            Text("Choose a template...").tag(nil as MapTemplate?)
                            ForEach(availableTemplates) { template in
                                Text(template.displayName).tag(template as MapTemplate?)
                            }
                        }
                        #if os(macOS)
                        .pickerStyle(.menu)
                        #endif
                    }
                } header: {
                    Text("Choose a Template")
                        .font(.headline)
                } footer: {
                    Text("All places from the selected template will be added to your map. You'll be able to review them before confirming.")
                        .font(.caption)
                }
            }
            .navigationTitle("Add from Template")
            #if os(macOS)
            .formStyle(.grouped)
            .padding(20)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        onCancel()
                        dismiss()
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Add") {
                        onConfirm()
                        dismiss()
                    }
                    .disabled(selectedTemplate == nil)
                    #if os(macOS)
                    .buttonStyle(.borderedProminent)
                    #endif
                }
            }
        }
        #if os(macOS)
        .frame(minWidth: 500, idealWidth: 550, minHeight: 300, idealHeight: 400)
        #else
        .frame(minWidth: 360, minHeight: 200)
        #endif
        .onAppear {
            availableTemplates = TemplateLoader.availableTemplates()
        }
    }
}

struct BulkAISheet: View {
    @Environment(\.dismiss) private var dismiss
    @State private var aiQuery: String = ""
    @State private var isGenerating: Bool = false
    @State private var showSettings: Bool = false
    @State private var generationProgress: String = ""
    @State private var verifiedCount: Int = 0
    @State private var showErrorAlert: Bool = false
    @State private var errorMessage: String = ""
    @AppStorage("selected_ai_provider") private var selectedProviderRaw: String = AIProvider.appleFM.rawValue
    @FocusState private var isQueryFocused: Bool
    
    var onGenerate: ([TemplatePlace], Bool) -> Void
    var onCancel: () -> Void
    
    private var selectedProvider: AIProvider {
        AIProvider(rawValue: selectedProviderRaw) ?? .appleFM
    }
    
    var body: some View {
        NavigationStack {
            Form {
                Section {
                    VStack(alignment: .leading, spacing: 12) {
                        TextField("e.g. Top coffee shops in Austin", text: $aiQuery)
                            #if os(iOS)
                            .textInputAutocapitalization(.sentences)
                            .disableAutocorrection(false)
                            #elseif os(macOS)
                            .textFieldStyle(.roundedBorder)
                            #endif
                            .focused($isQueryFocused)
                            .disabled(!selectedProvider.isAvailable || isGenerating)
                            .onSubmit {
                                if canGenerate {
                                    Task { await generate() }
                                }
                            }
                        
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
                    Text("What places do you want?")
                        .font(.headline)
                } footer: {
                    VStack(alignment: .leading, spacing: 4) {
                        if !selectedProvider.isAvailable {
                            if selectedProvider == .appleFM {
                                Text("AI generation requires iOS 26+ or macOS 26+ with Apple Intelligence.")
                            } else {
                                #if os(macOS)
                                Text("Requires API key configuration. Click the settings button to add your \(selectedProvider.displayName) API key.")
                                #else
                                Text("Requires API key configuration. Tap the settings button to add your \(selectedProvider.displayName) API key.")
                                #endif
                            }
                        } else if isGenerating {
                            Text("Generating and verifying places... This may take 20-30 seconds.")
                        } else {
                            Text("Describe the places you want (e.g., \"coffee shops in Austin\" or \"national parks in California\"). AI will generate suggestions that you can review before adding.")
                        }
                    }
                    .font(.caption)
                }
            }
            .navigationTitle("Generate with AI")
            #if os(macOS)
            .formStyle(.grouped)
            .padding(20)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        onCancel()
                        dismiss()
                    }
                    .disabled(isGenerating)
                }
                
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
                
                ToolbarItem(placement: .confirmationAction) {
                    Button {
                        Task { await generate() }
                    } label: {
                        if isGenerating {
                            ProgressView()
                        } else {
                            Text("Generate")
                        }
                    }
                    .disabled(!canGenerate)
                    #if os(macOS)
                    .buttonStyle(.borderedProminent)
                    #endif
                }
            }
        }
        #if os(macOS)
        .frame(minWidth: 500, idealWidth: 550, minHeight: 350, idealHeight: 450)
        #else
        .frame(minWidth: 360, minHeight: 200)
        #endif
        .task { isQueryFocused = true }
        .sheet(isPresented: $showSettings) {
            SettingsView()
        }
        .alert("Generation Error", isPresented: $showErrorAlert) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(errorMessage)
        }
    }
    
    private var canGenerate: Bool {
        let hasQuery = !aiQuery.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        return selectedProvider.isAvailable && hasQuery && !isGenerating
    }
    
    @MainActor private func generate() async {
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
            
            // Call the completion handler with generated places
            onGenerate(places, usedPCC)
            dismiss()
            
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


