import SwiftUI
import CoreLocation

struct SelectAddressesSheet: View {
    @ObservedObject var importer: URLImporter
    let usedPCC: Bool
    var onConfirm: (_ selected: [ExtractedAddress]) -> Void
    var onCancel: () -> Void
    var onPaste: (_ text: String) -> Void

    @State private var selectedIds = Set<UUID>()
    @State private var pastedText: String = ""

    var body: some View {
        NavigationStack {
            VStack(spacing: 12) {
                // Selection controls (outside List to avoid row gesture interference)
                HStack(spacing: 12) {
                    Button("Select All") { selectedIds = Set(importer.candidates.map { $0.id }) }
                        .buttonStyle(.bordered)
                    Button("Select None") { selectedIds.removeAll() }
                        .buttonStyle(.bordered)
                    Spacer()
                    let selectedCount = importer.candidates.filter { selectedIds.contains($0.id) }.count
                    Text("\(selectedCount) selected")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
                .padding(.horizontal)

                if importer.candidates.isEmpty {
                    VStack(spacing: 12) {
                        Text("No addresses found")
                            .foregroundStyle(.secondary)
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Paste page text to try again:")
                                .font(.footnote)
                            TextEditor(text: $pastedText)
                                .frame(minHeight: 160)
                                .border(Color.gray.opacity(0.2))
                            HStack { Spacer()
                                Button("Run on pasted text") {
                                    let text = pastedText.trimmingCharacters(in: .whitespacesAndNewlines)
                                    guard !text.isEmpty else { return }
                                    onPaste(text)
                                }
                            }
                        }
                    }
                    .padding()
                } else {
                    List {
                        Section("Addresses") {
                            ForEach(importer.candidates, id: \.id) { item in
                                HStack(alignment: .top, spacing: 12) {
                                    Toggle("", isOn: Binding(
                                        get: { selectedIds.contains(item.id) },
                                        set: { isOn in
                                            if isOn { selectedIds.insert(item.id) } else { selectedIds.remove(item.id) }
                                        }
                                    ))
                                    .labelsHidden()

                                    VStack(alignment: .leading, spacing: 2) {
                                        if let name = item.displayName, !name.isEmpty {
                                            Text(name)
                                                .font(.headline)
                                        }
                                        Text(item.normalizedText)
                                        if let lat = item.latitude, let lon = item.longitude {
                                            Text(String(format: "%.5f, %.5f", lat, lon))
                                                .font(.caption)
                                                .foregroundStyle(.secondary)
                                        } else {
                                            HStack(spacing: 8) {
                                                VStack(alignment: .leading, spacing: 4) {
                                                    Text("Couldn't resolve location")
                                                        .font(.caption)
                                                        .foregroundStyle(.secondary)
                                                    if item.geocodeStatus == .resolving {
                                                        HStack(spacing: 4) {
                                                            ProgressView()
                                                                .scaleEffect(0.7)
                                                            Text("Retrying...")
                                                                .font(.caption2)
                                                                .foregroundStyle(.secondary)
                                                        }
                                                    }
                                                }
                                                if item.geocodeStatus != .resolving {
                                                    Button {
                                                        importer.retry(candidateId: item.id)
                                                    } label: {
                                                        Label("Retry", systemImage: "arrow.clockwise")
                                                            .font(.caption)
                                                    }
                                                    .buttonStyle(.bordered)
                                                    .controlSize(.mini)
                                                }
                                            }
                                            if let logsForItem = importer.debugLogs[item.id], !logsForItem.isEmpty {
                                                DisclosureGroup("Details") {
                                                    ForEach(logsForItem, id: \.self) { line in
                                                        Text(line)
                                                            .font(.caption2)
                                                            .foregroundStyle(.secondary)
                                                    }
                                                }
                                            }
                                        }
                                    }
                                }
                            }
                        }
                    }
                }

                VStack(spacing: 8) {
                    // Info about AI extraction
                    VStack(alignment: .leading, spacing: 6) {
                        if importer.usedLLM {
                            Text("Addresses extracted using Apple Intelligence LLM")
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                        } else {
                            Text("Addresses extracted using on-device Natural Language AI")
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                        }
                        Text("Review results before adding to your map.")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                    .padding(.horizontal)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    
                    // Show rate limiting notice if there are failed addresses
                    let failedCount = importer.candidates.filter { $0.coordinate == nil }.count
                    if failedCount > 0 {
                        VStack(alignment: .leading, spacing: 6) {
                            Text("\(failedCount) address\(failedCount == 1 ? "" : "es") couldn't be resolved")
                                .font(.footnote)
                                .foregroundStyle(.orange)
                            Text("Some addresses may have failed due to rate limiting. Try selecting fewer addresses at a time, or wait a few minutes and try again.")
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                        }
                        .padding(.horizontal)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
                .padding(.bottom)
            }
            .navigationTitle("Review Addresses")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { onCancel() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Add Selected") {
                        let selected = importer.candidates.filter { selectedIds.contains($0.id) }
                        onConfirm(selected)
                    }
                    .disabled(importer.candidates.filter { selectedIds.contains($0.id) && $0.coordinate != nil }.isEmpty)
                }
            }
        }
        .frame(minWidth: 420, minHeight: 480)
        .onAppear {
            // Preselect only resolved by default
            selectedIds = Set(importer.candidates.filter { $0.coordinate != nil }.map { $0.id })
        }
        .onReceive(importer.$candidates) { _ in
            // When candidates update (coordinates resolved), auto-select newly resolved ones if nothing is selected
            if selectedIds.isEmpty { selectedIds = Set(importer.candidates.filter { $0.coordinate != nil }.map { $0.id }) }
        }
    }
}


