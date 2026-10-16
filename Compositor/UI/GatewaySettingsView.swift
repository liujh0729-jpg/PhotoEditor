import SwiftUI

/// Settings window for configuring the AI gateway.
struct GatewaySettingsView: View {
    @ObservedObject private var store = GatewayConfigurationStore.shared
    @State private var selectedTab = 0
    @State private var editingChannel: ProviderChannel?
    @State private var showingAddChannel = false
    
    var body: some View {
        TabView(selection: $selectedTab) {
            ChannelsTab(
                editingChannel: $editingChannel,
                showingAddChannel: $showingAddChannel
            )
            .tabItem {
                Label("Channels", systemImage: "server.rack")
            }
            .tag(0)
            
            CapabilitiesTab()
                .tabItem {
                    Label("Capabilities", systemImage: "puzzlepiece.extension")
                }
                .tag(1)

            GeneralTab()
                .tabItem {
                    Label("General", systemImage: "gearshape")
                }
                .tag(2)
        }
        .frame(width: 600, height: 500)
        .sheet(item: $editingChannel) { channel in
            ChannelEditorView(channel: channel)
        }
        .sheet(isPresented: $showingAddChannel) {
            ChannelEditorView(channel: nil)
        }
    }
}

/// Tab for managing provider channels.
struct ChannelsTab: View {
    @ObservedObject private var store = GatewayConfigurationStore.shared
    @Binding var editingChannel: ProviderChannel?
    @Binding var showingAddChannel: Bool
    
    var body: some View {
        VStack(spacing: 0) {
            List {
                ForEach(store.configuration.channels.sorted { $0.priority > $1.priority }) { channel in
                    ChannelRow(
                        channel: channel,
                        isDefault: store.configuration.defaultChannelID == channel.id,
                        onEdit: { editingChannel = channel },
                        onDelete: channel.isBuiltIn ? nil : { store.deleteChannel(channel.id) },
                        onSetDefault: { store.setDefaultChannel(channel.id) }
                    )
                }
            }
            .listStyle(.inset)
            
            Divider()
            
            HStack {
                Button(action: { showingAddChannel = true }) {
                    Label("Add Channel", systemImage: "plus")
                }
                Spacer()
            }
            .padding()
        }
    }
}

/// A single channel row in the list.
struct ChannelRow: View {
    let channel: ProviderChannel
    let isDefault: Bool
    let onEdit: () -> Void
    let onDelete: (() -> Void)?
    let onSetDefault: () -> Void
    
    @State private var apiKeyDisplay: String = "••••"
    
    var body: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 8) {
                    Text(channel.name)
                        .font(.headline)
                    if channel.isBuiltIn {
                        Text("Built-in")
                            .font(.caption)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Color.blue.opacity(0.2))
                            .cornerRadius(4)
                    }
                    if isDefault {
                        Text("Default")
                            .font(.caption)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Color.green.opacity(0.2))
                            .cornerRadius(4)
                    }
                }
                Text(channel.baseURL.absoluteString)
                    .font(.caption)
                    .foregroundColor(.secondary)
                Text("API Key: \(apiKeyDisplay)")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            
            Spacer()
            
            VStack(spacing: 8) {
                Toggle("", isOn: Binding(
                    get: { channel.enabled },
                    set: { newValue in
                        var updated = channel
                        updated.enabled = newValue
                        GatewayConfigurationStore.shared.updateChannel(updated)
                    }
                ))
                .toggleStyle(.switch)
                .labelsHidden()
                
                Menu {
                    Button("Edit…", action: onEdit)
                    if !isDefault {
                        Button("Set as Default", action: onSetDefault)
                    }
                    if let onDelete = onDelete {
                        Divider()
                        Button("Delete", action: onDelete)
                    }
                } label: {
                    Image(systemName: "ellipsis.circle")
                }
                .menuStyle(.borderlessButton)
                .fixedSize()
            }
        }
        .padding(.vertical, 4)
        .onAppear {
            apiKeyDisplay = KeychainStore.shared.displayKey(for: channel.id)
        }
    }
}

/// Editor for adding or editing a channel.
struct ChannelEditorView: View {
    let channel: ProviderChannel?
    
    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var store = GatewayConfigurationStore.shared
    
