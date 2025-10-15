import SwiftUI

struct SettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @AppStorage("selected_ai_provider") private var selectedProviderRaw: String = AIProvider.appleFM.rawValue
    @State private var geminiAPIKey: String = ""
    @State private var isEditingAPIKey: Bool = false
    @State private var showAPIKeyAlert: Bool = false
    @State private var apiKeyAlertMessage: String = ""
    @State private var hasExistingKey: Bool = false
    
    private var selectedProvider: AIProvider {
        AIProvider(rawValue: selectedProviderRaw) ?? .appleFM
    }
    
    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Picker("AI Provider", selection: $selectedProviderRaw) {
                        ForEach(AIProvider.allCases) { provider in
                            HStack {
                                Text(provider.displayName)
                                if !provider.isAvailable {
                                    Image(systemName: "exclamationmark.triangle.fill")
                                        .foregroundStyle(.orange)
                                        .font(.caption)
                                }
                            }
                            .tag(provider.rawValue)
                        }
                    }
                    #if os(macOS)
                    .pickerStyle(.menu)
                    #endif
                } header: {
                    Text("Place Generation")
                } footer: {
                    Text(selectedProvider.description)
                }
                
                // Gemini API Key Section
                if selectedProvider == .gemini {
                    Section {
                        if hasExistingKey && !isEditingAPIKey {
                            HStack {
                                Text("API Key")
                                Spacer()
                                Text("••••••••")
                                    .foregroundStyle(.secondary)
                            }
                            Button("Update API Key") {
                                isEditingAPIKey = true
                                geminiAPIKey = ""
                            }
                            Button("Remove API Key", role: .destructive) {
                                removeAPIKey()
                            }
                        } else {
                            VStack(alignment: .leading, spacing: 8) {
                                Text("Gemini API Key")
                                    .font(.headline)
                                SecureField("Enter your API key", text: $geminiAPIKey)
                                    #if os(iOS)
                                    .textInputAutocapitalization(.never)
                                    .disableAutocorrection(true)
                                    #endif
                                Button(hasExistingKey ? "Update Key" : "Save Key") {
                                    saveAPIKey()
                                }
                                .disabled(geminiAPIKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                                
                                if isEditingAPIKey {
                                    Button("Cancel") {
                                        isEditingAPIKey = false
                                        geminiAPIKey = ""
                                    }
                                }
                            }
                        }
                    } header: {
                        Text("API Configuration")
                    } footer: {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Get your API key from Google AI Studio:")
                            Link("https://aistudio.google.com/apikey", destination: URL(string: "https://aistudio.google.com/apikey")!)
                                .font(.caption)
                            Text("Your API key is stored securely in the iOS Keychain.")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                
                // Provider Status
                Section {
                    ForEach(AIProvider.allCases) { provider in
                        HStack {
                            Text(provider.displayName)
                            Spacer()
                            if provider.isAvailable {
                                Image(systemName: "checkmark.circle.fill")
                                    .foregroundStyle(.green)
                            } else {
                                Image(systemName: "xmark.circle.fill")
                                    .foregroundStyle(.red)
                            }
                        }
                    }
                } header: {
                    Text("Provider Availability")
                } footer: {
                    Text("Apple Intelligence requires iOS 18+ or macOS 15+. Gemini requires an API key.")
                }
            }
            .navigationTitle("AI Settings")
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
        .frame(minWidth: 420, minHeight: 480)
        .onAppear {
            checkExistingKey()
        }
        .alert("API Key", isPresented: $showAPIKeyAlert) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(apiKeyAlertMessage)
        }
    }
    
    private func checkExistingKey() {
        hasExistingKey = GeminiPlaceGenerator.isConfigured
    }
    
    private func saveAPIKey() {
        let trimmed = geminiAPIKey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        
        do {
            try GeminiPlaceGenerator.saveAPIKey(trimmed)
            apiKeyAlertMessage = "API key saved successfully!"
            showAPIKeyAlert = true
            geminiAPIKey = ""
            isEditingAPIKey = false
            hasExistingKey = true
        } catch {
            apiKeyAlertMessage = "Failed to save API key: \(error.localizedDescription)"
            showAPIKeyAlert = true
        }
    }
    
    private func removeAPIKey() {
        do {
            try GeminiPlaceGenerator.deleteAPIKey()
            apiKeyAlertMessage = "API key removed successfully!"
            showAPIKeyAlert = true
            hasExistingKey = false
            isEditingAPIKey = false
        } catch {
            apiKeyAlertMessage = "Failed to remove API key: \(error.localizedDescription)"
            showAPIKeyAlert = true
        }
    }
}

