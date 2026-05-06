//
//  TMDbAPIConfigurator.swift
//  MyAnimeList
//
//  Created by Samuel He on 2025/5/3.
//

import SwiftUI

struct TMDbAPIConfigurator: View {
    @Environment(TMDbAPIKeyStorage.self) private var keyStorage

    @StateObject private var keyEntryController = TMDbAPIKeyEntryController()

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                configuratorHeader

                TMDbSetupPanel {
                    TMDbAPIKeyEntryCard(
                        apiKey: $keyEntryController.apiKeyInput,
                        mode: .settings,
                        autoFocus: true,
                        showsValidateButton: false,
                        validate: validateKey
                    )
                }
            }
            .padding(.horizontal, 20)
            .padding(.top, 24)
            .padding(.bottom, 24)
        }
        .safeAreaInset(edge: .top) {
            Color.clear.frame(height: 14)
        }
        .safeAreaInset(edge: .bottom) {
            TMDbProminentButton(
                title: confirmButtonTitleResource,
                systemImage: keyEntryController.checking ? "hourglass" : "checkmark.circle.fill",
                iconPlacement: .leading,
                isEnabled: !keyEntryController.isFieldEmpty && !keyEntryController.checking,
                validationStatus: keyEntryController.status,
                action: validateKey
            )
            .padding(.horizontal, 20)
            .padding(.top, 8)
            .padding(.bottom, 8)
        }
        .scrollBounceBehavior(.basedOnSize)
        .onAppear {
            keyEntryController.loadCurrentKey(from: keyStorage)
        }
        .sensoryFeedback(trigger: keyEntryController.status) { _, new in
            switch new {
            case .invalid: .error
            case .valid: .success
            default: nil
            }
        }
    }

    private var configuratorHeader: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label(sectionLabelResource, systemImage: "person.badge.key")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)

            Text(keyEntryTitleResource)
                .font(.title2.weight(.bold))

            Text(sectionMessageResource)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var sectionLabelResource: LocalizedStringResource {
        "TMDb API Key"
    }

    private var keyEntryTitleResource: LocalizedStringResource {
        "Change your API key"
    }

    private var sectionMessageResource: LocalizedStringResource {
        "Replace the TMDb key AniShelf uses for search and metadata."
    }

    private var confirmButtonTitleResource: LocalizedStringResource {
        keyEntryController.checking ? "Checking..." : "Save API Key"
    }

    private func validateKey() {
        keyEntryController.validate(using: keyStorage)
    }
}

extension Notification.Name {
    static let tmdbAPIConfigurationDidChange = Notification.Name("tmdbAPIKeyDidChange")
}

enum TMDbAPIKeyCheckStatus {
    case checking
    case valid
    case invalid
}

@MainActor
final class TMDbAPIKeyEntryController: ObservableObject {
    @Published var apiKeyInput: String = "" {
        didSet {
            if status != .checking {
                withAnimation(.spring(response: 0.32, dampingFraction: 0.86)) {
                    status = nil
                }
            }
        }
    }
    @Published var status: TMDbAPIKeyCheckStatus?

    var checking: Bool { status == .checking }
    var isFieldEmpty: Bool {
        apiKeyInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    func loadCurrentKey(from keyStorage: TMDbAPIKeyStorage) {
        apiKeyInput = keyStorage.key ?? ""
    }

    func validate(using keyStorage: TMDbAPIKeyStorage) {
        let trimmedKey = apiKeyInput.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedKey.isEmpty else { return }

        withAnimation(.spring(response: 0.32, dampingFraction: 0.86)) {
            status = .checking
        }
        Task {
            await checkKey(trimmedKey, using: keyStorage)
        }
    }

    @discardableResult
    func checkKey(_ key: String, using keyStorage: TMDbAPIKeyStorage) async -> Bool {
        let result = await TMDbAPIKeyValidator.check(key)
        guard result else {
            withAnimation(.spring(response: 0.32, dampingFraction: 0.86)) {
                status = .invalid
            }
            return false
        }

        withAnimation(.spring(response: 0.32, dampingFraction: 0.86)) {
            status = .valid
        }
        await saveKeyAfterFeedback(key, using: keyStorage)
        return true
    }

    private func saveKeyAfterFeedback(_ key: String, using keyStorage: TMDbAPIKeyStorage) async {
        try? await Task.sleep(for: .milliseconds(500))

        let result = keyStorage.saveKey(key)
        if result {
            NotificationCenter.default.post(
                name: .tmdbAPIConfigurationDidChange,
                object: nil
            )
        }
    }
}

enum TMDbAPIKeyEntryMode {
    case onboarding
    case settings

    var message: LocalizedStringResource {
        switch self {
        case .onboarding:
            "Paste your TMDB API Key here. AniShelf will check it before saving."
        case .settings:
            "Paste your new API Key. AniShelf will check it before saving."
        }
    }

    var fieldHint: LocalizedStringResource {
        switch self {
        case .onboarding:
            "You can change this later from settings."
        case .settings:
            "Your existing key stays active until the new one is saved."
        }
    }
}

struct TMDbAPIKeyEntryCard: View {
    @Binding var apiKey: String

    let mode: TMDbAPIKeyEntryMode
    var isChecking: Bool = false
    var autoFocus: Bool = false
    var showsValidateButton: Bool = true
    let validate: () -> Void

    @FocusState private var isTextFieldFocused: Bool

