//
//  EntryDetailBroadcastComponents.swift
//  AniShelf
//
//  Created by OpenAI Codex on behalf of Samuel He on 2026/8/14.
//

import Foundation
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
                placeholderRow
            }
        case .resolved(let availability):
            airtimeSection(
                header: EntryDetailBroadcastFormatting.menuHeader(for: availability)
            ) {
                placeholderRow
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

    private var placeholderRow: some View {
        Text(verbatim: " ")
            .accessibilityHidden(true)
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
                candidateArtwork(candidate)

                VStack(alignment: .leading, spacing: 8) {
                    Text(EntryDetailL10n.candidate)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .textCase(.uppercase)
                    Text(candidate.name)
                        .font(.title2.weight(.bold))
                    Text(EntryDetailL10n.candidateConfirmationHelp)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }

                VStack(spacing: 12) {
                    metadataRow(title: EntryDetailL10n.aniShelfTitle, value: searchTitle)
                    if let language = candidate.language {
                        metadataRow(title: EntryDetailL10n.language, value: language)
                    }
                    if let premiered = candidate.premiered {
                        metadataRow(title: EntryDetailL10n.premiered, value: premiered)
                    }
                    if let schedule = EntryDetailBroadcastFormatting.scheduleSummary(candidate) {
                        metadataRow(title: EntryDetailL10n.broadcastSchedule, value: schedule)
                    }
                }

                nextAiringContent(candidate)

                VStack(spacing: 10) {
                    Button {
                        isConfirming = true
                        model.confirmTitleFallbackCandidate()
                    } label: {
                        Text(EntryDetailL10n.thisIsTheSeries)
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)

                    Button(EntryDetailL10n.notAMatch, role: .cancel) {
                        model.rejectTitleFallbackCandidate()
                        dismiss()
                    }
                    .frame(maxWidth: .infinity)
                }
            }
            .padding(20)
            .frame(maxWidth: 560)
            .frame(maxWidth: .infinity)
        }
    }

    @ViewBuilder
    private func candidateArtwork(_ candidate: TVMazeShow) -> some View {
        if let imageURL = candidate.fullImageURL {
            AsyncImage(url: imageURL) { phase in
                switch phase {
                case .success(let image):
                    image
                        .resizable()
                        .scaledToFit()
                default:
                    artworkPlaceholder
                }
            }
            .frame(maxWidth: .infinity)
            .frame(height: 280)
            .background(.quaternary)
            .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
        } else {
            artworkPlaceholder
                .frame(maxWidth: .infinity)
                .frame(height: 180)
        }
    }

    private var artworkPlaceholder: some View {
        RoundedRectangle(cornerRadius: 20, style: .continuous)
            .fill(.quaternary)
            .overlay {
                Image(systemName: "tv")
                    .font(.system(size: 42))
                    .foregroundStyle(.secondary)
            }
    }

    @ViewBuilder
    private func nextAiringContent(_ candidate: TVMazeShow) -> some View {
        switch model.availability(for: candidate) {
        case .tvMazeNextAiring(_, let airing, let assessment):
            VStack(alignment: .leading, spacing: 8) {
                Label(
                    EntryDetailBroadcastFormatting.nextAiringSummary(airing.airStamp),
                    systemImage: "clock"
                )
                .font(.headline)
                if let episode = EntryDetailBroadcastFormatting.episodeSummary(airing) {
                    Text(episode)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                if case .disagrees = assessment {
                    Label(
                        EntryDetailL10n.unreliableAirtime,
                        systemImage: "exclamationmark.triangle.fill"
                    )
                    .font(.subheadline)
                    .foregroundStyle(.orange)
                }
            }
        case .tmdbExpected(let evidence):
            VStack(alignment: .leading, spacing: 8) {
                Label(
                    EntryDetailBroadcastFormatting.expectedSummary(evidence.airDate),
                    systemImage: "calendar.badge.clock"
                )
                .font(.headline)
                Text(EntryDetailL10n.missingTVMazeNextAiring)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                Text(EntryDetailL10n.usesTMDbExpectedDateAfterConfirmation)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        case .unavailable:
            Label(EntryDetailL10n.nextAirtimeUnavailable, systemImage: "clock.badge.questionmark")
                .font(.headline)
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
        }
        .font(.subheadline)
    }
}

fileprivate enum EntryDetailBroadcastFormatting {
    static func menuHeader(for availability: BroadcastAvailability) -> String {
        switch availability {
        case .tvMazeNextAiring(_, let airing, let assessment):
            var components = [String(localized: EntryDetailL10n.nextUp)]
            if let episode = episodeSummary(airing) {
                components.append(episode)
            }
            components.append(compactDateTime(airing.airStamp))
            if case .disagrees = assessment {
                components.append("⚠︎")
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

    static func nextAiringSummary(_ date: Date) -> String {
        String(localized: EntryDetailL10n.nextAiring)
            + ": "
            + date.formatted(date: .abbreviated, time: .shortened)
    }

    static func expectedSummary(_ tmdbDate: TMDbCalendarDate) -> String {
        String(localized: EntryDetailL10n.expected)
            + ": "
            + calendarDate(tmdbDate)
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
            components.append(timeZone.identifier)
        }
        return components.joined(separator: " · ")
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
