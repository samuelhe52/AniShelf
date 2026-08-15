//
//  EntryDetailBroadcastComponents.swift
//  AniShelf
//
//  Created by OpenAI Codex on behalf of Samuel He on 2026/8/14.
//

import Foundation
import Kingfisher
import SwiftUI

struct EntryDetailBroadcastMenuContent: View {
    let phase: EntryDetailBroadcastModel.Phase
    let onPresentValidation: () -> Void
    let onRetry: () -> Void

    var isVisible: Bool {
        switch phase {
        case .disabled, .ineligible, .idle:
            false
        default:
            true
        }
    }

    @ViewBuilder
    var body: some View {
        switch phase {
        case .disabled, .ineligible, .idle:
            EmptyView()
        case .checkingEligibility, .resolving:
            airtimeSection(header: String(localized: EntryDetailL10n.findingAirtime)) {
                notificationsButton
            }
        case .resolved(let availability):
            airtimeSection(
                header: EntryDetailBroadcastFormatting.menuHeader(for: availability)
            ) {
                notificationsButton
            }
        case .requiresUserAssistance:
            airtimeSection(header: String(localized: EntryDetailL10n.airtime)) {
                Button(action: onPresentValidation) {
                    Label(EntryDetailL10n.helpConfirmAirtime, systemImage: "person.crop.circle.badge.questionmark")
                }
            }
        case .titleSearching, .titleCandidate:
            airtimeSection(header: String(localized: EntryDetailL10n.airtime)) {
                Button(action: onPresentValidation) {
                    Label(EntryDetailL10n.reviewAirtimeMatch, systemImage: "checkmark.bubble")
                }
            }
        case .failed:
            airtimeSection(header: String(localized: EntryDetailL10n.couldNotLoadAirtime)) {
                Button(action: onRetry) {
                    Label(EntryDetailL10n.retryAirtime, systemImage: "arrow.clockwise")
                }
            }
        }
    }

    private var notificationsButton: some View {
        Button(action: {}) {
            Label(EntryDetailL10n.notifications, systemImage: "bell")
        }
        .disabled(true)
    }

    private func airtimeSection<Content: View>(
        header: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        Section {
            content()
        } header: {
            Text(header)
        }
    }
}

struct EntryDetailBroadcastValidationSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.locale) private var locale

    let model: EntryDetailBroadcastModel
    let searchTitle: String

    @State private var isConfirming = false

    var body: some View {
        NavigationStack {
            content
                .navigationTitle(EntryDetailL10n.confirmAirtimeMatch)
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button(EntryDetailL10n.close, action: dismiss.callAsFunction)
                    }
                }
        }
        .onChange(of: model.phase) { _, phase in
            if case .resolved = phase {
                dismiss()
            }
        }
    }

    @ViewBuilder
    private var content: some View {
        switch model.phase {
        case .titleCandidate(let candidate):
            candidateContent(candidate)
        case .titleSearching:
            progressContent
        case .failed:
            failureContent
        case .resolved:
            Color.clear
                .task { dismiss() }
        default:
            progressContent
                .task {
                    model.startTitleFallback(named: searchTitle)
                }
        }
    }

    private var progressContent: some View {
        VStack(spacing: 16) {
            ProgressView()
                .controlSize(.large)
            Text(isConfirming ? EntryDetailL10n.savingAirtimeMatch : EntryDetailL10n.searchingTVMaze)
                .font(.headline)
            Text(searchTitle)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(24)
    }

    private var failureContent: some View {
        ContentUnavailableView {
            Label(EntryDetailL10n.couldNotFindMatch, systemImage: "magnifyingglass")
        } description: {
            Text(searchTitle)
        } actions: {
            Button(EntryDetailL10n.tryAgain) {
                isConfirming = false
                model.retryTitleFallback(named: searchTitle)
            }
            .buttonStyle(.borderedProminent)
        }
    }

    private func candidateContent(_ candidate: TVMazeShow) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                candidateHeader(candidate)

                candidateMetadata(candidate)

                nextAiringContent(candidate)

                VStack(spacing: 15) {
                    Button {
                        isConfirming = true
                        model.confirmTitleFallbackCandidate()
                    } label: {
                        Text(EntryDetailL10n.thisIsTheAnime)
                            .bold()
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 5)
                    }
                    .buttonStyle(.borderedProminent)
                    .buttonBorderShape(.roundedRectangle(radius: 15))

                    Button(EntryDetailL10n.notAMatch, role: .cancel) {
                        model.rejectTitleFallbackCandidate()
                        dismiss()
                    }
                    .bold()
                    .frame(maxWidth: .infinity)
                }
                .padding(.top, 8)
            }
            .padding(20)
            .frame(maxWidth: 560)
            .frame(maxWidth: .infinity)
        }
    }

    private func candidateHeader(_ candidate: TVMazeShow) -> some View {
        HStack(alignment: .center, spacing: 14) {
            candidateArtwork(candidate)

            VStack(alignment: .leading, spacing: 8) {
                Text(EntryDetailL10n.candidate)
                    .font(.caption2.weight(.bold))
                    .foregroundStyle(Color.accentColor)
                    .textCase(.uppercase)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Color.accentColor.opacity(0.12), in: Capsule())
                Text(candidate.name)
                    .font(.title2.weight(.bold))
                    .fixedSize(horizontal: false, vertical: true)
                Text(EntryDetailL10n.candidateConfirmationHelp)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(12)
        .background(
            Color(uiColor: .secondarySystemGroupedBackground),
            in: RoundedRectangle(cornerRadius: 20, style: .continuous)
        )
        .overlay {
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .stroke(.primary.opacity(0.06), lineWidth: 1)
        }
    }

    private func candidateArtwork(_ candidate: TVMazeShow) -> some View {
        KFImageView(
            url: candidate.fullImageURL,
            targetWidth: 240,
            diskCacheExpiration: .transient
        )
        .scaledToFill()
        .frame(width: 96, height: 144)
        .clipped()
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(.white.opacity(0.1), lineWidth: 1)
        }
        .accessibilityHidden(true)
    }

    @ViewBuilder
    private func candidateMetadata(_ candidate: TVMazeShow) -> some View {
        let rows = candidateMetadataRows(candidate)

        VStack(spacing: 0) {
            ForEach(rows.indices, id: \.self) { index in
                metadataRow(title: rows[index].title, value: rows[index].value)
                if index < rows.count - 1 {
                    Divider()
                }
            }
        }
        .padding(.horizontal, 12)
        .background(
            Color(uiColor: .secondarySystemGroupedBackground),
            in: RoundedRectangle(cornerRadius: 18, style: .continuous)
        )
        .overlay {
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(.primary.opacity(0.05), lineWidth: 1)
        }
    }

    private func candidateMetadataRows(
        _ candidate: TVMazeShow
    ) -> [(title: LocalizedStringResource, value: String)] {
        var rows: [(LocalizedStringResource, String)] = [
            (EntryDetailL10n.aniShelfTitle, searchTitle)
        ]
        if let language = candidate.language {
            rows.append(
                (
                    EntryDetailL10n.language,
                    EntryDetailBroadcastFormatting.localizedLanguageName(
                        language,
                        locale: locale
                    )
                )
            )
        }
        if let premiered = candidate.premiered {
            rows.append((EntryDetailL10n.premiered, premiered))
        }
        if let schedule = EntryDetailBroadcastFormatting.scheduleSummary(candidate) {
            rows.append((EntryDetailL10n.broadcastSchedule, schedule))
        }
        return rows
    }

    @ViewBuilder
    private func nextAiringContent(_ candidate: TVMazeShow) -> some View {
        switch model.availability(for: candidate) {
        case .tvMazeNextAiring(_, let airing, let assessment):
            VStack(alignment: .leading, spacing: 6) {
                Label(EntryDetailL10n.nextAiring, systemImage: "clock")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                Text(EntryDetailBroadcastFormatting.nextAiringDateTime(airing.airStamp))
                    .font(.title3.weight(.medium))
                    .monospacedDigit()
                if let episode = EntryDetailBroadcastFormatting.episodeSummary(airing) {
                    Text(episode)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                if case .disagrees = assessment {
                    Label(
                        EntryDetailL10n.uncertainAirtime,
                        systemImage: "exclamationmark.triangle.fill"
                    )
                    .font(.subheadline)
                    .foregroundStyle(.orange)
                }
            }
            .nextAiringSectionStyle()
        case .tmdbExpected(let evidence):
            VStack(alignment: .leading, spacing: 6) {
                Label(EntryDetailL10n.expected, systemImage: "calendar.badge.clock")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                Text(EntryDetailBroadcastFormatting.expectedDate(evidence.airDate))
                    .font(.title3.weight(.medium))
                    .monospacedDigit()
                Text(EntryDetailL10n.missingTVMazeNextAiring)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                Text(EntryDetailL10n.usesTMDbExpectedDateAfterConfirmation)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            .nextAiringSectionStyle()
        case .unavailable:
            Label(EntryDetailL10n.nextAirtimeUnavailable, systemImage: "clock.badge.questionmark")
                .font(.headline)
                .nextAiringSectionStyle()
        }
    }

    private func metadataRow(
        title: LocalizedStringResource,
        value: String
    ) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 16) {
            Text(title)
                .foregroundStyle(.secondary)
            Spacer(minLength: 12)
            Text(value)
                .multilineTextAlignment(.trailing)
                .lineLimit(2)
        }
        .font(.subheadline)
        .padding(.vertical, 10)
    }
}

extension View {
    fileprivate func nextAiringSectionStyle() -> some View {
        self
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                Color(uiColor: .secondarySystemGroupedBackground),
                in: RoundedRectangle(cornerRadius: 18, style: .continuous)
            )
            .overlay {
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .stroke(.primary.opacity(0.05), lineWidth: 1)
            }
    }
}

