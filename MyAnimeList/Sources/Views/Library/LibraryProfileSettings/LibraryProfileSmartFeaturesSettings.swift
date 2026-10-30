//
//  LibraryProfileSmartFeaturesSettings.swift
//  AniShelf
//
//  Created by Claude Code on behalf of Samuel He on 2026/10/29.
//

import FoundationModels
import SwiftUI

/// The Smart Features page: which backend runs, and each provider's model and key.
struct LibraryProfileSmartFeaturesSettings: View {
    @State private var model = AISettingsModel()
    @State private var keyPrompt: AIBackend?
    @State private var keyDraft = ""
    @State private var customModelPrompt: AIBackend?
    @State private var customModelDraft = ""
    @State private var showsKeySaveFailure = false
    @State private var showsKeyRemovalFailure = false
    @State private var keyRemoval: AIBackend?

    private var tint: Color { LibraryProfileSettingsDestination.smartFeatures.tint }

    var body: some View {
        // One stack animates every card, so a card that grows or shrinks moves the ones below.
        LibraryProfileSettingsRows(alignment: .center, spacing: 16) {
            backendSection
            ForEach(model.listedBackends.filter(\.isProvider), id: \.self) { backend in
                providerSection(backend)
            }
        }
        .animation(Self.stateAnimation, value: model.activeBackend)
        .animation(Self.stateAnimation, value: model.models)
        .animation(Self.stateAnimation, value: model.keySuffixes)
        .animation(Self.stateAnimation, value: model.testStates)
    }

    private static let stateAnimation = Animation.spring(response: 0.34, dampingFraction: 0.88)

    // MARK: - Backend

    private var backendSection: some View {
        LibraryProfileSettingsGroup(
            "Backend", subtitle: formFooter(backendFooter), systemImage: "sparkles", tint: tint
        ) {
            ForEach(model.listedBackends, id: \.self) { backend in
                if backend != model.listedBackends.first {
                    LibraryProfileActionDivider(leadingInset: 0)
                }
                backendRow(backend)
            }
            cardFootnote(backendFooter)
        }
        .onAppear { model.refresh() }
        .onReceive(NotificationCenter.default.publisher(for: .aiConfigurationDidChange)) {
            model.configurationDidChange($0)
        }
        .alert("API Key", isPresented: isPresenting($keyPrompt), presenting: keyPrompt) { backend in
            SecureField("Paste the key", text: $keyDraft)
            Button("Cancel", role: .cancel) {}
            Button("Save") {
                if !model.saveKey(keyDraft, for: backend) { showsKeySaveFailure = true }
                keyDraft = ""
            }
        } message: { backend in
            Text("AniShelf keeps your \(backend.displayName) key in the Keychain on this device. It does not sync.")
        }
        .alert("Could Not Save the Key", isPresented: $showsKeySaveFailure) {
            Button("OK", role: .cancel) {}
        } message: {
            Text("The key is empty, or the Keychain refused it. The previous key, if any, stays.")
        }
        .alert("Could Not Remove the Key", isPresented: $showsKeyRemovalFailure) {
            Button("OK", role: .cancel) {}
        } message: {
            Text("The Keychain refused the change. The key stays. Try again.")
        }
        .alert("Custom Model", isPresented: isPresenting($customModelPrompt), presenting: customModelPrompt) {
            backend in
            TextField("Model ID", text: $customModelDraft)
            Button("Cancel", role: .cancel) {}
            Button("Use Model") { model.setModel(customModelDraft, for: backend) }
        } message: { _ in
            Text(customModelRisk)
        }
    }

