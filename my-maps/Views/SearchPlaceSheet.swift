import SwiftUI
import MapKit

struct SearchPlaceSheet: View {
    @Environment(\.dismiss) private var dismiss
    var onPick: (MKMapItem) -> Void

    @State private var query: String = ""
    @State private var results: [MKMapItem] = []
    @State private var isSearching = false
    @State private var debouncedTask: DispatchWorkItem?
    @FocusState private var isSearchFocused: Bool

    var body: some View {
        NavigationStack {
//            VStack() {
            Form {
                Section{
                    TextField("Search places", text: $query)
                    // iOS-only modifier; guard for macOS builds
#if os(iOS)
                        .textInputAutocapitalization(.words)
#endif
                    // .textFieldStyle(.roundedBorder)
                        .onChange(of: query) { _, _ in debounceSearch() }
                        .onSubmit { performSearch() }
                        .focused($isSearchFocused)
                    //                        .padding()
                    //                     Button("Search") { performSearch() }
                    //                         .disabled(query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    //                }
                    //                .padding()
                }.padding()
                
                Section() {
                    if isSearching {
                        ProgressView().padding()
                    } else {
                        List(results, id: \.self) { item in
                            Button {
                                onPick(item)
                                dismiss()
                            } label: {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(item.name ?? "Unknown")
                                        .font(.headline)
                                    let pm = item.placemark
                                    let street = [pm.subThoroughfare, pm.thoroughfare].compactMap { $0 }.joined(separator: " ")
                                    let parts = [street.isEmpty ? nil : street, pm.locality, pm.administrativeArea]
                                    if let subtitle = parts.compactMap({ $0 }).joined(separator: ", ").nilIfEmpty() {
                                        Text(subtitle).font(.subheadline).foregroundStyle(.secondary)
                                    }
                                }
                            }
                        }
                    }
                }
            }.navigationTitle("Search")
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } } }
//            .padding()
        }
        .frame(minWidth: 320, minHeight: 150)
        .task { isSearchFocused = true }
    }

    private func debounceSearch() {
        debouncedTask?.cancel()
        let work = DispatchWorkItem { performSearch() }
        debouncedTask = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2, execute: work)
    }

    private func performSearch() {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { results = []; return }
        isSearching = true
        let request = MKLocalSearch.Request()
        request.naturalLanguageQuery = trimmed
        let search = MKLocalSearch(request: request)
        search.start { response, _ in
            self.results = response?.mapItems ?? []
            self.isSearching = false
        }
    }
}

private extension String {
    func nilIfEmpty() -> String? { isEmpty ? nil : self }
}