fileprivate enum EntryDetailBroadcastFormatting {
    private static let languageCodeByEnglishName: [String: String] = {
        let englishLocale = Locale(identifier: "en")
        var result: [String: String] = [:]
        for code in Locale.LanguageCode.isoLanguageCodes {
            guard let name = englishLocale.localizedString(forLanguageCode: code.identifier) else {
                continue
            }
            result[name.lowercased()] = code.identifier
        }
        return result
    }()

    static func menuHeader(for availability: BroadcastAvailability) -> String {
        switch availability {
        case .tvMazeNextAiring(_, let airing, let assessment):
            var components: [String] = []
            if let episode = episodeSummary(airing) {
                components.append(episode)
            }
            components.append(compactDateTime(airing.airStamp))
            if case .disagrees = assessment {
                components.append("⚠︎ " + String(localized: EntryDetailL10n.uncertainAirtime))
            }
            return components.joined(separator: " · ")
        case .tmdbExpected(let evidence):
            return [
                String(localized: EntryDetailL10n.expected),
                compactCalendarDate(evidence.airDate)
            ]
            .joined(separator: " · ")
        case .unavailable:
            return String(localized: EntryDetailL10n.airtimeUnavailable)
        }
    }

    static func nextAiringDateTime(_ date: Date) -> String {
        date.formatted(date: .abbreviated, time: .shortened)
    }

    static func expectedDate(_ tmdbDate: TMDbCalendarDate) -> String {
        calendarDate(tmdbDate)
    }

    static func scheduleSummary(_ show: TVMazeShow) -> String? {
        let schedule = show.providerLocalSchedule
        let days = schedule.days.map(\.localizedName).filter { !$0.isEmpty }
        guard !days.isEmpty || schedule.displayTime != nil else { return nil }

        var components: [String] = []
        if !days.isEmpty {
            components.append(days.joined(separator: ", "))
        }
        if let displayTime = schedule.displayTime {
            components.append(displayTime)
        }
        if let timeZone = show.timeZone {
            let referenceDate = show.nextEpisodeAiring?.airStamp ?? .now
            let compactTimeZoneName =
                timeZone.abbreviation(for: referenceDate)
                ?? timeZone.localizedName(
                    for: .shortGeneric,
                    locale: .autoupdatingCurrent
                )
            if let compactTimeZoneName {
                components.append(compactTimeZoneName)
            }
        }
        return components.joined(separator: " · ")
    }

    static func localizedLanguageName(
        _ providerValue: String,
        locale: Locale = .autoupdatingCurrent
    ) -> String {
        let normalizedValue =
            providerValue
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
        guard let languageCode = languageCodeByEnglishName[normalizedValue] else {
            return providerValue
        }
        return locale.localizedString(forLanguageCode: languageCode) ?? providerValue
    }

    static func episodeSummary(_ airing: TVMazeNextEpisodeAiring) -> String? {
        switch (airing.seasonNumber, airing.episodeNumber) {
        case (.some(let season), .some(let episode)):
            String(format: "S%02dE%02d", season, episode)
        case (.some(let season), nil):
            String(format: "S%02d", season)
        case (nil, .some(let episode)):
            String(format: "E%02d", episode)
        case (nil, nil):
            nil
        }
    }

    private static func compactDateTime(_ date: Date) -> String {
        let currentYear = Calendar.autoupdatingCurrent.component(.year, from: .now)
        let airingYear = Calendar.autoupdatingCurrent.component(.year, from: date)
        return localizedDate(
            date,
            template: currentYear == airingYear ? "Mdjmm" : "yMdjmm"
        )
    }

    private static func compactCalendarDate(_ tmdbDate: TMDbCalendarDate) -> String {
        let components = DateComponents(
            year: tmdbDate.year,
            month: tmdbDate.month,
            day: tmdbDate.day
        )
        guard let date = Calendar.autoupdatingCurrent.date(from: components) else {
            return String(format: "%04d-%02d-%02d", tmdbDate.year, tmdbDate.month, tmdbDate.day)
        }

        let currentYear = Calendar.autoupdatingCurrent.component(.year, from: .now)
        return localizedDate(
            date,
            template: currentYear == tmdbDate.year ? "Md" : "yMd"
        )
    }

    private static func localizedDate(_ date: Date, template: String) -> String {
        let formatter = DateFormatter()
        formatter.locale = .autoupdatingCurrent
        formatter.calendar = .autoupdatingCurrent
        formatter.timeZone = .autoupdatingCurrent
        formatter.setLocalizedDateFormatFromTemplate(template)
        return formatter.string(from: date)
    }

    private static func calendarDate(_ tmdbDate: TMDbCalendarDate) -> String {
        let components = DateComponents(
            year: tmdbDate.year,
            month: tmdbDate.month,
            day: tmdbDate.day
        )
        guard let date = Calendar.autoupdatingCurrent.date(from: components) else {
            return String(format: "%04d-%02d-%02d", tmdbDate.year, tmdbDate.month, tmdbDate.day)
        }
        return date.formatted(date: .abbreviated, time: .omitted)
    }
}
