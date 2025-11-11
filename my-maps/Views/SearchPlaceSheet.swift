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
            VStack(spacing: 0) {
                // Search field
                HStack {
                    Image(systemName: "magnifyingglass")
                        .foregroundStyle(.secondary)
                    TextField("Search places", text: $query)
                        #if os(iOS)
                        .textInputAutocapitalization(.words)
                        #elseif os(macOS)
                        .textFieldStyle(.roundedBorder)
                        #endif
                        .onChange(of: query) { _, _ in debounceSearch() }
                        .onSubmit { performSearch() }
                        .focused($isSearchFocused)
                }
                .padding()
                #if os(macOS)
                .background(Color(NSColor.controlBackgroundColor))
                #endif
                
                Divider()
                
                // Results list
                if isSearching {
                    VStack {
                        ProgressView()
                            .padding()
                        Text("Searching...")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if results.isEmpty && !query.isEmpty {
                    VStack(spacing: 12) {
                        Image(systemName: "magnifyingglass")
                            .font(.largeTitle)
                            .foregroundStyle(.secondary)
                        Text("No results found")
                            .font(.headline)
                        Text("Try a different search term")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if results.isEmpty {
                    VStack(spacing: 12) {
                        Image(systemName: "location.magnifyingglass")
                            .font(.largeTitle)
                            .foregroundStyle(.secondary)
                        Text("Search for a place")
                            .font(.headline)
                        Text("Enter a location, address, or place name")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    List(results, id: \.self) { item in
                        Button {
                            onPick(item)
                            dismiss()
                        } label: {
                            HStack(spacing: 12) {
                                Image(systemName: "mappin.circle.fill")
                                    .font(.title2)
                                    .foregroundStyle(.red)
                                
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(item.name ?? "Unknown")
                                        .font(.headline)
                                        .foregroundStyle(.primary)
                                    
                                    let pm = item.placemark
                                    let street = [pm.subThoroughfare, pm.thoroughfare].compactMap { $0 }.joined(separator: " ")
                                    let parts = [street.isEmpty ? nil : street, pm.locality, pm.administrativeArea]
                                    if let subtitle = parts.compactMap({ $0 }).joined(separator: ", ").nilIfEmpty() {
                                        Text(subtitle)
                                            .font(.subheadline)
                                            .foregroundStyle(.secondary)
                                    }
                                }
                                
                                Spacer()
                                
                                Image(systemName: "chevron.right")
                                    .font(.caption)
                                    .foregroundStyle(.tertiary)
                            }
                            #if os(macOS)
                            .padding(.vertical, 6)
                            #endif
                        }
                        .buttonStyle(.plain)
                    }
                    #if os(macOS)
                    .listStyle(.inset)
                    #endif
                }
            }
            .navigationTitle("Search")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
        #if os(macOS)
        .frame(minWidth: 500, idealWidth: 600, minHeight: 400, idealHeight: 500)
        #else
        .frame(minWidth: 320, minHeight: 150)
        #endif
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









