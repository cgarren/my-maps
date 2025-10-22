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
    
    // Filter to only show usable providers (available or needs configuration)
    private var usableProviders: [AIProvider] {
        AIProvider.allCases.filter { $0.availabilityState.isUsable }
    }
    
    var body: some View {
        NavigationStack {
            Form {
                // SECTION 1: Provider Availability (moved to top for visibility)
                Section {
                    ForEach(AIProvider.allCases) { provider in
                        HStack {
                            Text(provider.displayName)
                            Spacer()
                            
                            // Visual indicator based on availability state
                            switch provider.availabilityState {
                            case .available:
                                HStack(spacing: 4) {
                                    Image(systemName: "checkmark.circle.fill")
                                        .foregroundStyle(.green)
                                    Text("Available")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                                
                            case .needsConfiguration:
                                HStack(spacing: 4) {
                                    Image(systemName: "exclamationmark.triangle.fill")
                                        .foregroundStyle(.orange)
                                    Text("Configuration needed")
                                        .font(.caption)
                                        .foregroundStyle(.orange)
                                }
                                
                            case .unavailable:
                                HStack(spacing: 4) {
                                    Image(systemName: "xmark.circle.fill")
                                        .foregroundStyle(.red)
                                    Text("Unavailable")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                            }
                        }
                        #if os(macOS)
                        .padding(.vertical, 2)
                        #endif
                    }
                } header: {
                    Text("Provider Availability")
                        .font(.headline)
                } footer: {
                    // Show status message for each provider
                    VStack(alignment: .leading, spacing: 4) {
                        ForEach(AIProvider.allCases) { provider in
                            if provider.availabilityState != .available {
                                Text("• \(provider.displayName): \(provider.statusMessage)")
                                    .font(.caption)
                                    .foregroundStyle(provider.availabilityState == .needsConfiguration ? .orange : .secondary)
                            }
                        }
                    }
                }
                
                // SECTION 2: Provider Selection (only show usable providers)
                if !usableProviders.isEmpty {
                    Section {
                        Picker("AI Provider", selection: $selectedProviderRaw) {
                            ForEach(usableProviders) { provider in
                                HStack {
                                    Text(provider.displayName)
                                    if provider.availabilityState == .needsConfiguration {
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
                        Text("Active Provider")
                            .font(.headline)
                    } footer: {
                        Text(selectedProvider.description)
                            .font(.caption)
                    }
                }
                
                // SECTION 3: Configuration for Apple Intelligence
                if selectedProvider == .appleFM && selectedProvider.availabilityState == .needsConfiguration {
                    Section {
                        VStack(alignment: .leading, spacing: 12) {
                            HStack(spacing: 8) {
                                Image(systemName: "exclamationmark.triangle.fill")
                                    .foregroundStyle(.orange)
                                    .font(.title2)
                                
                                VStack(alignment: .leading, spacing: 4) {
                                    Text("Configuration Required")
                                        .font(.headline)
                                        .foregroundStyle(.orange)
                                    
                                    Text("Apple Intelligence must be enabled in System Settings to use this feature.")
                                        .font(.subheadline)
                                        .foregroundStyle(.secondary)
                                }
                            }
                            
                            #if os(iOS)
                            if let url = URL(string: "App-prefs:") {
                                Link(destination: url) {
                                    HStack {
                                        Text("Open System Settings")
                                        Spacer()
                                        Image(systemName: "arrow.up.forward.app.fill")
                                    }
                                }
                                .buttonStyle(.borderedProminent)
                            }
                            #else
                            Text("Open System Settings > Apple Intelligence & Siri")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .padding(.top, 4)
                            #endif
                        }
                        #if os(macOS)
                        .padding(.vertical, 8)
                        #endif
                    } header: {
                        Text("Apple Intelligence Setup")
                            .font(.headline)
                    }
                }
                
                // SECTION 4: Gemini API Key Configuration
                if selectedProvider == .gemini {
                    Section {
                        // Show warning badge if needs configuration
                        if selectedProvider.availabilityState == .needsConfiguration {
                            HStack(spacing: 8) {
                                Image(systemName: "exclamationmark.triangle.fill")
                                    .foregroundStyle(.orange)
                                
                                Text("API key required to use Google Gemini")
                                    .font(.subheadline)
                                    .foregroundStyle(.orange)
                            }
                            #if os(macOS)
                            .padding(.vertical, 4)
                            #endif
                        }
                        
                        if hasExistingKey && !isEditingAPIKey {
                            HStack {
                                Text("API Key")
                                Spacer()
                                Text("••••••••")
                                    .foregroundStyle(.secondary)
                            }
                            #if os(macOS)
                            .padding(.vertical, 4)
                            #endif
                            
                            Button("Update API Key") {
                                isEditingAPIKey = true
                                geminiAPIKey = ""
                            }
                            #if os(macOS)
                            .buttonStyle(.borderless)
                            #endif
                            
                            Button("Remove API Key", role: .destructive) {
                                removeAPIKey()
                            }
                            #if os(macOS)
                            .buttonStyle(.borderless)
                            #endif
                        } else {
                            VStack(alignment: .leading, spacing: 12) {
                                Text("Gemini API Key")
                                    .font(.headline)
                                SecureField("Enter your API key", text: $geminiAPIKey)
                                    #if os(iOS)
                                    .textInputAutocapitalization(.never)
                                    .disableAutocorrection(true)
                                    #endif
                                    #if os(macOS)
                                    .textFieldStyle(.roundedBorder)
                                    #endif
                                
                                HStack(spacing: 12) {
                                    Button(hasExistingKey ? "Update Key" : "Save Key") {
                                        saveAPIKey()
                                    }
                                    .disabled(geminiAPIKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                                    #if os(macOS)
                                    .buttonStyle(.borderedProminent)
                                    #endif
                                    
                                    if isEditingAPIKey {
                                        Button("Cancel") {
                                            isEditingAPIKey = false
                                            geminiAPIKey = ""
                                        }
                                        #if os(macOS)
                                        .buttonStyle(.bordered)
                                        #endif
                                    }
                                }
                            }
                            #if os(macOS)
                            .padding(.vertical, 8)
                            #endif
                        }
                    } header: {
                        Text("API Configuration")
                            .font(.headline)
                    } footer: {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Get your API key from Google AI Studio:")
                            Link("https://aistudio.google.com/apikey", destination: URL(string: "https://aistudio.google.com/apikey")!)
                                .font(.caption)
                            Text("Your API key is stored securely in the Keychain.")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }
            .navigationTitle("AI Settings")
            #if os(macOS)
            .formStyle(.grouped)
            .padding(20)
            #endif
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
        #if os(macOS)
        .frame(minWidth: 500, idealWidth: 550, minHeight: 500, idealHeight: 600)
        #else
        .frame(minWidth: 320, minHeight: 400)
        #endif
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

