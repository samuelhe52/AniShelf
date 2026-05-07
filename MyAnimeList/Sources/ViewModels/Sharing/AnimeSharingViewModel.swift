//
//  AnimeSharingViewModel.swift
//  MyAnimeList
//
//  Created by Samuel He on 2025/11/22.
//

import DataProvider
import Foundation
import Observation
import SwiftUI

/// Observable view model that prepares localized poster previews and
/// manages cached renders for the sharing sheet.
@MainActor @Observable
final class AnimeSharingViewModel {
    /// Target width (points) used for both preview and exported posters.
    static let previewCardWidth: CGFloat = 360

    private static let defaultAspectRatio: CGFloat = 2.0 / 3.0
    private static let minAspectRatio: CGFloat = 0.45
    private static let maxAspectRatio: CGFloat = 0.85
    private static let jpegQuality: CGFloat = 0.9

    private static let yearFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.dateFormat = "yyyy"
        return formatter
    }()

    private static let validLanguageCodes: Set<String> = Set(
        Language.allCases.map(\.rawValueWithRegion)
    )

    /// Root entry the sharing UI references, collapsing seasons into series.
    let entry: AnimeEntry

    var selectedLanguage: Language
    var selectedPosterURL: URL?
    private(set) var renderedImageURL: URL?
    private(set) var loadedImage: UIImage?
    /// Aspect ratio applied to previews and exports, sourced from renderer output.
    private(set) var posterAspectRatio: CGFloat = AnimeSharingViewModel.defaultAspectRatio

    private var translations: [Language: String]

    /// Languages with available title translations for the current entry.
    var availableLanguages: [Language] {
        Array(translations.keys).sorted { $0.rawValue < $1.rawValue }
    }

    /// Indicates whether the user can pick alternate title languages.
    var canSelectLanguage: Bool {
        !translations.isEmpty
    }

    /// Localized attributed title for the current selection.
    var currentTitle: AttributedString {
        attributedTitle(for: selectedLanguage)
    }

    /// Optional localized subtitle shown underneath the main title.
    var previewSubtitle: AttributedString? {
        attributedSubtitle(for: selectedLanguage)
    }

    /// Text shown below the subtitle, typically release year + type.
    var previewDetailLine: String? {
        detailLineText()
    }

    /// Clamped aspect ratio used by both preview and export pipelines.
    var previewAspectRatio: CGFloat {
        posterAspectRatio
    }

    /// Hashable token that captures the poster/language pair for rendering.
    var renderTrigger: SharingCardRenderTrigger {
        SharingCardRenderTrigger(posterURL: selectedPosterURL, language: selectedLanguage)
    }

    @ObservationIgnored private var preferredLanguage: Language
    @ObservationIgnored private let renderer: SharingCardRenderer

    /// Creates a view model scoped to the provided entry, optionally forcing a
    /// specific default language for the generated metadata.
    init(entry: AnimeEntry, defaultLanguage: Language = .english) {
        self.entry = entry.parentSeriesEntry ?? entry
        self.selectedPosterURL = self.entry.posterURL
        self.selectedLanguage = defaultLanguage
        self.preferredLanguage = defaultLanguage
        self.translations = AnimeSharingViewModel.buildTranslations(from: self.entry)
        self.renderer = SharingCardRenderer(
            baseWidth: AnimeSharingViewModel.previewCardWidth,
            jpegQuality: AnimeSharingViewModel.jpegQuality,
            defaultAspectRatio: AnimeSharingViewModel.defaultAspectRatio,
            minAspectRatio: AnimeSharingViewModel.minAspectRatio,
            maxAspectRatio: AnimeSharingViewModel.maxAspectRatio
        )
        applyPreferredLanguage(defaultLanguage, respectingCurrentSelection: false)
    }

    /// Adjusts the preferred language if available, optionally keeping the
    /// current selection when it remains valid.
    func applyPreferredLanguage(_ language: Language, respectingCurrentSelection: Bool) {
        preferredLanguage = language
        guard !availableLanguages.isEmpty else { return }

        if respectingCurrentSelection, availableLanguages.contains(selectedLanguage) {
            return
        }

        if availableLanguages.contains(language) {
            selectedLanguage = language
        } else if let fallback = availableLanguages.first {
            selectedLanguage = fallback
        }
    }

    /// Updates the candidate poster URL while falling back to the entry
    /// default when the provided URL is nil.
    func updateSelectedPosterURL(_ url: URL?) {
        let resolvedURL = url ?? entry.posterURL
        guard selectedPosterURL != resolvedURL else { return }
        selectedPosterURL = resolvedURL
    }

    /// Loads poster art (using cached data when possible) and renders a share
    /// card for the provided trigger.
    func processRenderRequest(for trigger: SharingCardRenderTrigger) async {
        guard !Task.isCancelled else { return }
        let metadata = posterMetadata(for: trigger.language)
        let fileName = fileName(for: trigger)

        guard
            let outcome = await renderer.renderPoster(
                for: trigger,
                metadata: metadata,
                fileName: fileName
            )
        else { return }
        guard !Task.isCancelled else { return }

        renderedImageURL = outcome.imageURL
        if let image = outcome.image {
            loadedImage = image
        }
        posterAspectRatio = outcome.aspectRatio
    }

    /// Removes cached render artifacts to free disk space.
    func cleanupRenderedFiles() {
        renderer.cleanup()
        renderedImageURL = nil
        loadedImage = nil
        posterAspectRatio = AnimeSharingViewModel.defaultAspectRatio
    }

    /// Builds a stable filename so repeat renders overwrite earlier versions
    /// for the same poster/language pair.
    private func fileName(for trigger: SharingCardRenderTrigger) -> String {
        "poster_\(entry.tmdbID)_\(trigger.language).jpg"
    }

    private func attributedTitle(for language: Language) -> AttributedString {
        var attributed = AttributedString(title(for: language))
        attributed.languageIdentifier = language.rawValueWithRegion
        return attributed
    }

    private func attributedSubtitle(for language: Language) -> AttributedString? {
        guard let subtitleText = subtitle(for: language) else { return nil }
        var attributed = AttributedString(subtitleText)
        attributed.languageIdentifier = Language.japanese.rawValueWithRegion
        return attributed
    }

    private func title(for language: Language) -> String {
        translations[language] ?? entry.name
    }

    private func subtitle(for language: Language) -> String? {
        guard language != .japanese else { return nil }
        return entry.name.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func posterMetadata(for language: Language) -> PosterMetadata {
        PosterMetadata(
            title: attributedTitle(for: language),
            subtitle: attributedSubtitle(for: language),
            detail: detailLineText()
        )
    }

    /// Builds the detail line (year + entry type) for the rendered poster.
    private func detailLineText() -> String? {
        var parts: [String] = []
        if let year = releaseYearText() {
            parts.append(year)
        }
        parts.append(entryTypeLabel())
        return parts.joined(separator: " • ")
    }

    /// Formats the entry's air date into a four-digit year, when available.
    private func releaseYearText() -> String? {
        guard let date = entry.onAirDate else { return nil }
        return AnimeSharingViewModel.yearFormatter.string(from: date)
    }

    /// Human-readable label for whether the entry is a movie, series, or season.
    private func entryTypeLabel() -> String {
        switch entry.type {
        case .movie:
            return "Movie"
        case .series:
            return "TV Series"
        case .season(let seasonNumber, _):
            return "Season \(seasonNumber)"
        }
    }

    /// Builds the localized title table filtered to the languages we support.
    private static func buildTranslations(from entry: AnimeEntry) -> [Language: String] {
        entry.nameTranslations.reduce(into: [Language: String]()) { result, pair in
            guard let language = Language.fromRawValueWithRegion(pair.key),
                validLanguageCodes.contains(pair.key)
            else { return }
            result[language] = pair.value.isEmpty ? entry.name : pair.value
        }
    }
}
