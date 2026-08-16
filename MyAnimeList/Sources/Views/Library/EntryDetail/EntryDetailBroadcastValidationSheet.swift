//
//  EntryDetailBroadcastValidationSheet.swift
//  AniShelf
//
//  Created by OpenAI Codex on behalf of Samuel He on 2026/8/16.
//

import Foundation
import Kingfisher
import SwiftUI

fileprivate enum MatchPresentation {
    case resolved
    case candidate
}

struct EntryDetailBroadcastValidationSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.locale) private var locale

    let model: EntryDetailBroadcastModel
    let searchTitle: String
    let displayTitle: String

    @State private var isConfirming = false
    @State private var isShowingSearch = false
    @State private var replacementCandidate: TVMazeShow?
    @State private var confirmingCandidate: TVMazeShow?

    var body: some View {
        NavigationStack {
            content
                .navigationTitle(navigationTitle)
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button(action: dismiss.callAsFunction) {
                            Image(systemName: "xmark")
                        }
                        .accessibilityLabel(EntryDetailL10n.close)
                        .disabled(isSavingConfirmation)
                    }
                }
        }
        .sheet(isPresented: $isShowingSearch) {
            EntryDetailBroadcastSearchSheet(
                model: model,
                initialQuery: searchTitle
            ) { candidate in
                replacementCandidate = candidate
                confirmingCandidate = nil
                isConfirming = false
            }
        }
        .onChange(of: model.phase) { _, phase in
            if isConfirming, case .resolved = phase {
                dismiss()
            }
        }
    }

    private var navigationTitle: LocalizedStringResource {
        if replacementCandidate == nil, case .resolved = model.phase {
            EntryDetailL10n.airtimeMatch
        } else {
            EntryDetailL10n.confirmAirtimeMatch
        }
    }

    @ViewBuilder
    private var content: some View {
        if isConfirming {
            if case .failed = model.phase {
                confirmationFailureContent
            } else {
                progressContent
            }
        } else if let replacementCandidate {
            candidateContent(replacementCandidate, presentation: .candidate)
        } else {
            switch model.phase {
            case .titleCandidate(let candidate):
                candidateContent(candidate, presentation: .candidate)
            case .titleSearching:
                progressContent
            case .failed:
                failureContent
            case .resolved:
                if let resolvedShow = model.resolvedShow {
                    candidateContent(resolvedShow, presentation: .resolved)
                } else {
                    failureContent
                }
            default:
                progressContent
                    .task {
                        model.startTitleFallback(named: searchTitle)
                    }
            }
        }
    }

    private var isSavingConfirmation: Bool {
        guard isConfirming else { return false }
        if case .titleSearching = model.phase {
            return true
        }
        return false
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

    private var confirmationFailureContent: some View {
        ContentUnavailableView {
            Label(EntryDetailL10n.couldNotSaveAirtimeMatch, systemImage: "exclamationmark.triangle")
        } actions: {
            Button(EntryDetailL10n.tryAgain) {
                guard let confirmingCandidate else { return }
                model.confirm(candidate: confirmingCandidate)
            }
            .buttonStyle(.borderedProminent)
        }
    }

    private func candidateContent(
        _ candidate: TVMazeShow,
        presentation: MatchPresentation
    ) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                candidateHeader(candidate, presentation: presentation)

                candidateMetadata(candidate)

                nextAiringContent(candidate)

                VStack(spacing: 15) {
                    if presentation == .candidate {
                        Button {
                            confirmingCandidate = candidate
                            isConfirming = true
                            model.confirm(candidate: candidate)
                        } label: {
                            Text(EntryDetailL10n.thisIsTheAnime)
                                .bold()
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 5)
                        }
                        .buttonStyle(.borderedProminent)
                        .buttonBorderShape(.roundedRectangle(radius: 15))
                    }

                    Button(
                        presentation == .resolved
                            ? EntryDetailL10n.notThisAnime
                            : EntryDetailL10n.notAMatch
                    ) {
                        isShowingSearch = true
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

    private func candidateHeader(
        _ candidate: TVMazeShow,
        presentation: MatchPresentation
    ) -> some View {
        HStack(alignment: .center, spacing: 14) {
            candidateArtwork(candidate)

            VStack(alignment: .leading, spacing: 8) {
                Text(
                    presentation == .resolved
                        ? EntryDetailL10n.resolved
                        : EntryDetailL10n.candidate
                )
                .font(.caption2.weight(.bold))
                .foregroundStyle(Color.accentColor)
                .textCase(.uppercase)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(Color.accentColor.opacity(0.12), in: Capsule())
                Text(presentation == .resolved ? displayTitle : candidate.name)
                    .font(.title2.weight(.bold))
                    .fixedSize(horizontal: false, vertical: true)
                if presentation == .resolved,
                    candidate.name.localizedCaseInsensitiveCompare(displayTitle) != .orderedSame
                {
                    Text(candidate.name)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Text(
                    presentation == .resolved
                        ? EntryDetailL10n.resolvedMatchHelp
                        : EntryDetailL10n.candidateConfirmationHelp
                )
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
            (EntryDetailL10n.aniShelfTitle, displayTitle)
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
        switch model.confirmationAvailability(for: candidate) {
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
                if case .disagrees(let tvMazeDate, let tmdbDate) = assessment {
                    VStack(alignment: .leading, spacing: 4) {
                        Label(
                            EntryDetailL10n.possiblyWrongAnime,
                            systemImage: "exclamationmark.triangle.fill"
                        )
                        .font(.subheadline.weight(.semibold))
                        Text(
                            EntryDetailL10n.airingDateConflictReason(
                                tvMazeDate: EntryDetailBroadcastFormatting.expectedDate(tvMazeDate),
                                tmdbDate: EntryDetailBroadcastFormatting.expectedDate(tmdbDate)
                            )
                        )
                        .font(.caption)
                    }
                    .foregroundStyle(.orange)
                }
            }
            .nextAiringSectionStyle()
        // `confirmationAvailability` suppresses TMDb fallback. Keep `.tmdbExpected` defensive so
        // this sheet never presents a TMDb date as the candidate's next airing.
        case .tmdbExpected, .unavailable:
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
