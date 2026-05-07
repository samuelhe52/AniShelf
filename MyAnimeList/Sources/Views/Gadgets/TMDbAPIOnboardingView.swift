//
//  TMDbAPIOnboardingView.swift
//  MyAnimeList
//
//  Created by OpenAI Codex on 2026/5/2.
//

import SwiftUI

struct TMDbAPIOnboardingView: View {
    @Environment(TMDbAPIKeyStorage.self) private var keyStorage

    @State private var keyEntryViewModel = TMDbAPIKeyEntryViewModel()
    @State private var selectedStep: Step = .welcome

    private let apiSettingsURL = URL(string: "https://www.themoviedb.org/settings/api")!
    private let loginURL = URL(string: "https://www.themoviedb.org/login")!
    private let signupURL = URL(string: "https://www.themoviedb.org/signup")!

    var body: some View {
        @Bindable var keyEntryViewModel = keyEntryViewModel

        ScrollView {
            VStack(spacing: 20) {
                TMDbOnboardingHeader(
                    progress: currentProgressResource,
                    title: selectedStep.title
                )

                currentStepView
                    .id(selectedStep)

                TMDbOnboardingNavigation(
                    canGoBack: selectedStep.previous != nil,
                    canContinue: canContinue,
                    primaryTitle: selectedStep.primaryButtonTitle,
                    validationStatus: selectedStep == .enterKey ? keyEntryViewModel.status : nil,
                    goBack: goToPreviousStep,
                    goForward: goToNextStep
                )
            }
            .padding(.horizontal, 20)
            .padding(.top, 24)
            .padding(.bottom, 32)
        }
        .scrollBounceBehavior(.basedOnSize)
        .safeAreaInset(edge: .top) {
            Color.clear.frame(height: 14)
        }
        .animation(.spring(response: 0.32, dampingFraction: 0.88), value: selectedStep)
        .sensoryFeedback(trigger: keyEntryViewModel.status) { _, new in
            switch new {
            case .invalid: .error
            case .valid: .success
            default: nil
            }
        }
    }

    @ViewBuilder
    private var currentStepView: some View {
        switch selectedStep {
        case .welcome:
            TMDbWelcomeCard()
        case .getKey:
            TMDbKeyGuideCard(
                signupURL: signupURL,
                loginURL: loginURL,
                apiSettingsURL: apiSettingsURL
            )
        case .enterKey:
            TMDbSetupPanel {
                TMDbAPIKeyEntryCard(
                    apiKey: $keyEntryViewModel.apiKeyInput,
                    mode: .onboarding,
                    isChecking: keyEntryViewModel.checking,
                    autoFocus: true,
                    showsValidateButton: false,
                    validate: validateKey
                )
            }
        }
    }

    private var currentProgressResource: LocalizedStringResource {
        "Step \(selectedStep.rawValue) of \(Step.allCases.count)"
    }

    private var canContinue: Bool {
        guard selectedStep == .enterKey else { return true }
        return !keyEntryViewModel.isFieldEmpty && !keyEntryViewModel.checking
    }

    private func goToNextStep() {
        if selectedStep == .enterKey {
            validateKey()
            return
        }
        guard let nextStep = selectedStep.next else { return }
        withAnimation(.spring(response: 0.3, dampingFraction: 0.86)) {
            selectedStep = nextStep
        }
    }

    private func goToPreviousStep() {
        guard let previousStep = selectedStep.previous else { return }
        withAnimation(.spring(response: 0.3, dampingFraction: 0.86)) {
            selectedStep = previousStep
        }
    }

    private func validateKey() {
        keyEntryViewModel.validate(using: keyStorage)
    }

    private enum Step: Int, CaseIterable, Identifiable {
        case welcome = 1
        case getKey = 2
        case enterKey = 3

        var id: Int { rawValue }

        var title: LocalizedStringResource {
            switch self {
            case .welcome:
                "Connect AniShelf to TMDB"
            case .getKey:
                "Get a TMDB key"
            case .enterKey:
                "Connect TMDB"
            }
        }

        var primaryButtonTitle: LocalizedStringResource {
            switch self {
            case .welcome, .getKey:
                "Next"
            case .enterKey:
                "Validate Key"
            }
        }

        var previous: Self? {
            Self(rawValue: rawValue - 1)
        }

        var next: Self? {
            Self(rawValue: rawValue + 1)
        }
    }
}

fileprivate struct TMDbOnboardingHeader: View {
    let progress: LocalizedStringResource
    let title: LocalizedStringResource

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(progress)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)

            Text(title)
                .font(.title2.weight(.bold))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

fileprivate struct TMDbWelcomeCard: View {
    var body: some View {
        TMDbSetupPanel {
            VStack(spacing: 16) {
                Image("app-icon")
                    .resizable()
                    .scaledToFit()
                    .frame(width: 100, height: 100)
                    .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
                    .shadow(color: .black.opacity(0.18), radius: 18, y: 10)

                VStack(spacing: 6) {
                    Text(titleResource)
                        .font(.title3.weight(.semibold))
                        .multilineTextAlignment(.center)

                    Text(messageResource)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                }

                HStack(spacing: 10) {
                    TMDbWelcomePill(title: searchTitleResource, systemImage: "magnifyingglass")
                    TMDbWelcomePill(title: metadataTitleResource, systemImage: "photo.on.rectangle")
                }
            }
            .frame(maxWidth: .infinity)
        }
    }

    private var titleResource: LocalizedStringResource {
        "TMDB powers AniShelf."
    }

    private var messageResource: LocalizedStringResource {
        "Add a free API key once to unlock search, posters, and more."
    }

    private var searchTitleResource: LocalizedStringResource {
        "Search"
    }

    private var metadataTitleResource: LocalizedStringResource {
        "Metadata"
    }
}

