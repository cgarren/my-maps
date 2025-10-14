import SwiftUI
import SwiftData
import MapKit
import CoreLocation
import Contacts

struct PlaceDetailView: View {
    @Bindable var place: Place
    @State private var address: String = ""
    @State private var isFetchingAddress = false
    private let geocoder = CLGeocoder()

    var body: some View {
        Form {
            Section {
                HStack(spacing: 0) {
                    Button {
                        let coordinate = CLLocationCoordinate2D(latitude: place.latitude, longitude: place.longitude)
                        let mapItem = MKMapItem(placemark: MKPlacemark(coordinate: coordinate))
                        mapItem.name = place.name
                        mapItem.openInMaps(launchOptions: nil)
                    } label: {
                        Label("Open", systemImage: "map")
                            .lineLimit(1)
                            .labelStyle(.titleAndIcon)
                            .padding([.all],10)
                    }
                    .frame(maxWidth: .infinity)
                    .buttonStyle(.borderedProminent)
                    .controlSize(.regular)
                    .buttonBorderShape(.capsule)
                    .accessibilityLabel("Open in Apple Maps")

                    Button {
                        withAnimation(.easeInOut(duration: 0.2)) {
                            place.visited.toggle()
                        }
                    } label: {
                        Label(place.visited ? "Visited" :"Visit", systemImage: place.visited ? "checkmark.circle.fill" : "circle")
                            .lineLimit(1)
                            .labelStyle(.titleAndIcon)
                            .padding([.all],10)
                    }
                    .frame(maxWidth: .infinity)
                    .buttonStyle(.bordered)
                    .controlSize(.regular)
                    .buttonBorderShape(.capsule)
                    .tint(place.visited ? .green : .secondary)
                    .animation(.easeInOut(duration: 0.2), value: place.visited)
                    .accessibilityLabel(place.visited ? "Mark as not visited" : "Mark as visited")
                }
                .background(.clear)
            }
            LabeledContent("Address") {
                if isFetchingAddress {
                    ProgressView()
                } else {
                    Text(address.isEmpty ? "Unknown" : address)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            LabeledContent("Latitude") { Text(String(format: "%.5f", place.latitude)) }
            LabeledContent("Longitude") { Text(String(format: "%.5f", place.longitude)) }
        }
        .scrollContentBackground(.hidden)
        .listStyle(.plain)
        .listRowBackground(Color.clear)
        .listRowSeparator(.hidden)
        .formStyle(.grouped)
        .background(.clear)
        .environment(\.defaultMinListRowHeight, 32.0)
        .padding()
        .frame(minWidth: 300, minHeight: 200)
        .navigationTitle(place.name)
        .onAppear(perform: fetchAddress)
        .onChange(of: place.latitude) { _ in fetchAddress() }
        .onChange(of: place.longitude) { _ in fetchAddress() }
    }

    private func fetchAddress() {
        if geocoder.isGeocoding { geocoder.cancelGeocode() }
        isFetchingAddress = true
        address = ""
        let location = CLLocation(latitude: place.latitude, longitude: place.longitude)
        geocoder.reverseGeocodeLocation(location) { placemarks, _ in
            DispatchQueue.main.async {
                isFetchingAddress = false
                guard let p = placemarks?.first else { return }

                if let postal = p.postalAddress {
                    let formatter = CNPostalAddressFormatter()
                    formatter.style = .mailingAddress
                    address = formatter.string(from: postal)
                    return
                }

                let street = [p.subThoroughfare, p.thoroughfare]
                    .compactMap { $0 }
                    .filter { !$0.isEmpty }
                    .joined(separator: " ")

                let city = p.locality ?? ""
                let state = p.administrativeArea ?? ""
                let zip = p.postalCode ?? ""

                let cityStateZip: String = {
                    switch (city.isEmpty, state.isEmpty, zip.isEmpty) {
                    case (false, false, false):
                        return "\(city), \(state) \(zip)"
                    case (false, false, true):
                        return "\(city), \(state)"
                    case (false, true, false):
                        return "\(city) \(zip)"
                    case (true, false, false):
                        return "\(state) \(zip)"
                    case (false, true, true):
                        return city
                    case (true, false, true):
                        return state
                    case (true, true, false):
                        return zip
                    default:
                        return ""
                    }
                }()

                let country = p.country ?? ""
                let lines = [street, cityStateZip, country].filter { !$0.isEmpty }
                address = lines.joined(separator: "\n")
            }
        }
    }
}


