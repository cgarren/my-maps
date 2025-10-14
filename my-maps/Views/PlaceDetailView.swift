import SwiftUI
import SwiftData

struct PlaceDetailView: View {
    @Bindable var place: Place

    var body: some View {
        Form {
            TextField("Name", text: $place.name)
            LabeledContent("Latitude") { Text(String(format: "%.5f", place.latitude)) }
            LabeledContent("Longitude") { Text(String(format: "%.5f", place.longitude)) }
        }
        .padding()
        .frame(minWidth: 300, minHeight: 200)
        .navigationTitle("Place")
    }
}


