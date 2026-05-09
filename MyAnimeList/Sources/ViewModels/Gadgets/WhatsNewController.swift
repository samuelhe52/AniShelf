//
//  WhatsNewController.swift
//  MyAnimeList
//
//  Created by OpenAI Codex on 2026/5/9.
//

import Foundation

fileprivate func currentWhatsNewAppVersion(bundle: Bundle = .main) -> String? {
    bundle.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String
}

@Observable @MainActor
final class WhatsNewController {
    @ObservationIgnored private let defaults: UserDefaults

    let currentVersion: String?
    let currentEntry: WhatsNewEntry?
    var presentedEntry: WhatsNewEntry?

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
    }

    func presentIfNeeded(allowsAutoPresentation: Bool) {
        guard allowsAutoPresentation else { return }
        guard presentedEntry == nil else { return }
        guard let currentEntry else { return }
        guard lastSeenVersion != currentEntry.version else { return }
        presentedEntry = currentEntry
    }

    func presentCurrentEntry() {
        guard let currentEntry else { return }
        presentedEntry = currentEntry
    }

    func dismissPresentedEntry(markSeen: Bool = true) {
        guard let presentedEntry else {
            self.presentedEntry = nil
            return
        }

        if markSeen {
            defaults.set(presentedEntry.version, forKey: .lastSeenWhatsNewVersion)
        }

        self.presentedEntry = nil
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
