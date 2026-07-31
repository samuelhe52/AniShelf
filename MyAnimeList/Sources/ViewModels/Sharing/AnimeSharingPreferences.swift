//
//  AnimeSharingPreferences.swift
//  AniShelf
//
//  Created by OpenAI Codex on behalf of Samuel He on 2026/7/31.
//

import Foundation

struct AnimeSharingSettings: Equatable {
    let selectedLanguage: Language
    let didRestoreSelectedLanguage: Bool
    let usesRoundedCorners: Bool
    let roundedExportFormat: SharingCardRoundedExportFormat
    let exportSize: SharingCardExportSize

    static func defaultValue(language: Language) -> AnimeSharingSettings {
        AnimeSharingSettings(
            selectedLanguage: language,
            didRestoreSelectedLanguage: false,
            usesRoundedCorners: true,
            roundedExportFormat: .png,
            exportSize: .medium
        )
    }
}

struct AnimeSharingPreferences {
    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    var remembersSettings: Bool {
        defaults.bool(forKey: .rememberShareSheetSettings, defaultValue: false)
    }

    func load(defaultLanguage: Language) -> AnimeSharingSettings {
        let fallback = AnimeSharingSettings.defaultValue(language: defaultLanguage)
        guard remembersSettings else { return fallback }

        let rememberedLanguage =
            defaults.string(forKey: .shareSheetLanguage)
            .flatMap(Language.init(rawValue:))

        return AnimeSharingSettings(
            selectedLanguage: rememberedLanguage ?? fallback.selectedLanguage,
            didRestoreSelectedLanguage: rememberedLanguage != nil,
            usesRoundedCorners: defaults.bool(
                forKey: .shareSheetUsesRoundedCorners,
                defaultValue: fallback.usesRoundedCorners
            ),
            roundedExportFormat:
                defaults.string(forKey: .shareSheetRoundedExportFormat)
                .flatMap(SharingCardRoundedExportFormat.init(rawValue:))
                ?? fallback.roundedExportFormat,
            exportSize:
                defaults.string(forKey: .shareSheetExportSize)
                .flatMap(SharingCardExportSize.init(rawValue:))
                ?? fallback.exportSize
        )
    }

    func saveSelectedLanguage(_ language: Language) {
        guard remembersSettings else { return }
        defaults.set(language.rawValue, forKey: .shareSheetLanguage)
    }

    func saveUsesRoundedCorners(_ usesRoundedCorners: Bool) {
        guard remembersSettings else { return }
        defaults.set(usesRoundedCorners, forKey: .shareSheetUsesRoundedCorners)
    }

    func saveRoundedExportFormat(_ format: SharingCardRoundedExportFormat) {
        guard remembersSettings else { return }
        defaults.set(format.rawValue, forKey: .shareSheetRoundedExportFormat)
    }

    func saveExportSize(_ exportSize: SharingCardExportSize) {
        guard remembersSettings else { return }
        defaults.set(exportSize.rawValue, forKey: .shareSheetExportSize)
    }

    func resetRememberedSettings() {
        defaults.removeObject(forKey: .shareSheetLanguage)
        defaults.removeObject(forKey: .shareSheetUsesRoundedCorners)
        defaults.removeObject(forKey: .shareSheetRoundedExportFormat)
        defaults.removeObject(forKey: .shareSheetExportSize)
    }
}