    @State private var name: String = ""
    @State private var baseURL: String = ""
    @State private var apiKey: String = ""
    @State private var enabled: Bool = true
    @State private var priority: Int = 0
    @State private var weight: Int = 10
    @State private var timeout: Double = 60
    @State private var proxy: String = ""
    
    @State private var testing = false
    @State private var testResult: Bool?
    @State private var saveError: String?
    
    var isEditing: Bool { channel != nil }
    
    var body: some View {
        VStack(spacing: 0) {
            Form {
                Section("Channel Info") {
                    TextField("Name", text: $name)
                    TextField("Base URL", text: $baseURL)
                        .textFieldStyle(.roundedBorder)
                    SecureField("API Key", text: $apiKey)
                }
                
                Section("Settings") {
                    Toggle("Enabled", isOn: $enabled)
                    Stepper("Priority: \(priority)", value: $priority, in: 0...1000)
                    Stepper("Weight: \(weight)", value: $weight, in: 1...100)
                    HStack {
                        Text("Timeout")
                        Slider(value: $timeout, in: 10...300, step: 10)
                        Text("\(Int(timeout))s")
                            .frame(width: 40)
                    }
                    TextField("Proxy (optional)", text: $proxy)
                }
                
                Section {
                    HStack {
                        Button("Test Connection") {
                            testConnection()
                        }
                        .disabled(testing || name.isEmpty || baseURL.isEmpty || apiKey.isEmpty)
                        
                        if testing {
                            ProgressView()
                                .scaleEffect(0.5)
                        } else if let result = testResult {
                            Image(systemName: result ? "checkmark.circle.fill" : "xmark.circle.fill")
                                .foregroundColor(result ? .green : .red)
                        }
                    }
                }
            }
            .formStyle(.grouped)
            
            Divider()
            
            HStack {
                Button("Cancel") {
                    dismiss()
                }
                .keyboardShortcut(.cancelAction)
                
                Spacer()
                
                Button(isEditing ? "Save" : "Add") {
                    save()
                }
                .keyboardShortcut(.defaultAction)
                .disabled(name.isEmpty || baseURL.isEmpty || apiKey.isEmpty)
            }
            .padding()
        }
        .frame(width: 500, height: 450)
        .alert("Couldn't save the API key", isPresented: Binding(
            get: { saveError != nil },
            set: { if !$0 { saveError = nil } }
        )) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(saveError ?? "")
        }
        .onAppear {
            if let channel = channel {
                name = channel.name
                baseURL = channel.baseURL.absoluteString
                apiKey = (try? KeychainStore.shared.retrieve(for: channel.id)) ?? ""
                enabled = channel.enabled
                priority = channel.priority
                weight = channel.weight
                timeout = channel.timeout
                proxy = channel.proxy?.absoluteString ?? ""
            }
        }
    }
    
    private func testConnection() {
        testing = true
        testResult = nil
        
        Task {
            guard let url = URL(string: baseURL) else {
                testResult = false
                testing = false
                return
            }
            
            let testChannel = ProviderChannel(
                name: name,
                baseURL: url,
                enabled: enabled,
                priority: priority,
                weight: weight,
                timeout: timeout,
                proxy: proxy.isEmpty ? nil : URL(string: proxy)
            )
            
            do {
                let result = try await GatewayClient.shared.testConnection(
                    channel: testChannel,
                    apiKey: apiKey
                )
                testResult = result
            } catch {
                testResult = false
            }
            
            testing = false
        }
    }
    
    private func save() {
        guard let url = URL(string: baseURL) else { return }
        
        if let channel = channel {
            // Update existing
            var updated = channel
            updated.name = name
            updated.baseURL = url
            updated.enabled = enabled
            updated.priority = priority
            updated.weight = weight
            updated.timeout = timeout
            updated.proxy = proxy.isEmpty ? nil : URL(string: proxy)
            
            store.updateChannel(updated)
            
            // Update API key. A keychain write can fail (lock denied, item corrupted); report it instead of
            // dismissing as if the key were saved.
            if !apiKey.isEmpty {
                do {
                    try KeychainStore.shared.store(key: apiKey, for: channel.id)
                } catch {
                    saveError = error.localizedDescription
                    return
                }
            }
        } else {
            // Add new
            let newChannel = ProviderChannel(
                name: name,
                baseURL: url,
                enabled: enabled,
                priority: priority,
                weight: weight,
                timeout: timeout,
                proxy: proxy.isEmpty ? nil : URL(string: proxy)
            )
            
            store.addChannel(newChannel)
            
            // Store API key
            if !apiKey.isEmpty {
                do {
                    try KeychainStore.shared.store(key: apiKey, for: newChannel.id)
                } catch {
                    saveError = error.localizedDescription
                    return
                }
            }
        }
        
        dismiss()
    }
}