    private var isFieldEmpty: Bool {
        apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(mode.message)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            Label(keyTypeWarningResource, systemImage: "key.horizontal")
                .font(.footnote.weight(.semibold))
                .foregroundStyle(.blue)
                .fixedSize(horizontal: false, vertical: true)

            TextField(tmdbAPIKeyTitleResource, text: $apiKey)
                .padding()
                .background(Color(.secondarySystemBackground))
                .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                .focused($isTextFieldFocused)
                .textContentType(.password)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled(true)
                .privacySensitive()
                .submitLabel(.go)
                .onSubmit(validate)

            Text(mode.fieldHint)
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            if showsValidateButton {
                TMDbProminentButton(
                    title: validateButtonTitleResource,
                    systemImage: isChecking ? "hourglass" : "checkmark.seal.fill",
                    iconPlacement: .leading,
                    isEnabled: !isFieldEmpty && !isChecking,
                    validationStatus: isChecking ? .checking : nil,
                    action: validate
                )
            }
        }
        .onAppear {
            guard autoFocus else { return }
            isTextFieldFocused = true
        }
    }

    private var keyTypeWarningResource: LocalizedStringResource {
        "Use API Key, not API Read Access Token."
    }

    private var tmdbAPIKeyTitleResource: LocalizedStringResource {
        "TMDb API Key"
    }

    private var validateButtonTitleResource: LocalizedStringResource {
        isChecking ? "Checking..." : "Validate Key"
    }
}

enum TMDbProminentButtonIconPlacement {
    case leading
    case trailing
}

struct TMDbProminentButton: View {
    let title: LocalizedStringResource
    var systemImage: String? = nil
    var iconPlacement: TMDbProminentButtonIconPlacement = .trailing
    var isEnabled: Bool = true
    var validationStatus: TMDbAPIKeyCheckStatus? = nil
    let action: () -> Void

    private var effectiveTitle: LocalizedStringResource {
        switch validationStatus {
        case .checking:
            "Checking..."
        case .valid:
            "Key saved."
        case .invalid:
            "Key check failed!"
        case nil:
            title
        }
    }

    private var effectiveSystemImage: String? {
        switch validationStatus {
        case .checking:
            nil
        case .valid:
            "checkmark.circle.fill"
        case .invalid:
            "xmark.circle.fill"
        case nil:
            systemImage
        }
    }

    private var effectiveIconPlacement: TMDbProminentButtonIconPlacement {
        validationStatus == .checking ? .leading : iconPlacement
    }

    private var effectiveIsEnabled: Bool {
        switch validationStatus {
        case .checking, .valid:
            false
        case .invalid:
            true
        case nil:
            isEnabled
        }
    }

    private var effectiveTint: Color {
        switch validationStatus {
        case .checking, nil:
            .blue
        case .valid:
            .green
        case .invalid:
            .red
        }
    }

    private var showsValidationState: Bool {
        validationStatus != nil
    }

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                if effectiveIconPlacement == .leading {
                    iconView
                }

                Text(effectiveTitle)

                if effectiveIconPlacement == .trailing {
                    iconView
                }
            }
            .font(.headline.weight(.semibold))
            .contentTransition(.symbolEffect(.replace))
            .frame(maxWidth: .infinity)
            .frame(height: 50)
            .background(
                showsValidationState || effectiveIsEnabled ? effectiveTint : Color(.tertiarySystemFill),
                in: RoundedRectangle(cornerRadius: 18, style: .continuous)
            )
            .foregroundStyle(showsValidationState || effectiveIsEnabled ? .white : .secondary)
            .animation(.spring(response: 0.32, dampingFraction: 0.86), value: validationStatus)
            .animation(.spring(response: 0.32, dampingFraction: 0.86), value: effectiveIsEnabled)
            .overlay {
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .stroke(
                        .white.opacity(showsValidationState || effectiveIsEnabled ? 0.16 : 0),
                        lineWidth: 1
                    )
            }
            .shadow(
                color: showsValidationState || effectiveIsEnabled ? effectiveTint.opacity(0.16) : .clear,
                radius: 16,
                y: 10
            )
        }
        .buttonStyle(.plain)
        .disabled(!effectiveIsEnabled)
    }

    @ViewBuilder
    private var iconView: some View {
        if validationStatus == .checking {
            ProgressView()
                .tint(.white)
        } else if let effectiveSystemImage {
            Image(systemName: effectiveSystemImage)
                .font(.footnote.weight(.bold))
                .contentTransition(.symbolEffect(.replace))
        }
    }
}

struct TMDbSetupPanel<Content: View>: View {
    @ViewBuilder let content: Content

    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            content
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(20)
        .popupGlassPanel(cornerRadius: 28)
    }
}

struct TMDbAPIKeyValidator {
    static func check(_ key: String) async -> Bool {
        guard !key.isEmpty else { return false }
        guard
            let url = URL(
                string:
                    "https://\(UserDefaults.standard.tmdbAPIHostForCurrentPreference)/3/configuration?api_key=\(key)"
            )
        else {
            return false
        }

        var request = URLRequest(url: url)
        request.httpMethod = "GET"

        do {
            let (_, response) = try await URLSession.shared.data(for: request)
            guard let httpResponse = response as? HTTPURLResponse else { return false }
            return httpResponse.statusCode == 200
        } catch {
            return false
        }
    }
}

extension UserDefaults {
    fileprivate var tmdbAPIHostForCurrentPreference: String {
        usesTMDbRelayServer ? "tmdb-api.konakona52.com" : "api.themoviedb.org"
    }
}

#Preview {
    @Previewable @State var keyStorage = TMDbAPIKeyStorage()
    TMDbAPIConfigurator()
        .environment(keyStorage)
}
