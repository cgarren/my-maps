import SwiftUI

struct ImportProgressView: View {
    @ObservedObject var importer: URLImporter
    var onCancel: () -> Void
    var onPaste: (_ text: String) -> Void

    @State private var pastedText: String = ""

    var body: some View {
        NavigationStack {
            VStack(spacing: 16) {
                switch importer.stage {
                case .idle:
                    Text("Idle")
                case .fetching:
                    progressRow(title: "Fetching page…")
                case .extracting(let usePCC):
                    progressRow(title: usePCC ? "Extracting addresses (PCC)…" : "Extracting addresses…")
                case .geocoding(let done, let total):
                    VStack(spacing: 8) {
                        progressRow(title: "Geocoding addresses…")
                        ProgressView(value: total == 0 ? 0 : Double(done) / Double(total))
                        Text("\(done) of \(total)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                case .reviewing:
                    Text("Preparing review…")
                case .completed:
                    Text("Completed")
                case .failed(let message):
                    VStack(spacing: 8) {
                        Text("Import failed")
                            .font(.headline)
                        Text(message)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                }

                VStack(alignment: .leading, spacing: 6) {
                    if importer.usedLLM {
                        Text("Using Apple Intelligence LLM for extraction")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    } else {
                        Text("Using on-device Natural Language AI for extraction")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                // Paste fallback moved to the review step
            }
            .padding()
            .navigationTitle("Importing…")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { onCancel() }
                }
            }
        }
        .frame(minWidth: 380, minHeight: 320)
    }

    @ViewBuilder private func progressRow(title: String) -> some View {
        HStack(spacing: 12) {
            ProgressView()
            Text(title)
        }
    }
}


