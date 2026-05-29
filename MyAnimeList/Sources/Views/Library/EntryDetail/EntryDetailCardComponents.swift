//
//  EntryDetailCardComponents.swift
//  MyAnimeList
//
//  Created by OpenAI Codex on 2026/5/21.
//

import DataProvider
import Kingfisher
import SwiftUI

struct PersonCardView: View {
    let card: EntryDetailPersonCard

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Group {
                if let profileURL = card.profileURL {
                    KFImageView(url: profileURL, targetWidth: 240, diskCacheExpiration: .longTerm)
                        .scaledToFill()
                        .frame(width: 122, height: 156)
                        .clipped()
                } else {
                    Rectangle()
                        .fill(Color.secondary.opacity(0.15))
                        .overlay {
                            Image(systemName: "person.fill")
                                .font(.system(size: 34))
                                .foregroundStyle(.secondary)
                        }
                }
            }
            .frame(width: 122, height: 156)
            .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))

            Text(card.primaryText)
                .font(.subheadline.weight(.semibold))
                .lineLimit(2)

            Text(card.secondaryText)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(2)
        }
        .frame(width: 138, alignment: .leading)
        .padding(12)
        .popupGlassPanel(cornerRadius: 24)
    }
}

struct EpisodeRowView: View {
    let card: EntryDetailEpisodeCard
    let previewContext: EpisodePreviewContext?
    let isWatched: Bool
    @State private var showPreview = false
    @State private var previewHapticTrigger = false

    init(
        card: EntryDetailEpisodeCard,
        previewContext: EpisodePreviewContext? = nil,
        isWatched: Bool = false
    ) {
        self.card = card
        self.previewContext = previewContext
        self.isWatched = isWatched
    }

    var body: some View {
        HStack(spacing: 14) {
            Group {
                if let imageURL = card.imageURL {
                    KFImageView(url: imageURL, targetWidth: 500, diskCacheExpiration: .transient)
                        .scaledToFill()
                        .frame(width: 126, height: 74)
                        .clipped()
                } else {
                    Rectangle()
                        .fill(Color.secondary.opacity(0.15))
                        .overlay {
                            Image(systemName: "tv")
                                .foregroundStyle(.secondary)
                        }
                }
            }
            .frame(width: 126, height: 74)
            .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
            .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 6) {
                Text(card.title)
                    .font(.subheadline.weight(.semibold))
                    .lineLimit(2)
                Text(card.subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }

            Spacer(minLength: 0)

            statusAccessory
        }
        .padding(12)
        .popupGlassPanel(cornerRadius: 22)
        .accessibilityElement(children: .combine)
        .accessibilityValue(Text(verbatim: isWatched ? String(localized: EntryDetailL10n.watched) : ""))
        .onLongPressGesture {
            guard previewContext != nil else { return }
            previewHapticTrigger.toggle()
            showPreview = true
        }
        .sensoryFeedback(.impact(flexibility: .solid), trigger: previewHapticTrigger)
        .popover(isPresented: $showPreview) {
            if let previewContext {
                EpisodePreviewCard(card: card, context: previewContext)
                    .presentationCompactAdaptation(.popover)
            }
        }
    }

    @ViewBuilder
    private var statusAccessory: some View {
        if isWatched {
            Image(systemName: "checkmark.circle.fill")
                .font(.subheadline.weight(.semibold))
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(.blue)
                .accessibilityHidden(true)
        } else {
            EmptyView()
        }
    }
}