    /// A choice row like the Language page's Default Poster options.
    private func backendRow(_ backend: AIBackend) -> some View {
        let isActive = model.activeBackend == backend
        let reason = model.availability.reason(for: backend)
        return Button {
            model.select(backend)
        } label: {
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(verbatim: backend.displayName)
                        .settingsRowTitleFont()
                        .foregroundStyle(reason == nil ? .primary : .secondary)
                    Text(status(for: backend, reason: reason, isActive: isActive))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 12)
                Image(systemName: "checkmark")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(tint)
                    .opacity(isActive ? 1 : 0)
                    .accessibilityHidden(true)
            }
            .padding(.vertical, 4)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(reason != nil)
        .accessibilityAddTraits(isActive ? .isSelected : [])
    }

    private func status(
        for backend: AIBackend, reason: AIAvailability.UnavailableReason?, isActive: Bool
    ) -> LocalizedStringResource {
        switch reason {
        case nil: isActive ? "In use" : "Ready"
        case .missingKey: "Add an API key below"
        case .requiresOS27: Self.requiresNewerSystem
        case .apple(.deviceNotEligible): "Not available on this device"
        case .apple(.appleIntelligenceNotEnabled): "Turn on Apple Intelligence in system settings"
        case .apple(.modelNotReady): "The model is still downloading"
        case .apple: "Not available right now"
        }
    }

    private var backendFooter: LocalizedStringResource {
        if model.activeBackend != nil {
            "Smart Features use the checked backend. Describe a category from the Categories manager."
        } else if model.supportsProviders {
            "Smart Features need Apple Intelligence, or an OpenAI or OpenRouter key."
        } else {
            Self.needsAppleIntelligenceOrNewerSystem
        }
    }

    #if os(macOS)
        private static let requiresNewerSystem: LocalizedStringResource = "Needs macOS 27 or later"
        private static let needsAppleIntelligenceOrNewerSystem: LocalizedStringResource =
            "Smart Features need Apple Intelligence on this Mac. macOS 27 also accepts an OpenAI or OpenRouter key."
    #else
        private static let requiresNewerSystem: LocalizedStringResource = "Needs iOS 27 or later"
        private static let needsAppleIntelligenceOrNewerSystem: LocalizedStringResource =
            "Smart Features need Apple Intelligence on this device. iOS 27 also accepts an OpenAI or OpenRouter key."
    #endif

    // MARK: - Providers

    private func providerSection(_ backend: AIBackend) -> some View {
        let disclosure = disclosure(for: backend)
        return LibraryProfileSettingsGroup(
            "\(backend.displayName)", subtitle: formFooter(disclosure), systemImage: "cloud", tint: tint
        ) {
            labeledRow("Model") { modelMenu(backend) }
            if model.usesCustomModel(for: backend) {
                warning(customModelRisk)
            }
            keyRow(backend)
                .alert(
                    "Remove the \(backend.displayName) Key?",
                    isPresented: Binding(get: { keyRemoval == backend }, set: { if !$0 { keyRemoval = nil } })
                ) {
                    Button("Remove Key", role: .destructive) {
                        if !model.removeKey(for: backend) { showsKeyRemovalFailure = true }
                    }
                    Button("Keep Key", role: .cancel) {}
                } message: {
                    Text(
                        "AniShelf deletes the key from this device. To use \(backend.displayName) again, you need to add it again."
                    )
                }
            connectionRow(backend)
            cardFootnote(disclosure)
        }
    }

    private func modelMenu(_ backend: AIBackend) -> some View {
        let current = model.model(for: backend)
        let title = backend.suggestedModels.first { $0.id == current }?.name ?? current
        return Menu {
            Picker("Model", selection: modelSelection(for: backend)) {
                ForEach(backend.suggestedModels, id: \.id) { candidate in
                    Text(verbatim: candidate.name).tag(candidate.id)
                }
                if model.usesCustomModel(for: backend) {
                    Text(verbatim: current).tag(current)
                }
            }
            Divider()
            Button("Custom Model…") {
                customModelDraft = model.usesCustomModel(for: backend) ? current : ""
                customModelPrompt = backend
            }
        } label: {
            #if os(macOS)
                Text(verbatim: title)
                    .lineLimit(1)
                    .truncationMode(.middle)
            #else
                LibraryProfileSelectionCapsule(title: "\(title)", tint: tint)
            #endif
        }
        .fixedSize()
    }

    @ViewBuilder
    private func keyRow(_ backend: AIBackend) -> some View {
        #if os(macOS)
            labeledRow("API Key") {
                HStack(spacing: 10) {
                    if let suffix = model.keySuffixes[backend] {
                        Text(verbatim: "••••\(suffix)")
                            .monospaced()
                            .foregroundStyle(.secondary)
                        Button("Change") { presentKeyPrompt(for: backend) }
                        Button("Remove", role: .destructive) { keyRemoval = backend }
                    } else {
                        Button("Add Key") { presentKeyPrompt(for: backend) }
                    }
                }
            }
        #else
            if let suffix = model.keySuffixes[backend] {
                let maskedKey = "••••\(suffix)"
                labeledRow("API Key") {
                    Menu {
                        Button("Change Key…", systemImage: "key") { presentKeyPrompt(for: backend) }
                        Button("Remove Key…", systemImage: "trash", role: .destructive) {
                            keyRemoval = backend
                        }
                    } label: {
                        LibraryProfileSelectionCapsule(title: "\(maskedKey)", tint: tint)
                    }
                }
            } else {
                Button("Add API Key", systemImage: "key") { presentKeyPrompt(for: backend) }
                    .libraryProfileCommandButtonStyle(tint: tint)
            }
        #endif
    }

    @ViewBuilder
    private func connectionRow(_ backend: AIBackend) -> some View {
        let state = model.testStates[backend] ?? .idle
        #if os(macOS)
            labeledRow("Connection") {
                testButton(backend, state: state)
                    .disabled(model.keySuffixes[backend] == nil)
            }
        #else
            // Without a key there is nothing to test; the Add API Key button takes its place.
            if model.keySuffixes[backend] != nil {
                testButton(backend, state: state)
            }
        #endif
        if case .failed(let error) = state {
            warning(error.message)
        }
    }

    /// Notes the test's progress and result in its own label, like the TMDb key check.
    ///
    /// It stays enabled: a second tap while testing is ignored, and after a result it tests again.
    private func testButton(_ backend: AIBackend, state: AISettingsModel.TestState) -> some View {
        let presentation = TestPresentation(state: state, tint: tint)
        return Button {
            Task { await model.testConnection(backend) }
        } label: {
            HStack(spacing: 6) {
                if let systemImage = presentation.systemImage {
                    Image(systemName: systemImage)
                        .contentTransition(.symbolEffect(.replace))
                } else {
                    ProgressView()
                        .controlSize(.small)
                }
                Text(presentation.title)
            }
        }
        .libraryProfileCommandButtonStyle(tint: presentation.tint)
        .sensoryFeedback(trigger: state) { _, new in
            switch new {
            case .succeeded: .success
            case .failed: .error
            default: nil
            }
        }
    }

    private struct TestPresentation {
        let title: LocalizedStringResource
        /// `nil` while testing, which shows a spinner.
        let systemImage: String?
        let tint: Color

        init(state: AISettingsModel.TestState, tint: Color) {
            switch state {
            case .idle: (title, systemImage, self.tint) = ("Test Connection", "network", tint)
            case .testing: (title, systemImage, self.tint) = ("Testing…", nil, tint)
            case .succeeded: (title, systemImage, self.tint) = ("Connection Works", "checkmark.circle.fill", .green)
            case .failed:
                (title, systemImage, self.tint) = (
                    "Connection Failed", "xmark.circle.fill", LibraryProfileSettingsPalette.destructive
                )
            }
        }
    }

    private func disclosure(for backend: AIBackend) -> LocalizedStringResource {
        "\(backend.displayName) receives the titles, studios, genres, and overviews of the anime it checks, with your description. Requests go from this device to \(backend.displayName) with your key."
    }

    private var customModelRisk: LocalizedStringResource {
        "AniShelf did not check this model. It must support structured output, or every request fails. Some models are slower, cost more, or answer less accurately. Use Test Connection to check it."
    }

    private func presentKeyPrompt(for backend: AIBackend) {
        keyDraft = ""
        keyPrompt = backend
    }

    private func labeledRow<Value: View>(
        _ title: LocalizedStringResource, @ViewBuilder value: () -> Value
    ) -> some View {
        #if os(macOS)
            LabeledContent {
                value()
            } label: {
                Text(title)
            }
        #else
            HStack(alignment: .firstTextBaseline, spacing: 12) {
                Text(title)
                    .settingsRowTitleFont()
                Spacer(minLength: 12)
                value()
            }
            .padding(.vertical, 2)
        #endif
    }

    private func warning(_ message: LocalizedStringResource) -> some View {
        Label(message, systemImage: "exclamationmark.triangle.fill")
            .font(.caption)
            .foregroundStyle(.orange)
    }

    /// A card's explanation is the Mac section footer.
    ///
    /// On iOS a header subtitle sits beside the icon, so a paragraph there would strand it;
    /// ``cardFootnote(_:)`` puts it below the rows.
    private func formFooter(_ text: LocalizedStringResource) -> LocalizedStringResource? {
        #if os(macOS)
            text
        #else
            nil
        #endif
    }

    @ViewBuilder
    private func cardFootnote(_ text: LocalizedStringResource) -> some View {
        #if !os(macOS)
            Text(text)
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        #endif
    }

    private func modelSelection(for backend: AIBackend) -> Binding<String> {
        Binding(get: { model.model(for: backend) }, set: { model.setModel($0, for: backend) })
    }

    private func isPresenting(_ backend: Binding<AIBackend?>) -> Binding<Bool> {
        Binding(get: { backend.wrappedValue != nil }, set: { if !$0 { backend.wrappedValue = nil } })
    }
}
