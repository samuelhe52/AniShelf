//
//  EntryDetailStatGrid.swift
//  AniShelf
//
//  Created by OpenAI Codex on behalf of Samuel He on 2026/8/6.
//

import DataProvider
import SwiftUI

/// The stat card grid in entry detail.
///
/// Card behavior is selected by ``EntryDetailStatKind``, never by icon name or
/// array position.
struct EntryDetailStatGrid: View {
    @State private var showingProductionCompanies = false

    let availableCards: [EntryDetailStatCard]
    let productionCompanies: [EntryDetailProductionCompanyCard]
    let entryType: AnimeType
    let showProductionCompanyInsteadOfRuntime: Bool
    let onJumpToEpisodes: () -> Void

    var body: some View {
        LazyVGrid(columns: columns, spacing: 12) {
            ForEach(cards) { card in
                statCard(card)
            }
        }
    }

    private var cards: [EntryDetailStatCard] {
        switch entryType {
        case .movie:
            return availableCards
        case .series, .season:
            break
        }

        guard
            availableCards.contains(where: { $0.kind == .runtime }),
            availableCards.contains(where: { $0.kind == .production })
        else { return availableCards }

        let hiddenKind: EntryDetailStatKind =
            showProductionCompanyInsteadOfRuntime ? .runtime : .production
        return availableCards.filter { $0.kind != hiddenKind }
    }

    private var columns: [GridItem] {
        Array(
            repeating: GridItem(.flexible(), spacing: 12, alignment: .top),
            count: min(max(cards.count, 1), 3)
        )
    }

    @ViewBuilder
    private func statCard(_ card: EntryDetailStatCard) -> some View {
        switch card.kind {
        case .episodes:
            episodesCard(card)
        case .production:
            productionCard(card)
        case .runtime, .tmdbScore:
            DetailStatCard(card: card)
        }
    }

    private func episodesCard(_ card: EntryDetailStatCard) -> some View {
        Button(action: onJumpToEpisodes) {
            DetailStatCard(card: card)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Text(verbatim: "\(card.value), \(String(localized: card.title))"))
        .accessibilityHint(Text(EntryDetailL10n.jumpsToEpisodesSection))
    }

    private func productionCard(_ card: EntryDetailStatCard) -> some View {
        Button {
            showingProductionCompanies = true
        } label: {
            DetailStatCard(card: card)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Text(verbatim: "\(card.value), \(String(localized: card.title))"))
        .accessibilityHint(Text(EntryDetailL10n.showsAllProductionCompanies))
        .popover(isPresented: $showingProductionCompanies) {
            EntryDetailProductionCompaniesPopover(companies: productionCompanies)
                .presentationCompactAdaptation(.popover)
        }
    }
}
