//
//  WhatsNewController.swift
//  MyAnimeList
//
//  Created by OpenAI Codex on behalf of Samuel He on 2026/5/9.
//

import Foundation

fileprivate func currentWhatsNewAppVersion(bundle: Bundle = .main) -> String? {
    bundle.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String
}

enum WhatsNewPresentationSource: Equatable {
    case automatic
    case settings
}

@Observable @MainActor
final class WhatsNewController {
    @ObservationIgnored private let defaults: UserDefaults

    let currentVersion: String?
    let currentEntry: WhatsNewEntry?
    var presentedEntry: WhatsNewEntry?
    private(set) var presentationSource: WhatsNewPresentationSource?
    /// Window scene showing `presentedEntry`; `nil` until a window claims an automatic presentation.
    private(set) var presentingSceneIdentifier: String?

    init(
        defaults: UserDefaults = .standard,
        currentVersion: String? = currentWhatsNewAppVersion(),
        entryProvider: (String) -> WhatsNewEntry? = WhatsNewRegistry.currentEntry(for:)
    ) {
        self.defaults = defaults
        self.currentVersion = Self.normalizedVersion(currentVersion)
        self.currentEntry =
            self.currentVersion.flatMap { version in
                entryProvider(version)
            }
        self.presentedEntry = nil
        self.presentationSource = nil
    }

    func presentIfNeeded(allowsAutoPresentation: Bool) {
        guard allowsAutoPresentation else { return }
        guard presentedEntry == nil else { return }
        guard let currentEntry else { return }
        guard lastSeenVersion != currentEntry.version else { return }
        presentationSource = .automatic
        presentedEntry = currentEntry
    }

    func presentCurrentEntry(inSceneIdentifier sceneIdentifier: String?) {
        guard let currentEntry else { return }
        presentationSource = .settings
        presentedEntry = currentEntry
        presentingSceneIdentifier = sceneIdentifier
    }

    /// Lets the first window with a known scene take an unclaimed presentation, so only one shows it.
    func claimPresentation(forSceneIdentifier sceneIdentifier: String?) {
        guard presentedEntry != nil, presentingSceneIdentifier == nil, let sceneIdentifier else {
            return
        }
        presentingSceneIdentifier = sceneIdentifier
    }

    func presentedEntry(forSceneIdentifier sceneIdentifier: String?) -> WhatsNewEntry? {
        guard let sceneIdentifier, sceneIdentifier == presentingSceneIdentifier else { return nil }
        return presentedEntry
    }

    func dismissPresentedEntry(markSeen: Bool = true) {
        let dismissedEntry = presentedEntry
        presentedEntry = nil
        presentationSource = nil
        presentingSceneIdentifier = nil

        if markSeen, let dismissedEntry {
            defaults.set(dismissedEntry.version, forKey: .lastSeenWhatsNewVersion)
        }
    }

    private var lastSeenVersion: String? {
        defaults.string(forKey: .lastSeenWhatsNewVersion)
    }

    private static func normalizedVersion(_ version: String?) -> String? {
        guard let version else { return nil }
        let trimmedVersion = version.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmedVersion.isEmpty ? nil : trimmedVersion
    }
}
