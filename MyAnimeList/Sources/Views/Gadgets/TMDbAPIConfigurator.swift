//
//  TMDbAPIConfigurator.swift
//  MyAnimeList
//
//  Created by Samuel He on 2025/5/3.
//

import AlertToast
import SwiftUI

struct TMDbAPIConfigurator: View {
    @Environment(TMDbAPIKeyStorage.self) private var keyStorage

    @State private var apiKeyInput: String = ""
    @State private var status: TMDbAPIKeyCheckStatus?

    private var checking: Bool { status == .checking }
    private var checkFailed: Bool { status == .invalid }
    private var checkSuccess: Bool { status == .valid }

    var body: some View {
        ScrollView {
            PopupSectionCard(keyEntryTitleResource, systemImage: "person.badge.key") {
                TMDbAPIKeyEntryCard(
                    apiKey: $apiKeyInput,
                    mode: .settings,
                    isChecking: checking,
                    autoFocus: true,
                    validate: validateKey
                )
            }
            .padding(.horizontal, 20)
            .padding(.top, 24)
            .padding(.bottom, 24)
        }
        .safeAreaInset(edge: .top) {
            Color.clear.frame(height: 14)
        }
        .scrollBounceBehavior(.basedOnSize)
        .tmdbAPIKeyCheckToasts(
            checking: checking,
            failed: checkFailedBinding,
            succeeded: checkSuccessBinding,
            displayMode: .banner(.pop)
        )
        .onAppear {
            apiKeyInput = keyStorage.key ?? ""
        }
        .sensoryFeedback(trigger: status) { _, new in
            switch new {
            case .invalid: .error
            case .valid: .success
            default: nil
            }
        }
    }

    private var checkFailedBinding: Binding<Bool> {
        .init(get: { checkFailed }, set: { _ in status = nil })
    }

    private var checkSuccessBinding: Binding<Bool> {
        .init(get: { checkSuccess }, set: { _ in status = nil })
    }

    private var keyEntryTitleResource: LocalizedStringResource {
        "Change your API key"
    }

    private func validateKey() {
        let trimmedKey = apiKeyInput.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedKey.isEmpty else { return }
        status = .checking
        Task { await checkKey(trimmedKey) }
    }

    @discardableResult
    private func checkKey(_ key: String) async -> Bool {
        let result = await TMDbAPIKeyValidator.check(key)
        guard result else {
            status = .invalid
            return false
        }

        status = .valid
        await saveKeyAfterFeedback(key)
        return true
    }

    private func saveKeyAfterFeedback(_ key: String) async {
        await withCheckedContinuation { continuation in
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                let result = keyStorage.saveKey(key)
                if result {
                    NotificationCenter.default.post(
                        name: .tmdbAPIConfigurationDidChange,
                        object: nil
                    )
                }
                continuation.resume()
            }
        }
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
                Button(action: validate) {
                    HStack(spacing: 8) {
                        Image(systemName: isChecking ? "hourglass" : "checkmark.seal.fill")
                        Text(validateButtonTitleResource)
                    }
                    .padding()
                    .frame(maxWidth: .infinity)
                    .glassEffect(
                        .regular.tint(isFieldEmpty ? Color.gray : Color.blue),
                        in: .proportionalRounded
                    )
                    .animation(.default, value: isFieldEmpty)
                    .foregroundColor(.white)
                    .cornerRadius(10)
                }
                .disabled(isFieldEmpty || isChecking)
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

struct TMDbAPIKeyValidator {
    static func check(_ key: String) async -> Bool {
        guard !key.isEmpty else { return false }
        guard
            let url = URL(string: "https://tmdb-api.konakona52.com/3/configuration?api_key=\(key)")
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

extension View {
    func tmdbAPIKeyCheckToasts(
        checking: Bool,
        failed: Binding<Bool>,
        succeeded: Binding<Bool>,
        displayMode: AlertToast.DisplayMode
    ) -> some View {
        self
            .toast(
                isPresenting: .constant(checking),
                offsetY: 20,
                alert: {
                    AlertToast(
                        displayMode: displayMode,
                        type: .regular,
                        titleResource: "Checking key..."
                    )
                }
            )
            .toast(
                isPresenting: failed,
                offsetY: 20,
                alert: {
                    AlertToast(
                        displayMode: displayMode,
                        type: .error(.red),
                        titleResource: "Key check failed!"
                    )
                }
            )
            .toast(
                isPresenting: succeeded,
                offsetY: 20,
                alert: {
                    AlertToast(
                        displayMode: displayMode,
                        type: .complete(.green),
                        titleResource: "Key saved."
                    )
                }
            )
    }
}

#Preview {
    @Previewable @State var keyStorage = TMDbAPIKeyStorage()
    TMDbAPIConfigurator()
        .environment(keyStorage)
}