fileprivate struct TMDbWelcomePill: View {
    let title: LocalizedStringResource
    let systemImage: String

    var body: some View {
        Label(title, systemImage: systemImage)
            .font(.footnote.weight(.semibold))
            .foregroundStyle(.blue)
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(.blue.opacity(0.12), in: Capsule())
    }
}

fileprivate struct TMDbKeyGuideCard: View {
    let signupURL: URL
    let loginURL: URL
    let apiSettingsURL: URL

    var body: some View {
        TMDbSetupPanel {
            VStack(alignment: .leading, spacing: 18) {
                Text(messageResource)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                VStack(alignment: .leading, spacing: 12) {
                    TMDbGuideStep(
                        number: 1,
                        title: signInTitleResource,
                        message: signInMessageResource
                    )
                    TMDbGuideStep(
                        number: 2,
                        title: apiPageTitleResource,
                        message: apiPageMessageResource
                    )
                    TMDbGuideStep(
                        number: 3,
                        title: copyTitleResource,
                        message: copyMessageResource
                    )
                }

                VStack(spacing: 8) {
                    TMDbLinkRow(
                        title: joinTMDbTitleResource,
                        systemImage: "person.badge.plus",
                        destination: signupURL
                    )
                    TMDbLinkRow(
                        title: loginToTMDbTitleResource,
                        systemImage: "person.crop.circle.badge.checkmark",
                        destination: loginURL
                    )
                    TMDbLinkRow(
                        title: openTMDbAPIPageTitleResource,
                        systemImage: "person.badge.key",
                        destination: apiSettingsURL
                    )
                }
            }
        }
    }

    private var messageResource: LocalizedStringResource {
        "TMDB gives each account a personal API key. It's completely free for personal use."
    }

    private var signInTitleResource: LocalizedStringResource {
        "Sign in to TMDB"
    }

    private var signInMessageResource: LocalizedStringResource {
        "Create an account or log in first."
    }

    private var apiPageTitleResource: LocalizedStringResource {
        "Open API settings"
    }

    private var apiPageMessageResource: LocalizedStringResource {
        "Go to the API page after you are signed in."
    }

    private var copyTitleResource: LocalizedStringResource {
        "Copy API Key"
    }

    private var copyMessageResource: LocalizedStringResource {
        "Copy the API Key, not the Read Access Token."
    }

    private var joinTMDbTitleResource: LocalizedStringResource {
        "Join TMDB"
    }

    private var loginToTMDbTitleResource: LocalizedStringResource {
        "Login to TMDB"
    }

    private var openTMDbAPIPageTitleResource: LocalizedStringResource {
        "Open API Page"
    }
}

fileprivate struct TMDbGuideStep: View {
    let number: Int
    let title: LocalizedStringResource
    let message: LocalizedStringResource

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Text("\(number)")
                .font(.footnote.weight(.bold))
                .foregroundStyle(.white)
                .frame(width: 24, height: 24)
                .background(.blue, in: Circle())

            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.subheadline.weight(.semibold))

                Text(message)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

fileprivate struct TMDbLinkRow: View {
    let title: LocalizedStringResource
    let systemImage: String
    let destination: URL

    var body: some View {
        Link(destination: destination) {
            HStack(spacing: 12) {
                Image(systemName: systemImage)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.blue)
                    .frame(width: 34, height: 34)
                    .background(
                        .blue.opacity(0.12),
                        in: RoundedRectangle(cornerRadius: 12, style: .continuous)
                    )

                Text(title)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.primary)

                Spacer(minLength: 12)

                Image(systemName: "arrow.up.right")
                    .font(.footnote.weight(.bold))
                    .foregroundStyle(.tertiary)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .background(
                Color(.secondarySystemBackground).opacity(0.72),
                in: RoundedRectangle(cornerRadius: 16, style: .continuous)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

fileprivate struct TMDbOnboardingNavigation: View {
    let canGoBack: Bool
    let canContinue: Bool
    let primaryTitle: LocalizedStringResource
    var validationStatus: TMDbAPIKeyCheckStatus? = nil
    let goBack: () -> Void
    let goForward: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            if canGoBack {
                Button(action: goBack) {
                    Image(systemName: "chevron.left")
                        .font(.headline.weight(.semibold))
                        .frame(width: 50, height: 50)
                        .background(
                            Color(.secondarySystemBackground),
                            in: RoundedRectangle(cornerRadius: 18, style: .continuous)
                        )
                }
                .buttonStyle(.plain)
                .foregroundStyle(.blue)
            }

            TMDbProminentButton(
                title: primaryTitle,
                systemImage: "chevron.right",
                iconPlacement: .trailing,
                isEnabled: canContinue,
                validationStatus: validationStatus,
                action: goForward
            )
        }
        .padding(8)
    }
}

#Preview {
    @Previewable @State var keyStorage = TMDbAPIKeyStorage()
    TMDbAPIOnboardingView()
        .environment(keyStorage)
}