/// Tab for managing capability slots.
struct CapabilitiesTab: View {
    @ObservedObject private var store = GatewayConfigurationStore.shared
    
    var body: some View {
        List {
            ForEach(store.configuration.capabilitySlots) { slot in
                CapabilitySlotRow(slot: slot)
            }
        }
        .listStyle(.inset)
    }
}

/// A single capability slot row.
struct CapabilitySlotRow: View {
    let slot: CapabilitySlot
    @ObservedObject private var store = GatewayConfigurationStore.shared
    
    @State private var modelOverride: String = ""
    @State private var pathOverride: String = ""
    @State private var channelOverrideID: UUID?
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(slot.endpointType.displayName)
                    .font(.headline)
                Spacer()
                Text(slot.endpointType.defaultPath)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            
            HStack {
                Text("Model:")
                    .frame(width: 60, alignment: .leading)
                TextField("Default", text: $modelOverride)
                    .textFieldStyle(.roundedBorder)
            }
            
            HStack {
                Text("Path:")
                    .frame(width: 60, alignment: .leading)
                TextField(slot.endpointType.defaultPath, text: $pathOverride)
                    .textFieldStyle(.roundedBorder)
            }
            
            HStack {
                Text("Channel:")
                    .frame(width: 60, alignment: .leading)
                Picker("", selection: $channelOverrideID) {
                    Text("Default").tag(UUID?.none)
                    ForEach(store.configuration.channels) { channel in
                        Text(channel.name).tag(UUID?.some(channel.id))
                    }
                }
                .labelsHidden()
            }
        }
        .padding(.vertical, 4)
        .onAppear {
            modelOverride = slot.modelOverride ?? ""
            pathOverride = slot.pathOverride ?? ""
            channelOverrideID = slot.channelIDOverride
        }
        .onChange(of: modelOverride) { _, newValue in
            var updated = slot
            updated.modelOverride = newValue.isEmpty ? nil : newValue
            store.updateSlot(updated)
        }
        .onChange(of: pathOverride) { _, newValue in
            var updated = slot
            updated.pathOverride = newValue.isEmpty ? nil : newValue
            store.updateSlot(updated)
        }
        .onChange(of: channelOverrideID) { _, newValue in
            var updated = slot
            updated.channelIDOverride = newValue
            store.updateSlot(updated)
        }
    }
}

/// Tab for app-wide preferences that aren't gateway-specific. Right now the
/// only entry is the UI language, which the user can pin to one of eight
/// shipped locales instead of following the system setting.
struct GeneralTab: View {
    @ObservedObject private var languageStore = LanguageStore.shared
    @State private var pending: LanguageStore.AppLanguage?

    var body: some View {
        Form {
            Picker("Language", selection: $languageStore.selection) {
                ForEach(LanguageStore.AppLanguage.allCases) { language in
                    if language == .system {
                        // "Follow System" should read in the current UI
                        // language, so it goes through LocalizedStringKey.
                        Text("Follow System").tag(language)
                    } else {
                        // Native language names stay in their own script so
                        // a user can pick their language regardless of the
                        // currently displayed UI.
                        Text(verbatim: language.nativeName).tag(language)
                    }
                }
            }
            .pickerStyle(.menu)
            .onChange(of: languageStore.selection) { _, newValue in
                languageStore.apply(newValue)
                pending = newValue
            }

            if let pending {
                Text("Restart PhotoCompositor to apply the new language.")
                    .foregroundStyle(.secondary)
                HStack {
                    Button("Restart to Apply") {
                        LanguageStore.shared.relaunch()
                    }
                    Button("Later", role: .cancel) {
                        self.pending = nil
                    }
                }
                if pending.isRightToLeft {
                    Label("Arabic lays out right-to-left on the next launch.",
                          systemImage: "text.alignright")
                        .foregroundStyle(.secondary)
                }
            } else {
                Text("Follow System uses the language order set in System Settings › General › Language & Region.")
                    .foregroundStyle(.secondary)
                    .font(.callout)
            }
        }
        .padding(20)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
}
