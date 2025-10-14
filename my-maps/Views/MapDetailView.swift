import SwiftUI
import MapKit
import SwiftData
import CoreLocation

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
            .presentationDetents([.medium, .large])
#if os(iOS)
            .presentationBackground(.ultraThinMaterial)
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
        .onAppear(perform: centerCamera)
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
                } label: {
                    GlassPanel {
                        HStack(spacing: 12) {
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Completion")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                Text("\(map.visitedCount) of \(map.totalCount) visited")
                                    .font(.subheadline)
                            }
                            // No spacer—keeps the panel compact
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
                        }
                        .fixedSize()
                    }
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Show places list")
                .padding(.bottom, 8)
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
                Button("Add at Map Center", systemImage: "plus.viewfinder") {
                    isSelectingAtCenter = true
                }
                Button("Add Current Location", systemImage: "location.fill") {
                    locationProvider.requestOneShot { location in
                        guard let loc = location else { return }
                        prepareNameAndConfirm(for: loc.coordinate)
                    }
                }
                Button("Search Places", systemImage: "magnifyingglass") {
                    showingSearchSheet = true
                }
            } label: {
                Label("Add", systemImage: "plus")
            }
        }
    }
}


