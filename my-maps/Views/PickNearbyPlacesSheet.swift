import SwiftUI
import MapKit
import CoreLocation

struct PickNearbyPlacesSheet: View {
    let coordinate: CLLocationCoordinate2D
    var onPick: (_ name: String, _ coord: CLLocationCoordinate2D) -> Void
    var onManual: (_ suggestedName: String?) -> Void
    var onCancel: () -> Void

    @State private var addressSuggestion: String?
    @State private var results: [MKMapItem] = []
    @State private var isLoading = true

    var body: some View {
        NavigationStack {
            List {
                if let addressSuggestion {
                    Section("Address") {
                        Button(action: { onManual(addressSuggestion) }) {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(addressSuggestion)
                                    .font(.headline)
                                Text("Edit name…")
                                    .font(.subheadline)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                }

                Section("Nearby places") {
                    if isLoading {
                        HStack { Spacer(); ProgressView(); Spacer() }
                    } else if results.isEmpty {
                        Text("No nearby places found")
                            .foregroundStyle(.secondary)
                    } else {
                        ForEach(results, id: \.self) { item in
                            Button(action: { onPick(item.name ?? "New Place", item.placemark.coordinate) }) {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(item.name ?? "Unknown")
                                        .font(.headline)
                                    if let subtitle = item.placemark.title {
                                        Text(subtitle)
                                            .font(.subheadline)
                                            .foregroundStyle(.secondary)
                                    }
                                }
                            }
                        }
                    }
                }
            }
            .navigationTitle("Choose Place")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { onCancel() }
                }
            }
        }
        .frame(minWidth: 360, minHeight: 480)
        .task(loadNearby)
    }

    private func loadNearby() {
        isLoading = true
        // Reverse geocode for a friendly address suggestion
        let geocoder = CLGeocoder()
        geocoder.reverseGeocodeLocation(CLLocation(latitude: coordinate.latitude, longitude: coordinate.longitude)) { placemarks, _ in
            if let p = placemarks?.first {
                // Prefer a human-friendly name; fall back to street/locality/admin
                let street = [p.subThoroughfare, p.thoroughfare].compactMap { $0 }.joined(separator: " ")
                let options = [p.name, street.isEmpty ? nil : street, p.locality, p.administrativeArea]
                if let suggestion = options.compactMap({ $0 }).first(where: { !$0.isEmpty }) {
                    addressSuggestion = suggestion
                }
            }
        }

        // Nearby POIs using dedicated request (no text query required)
        let radius: CLLocationDistance = 800
        let poiReq = MKLocalPointsOfInterestRequest(center: coordinate, radius: radius)
        let search = MKLocalSearch(request: poiReq)
        search.start { response, _ in
            results = response?.mapItems ?? []
            isLoading = false
        }
    }
}


