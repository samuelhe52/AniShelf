//
//  EntryDetailCardComponents.swift
//  MyAnimeList
//
//  Created by OpenAI Codex on behalf of Samuel He on 2026/5/21.
//

import DataProvider
import Kingfisher
import SwiftUI

struct PersonCardView: View {
    @Environment(\.colorScheme) private var colorScheme

    let card: EntryDetailPersonCard

    private let cardWidth: CGFloat = 146
    private let portraitHeight: CGFloat = 168

    private var backgroundStyle: AnyShapeStyle {
        colorScheme == .dark
            ? AnyShapeStyle(Color(uiColor: .quaternarySystemFill))
            : AnyShapeStyle(.thinMaterial)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Group {
                if let profileURL = card.profileURL {
                    KFImageView(url: profileURL, targetWidth: 240, diskCacheExpiration: .shortTerm)
                        .scaledToFill()
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
            .frame(width: cardWidth, height: portraitHeight)
            .clipped()

            VStack(alignment: .leading, spacing: 8) {
                Text(card.primaryText)
                    .font(.subheadline.weight(.semibold))
                    .lineLimit(2)

                Text(card.secondaryText)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(12)
        }
        .frame(width: cardWidth, alignment: .leading)
        .background(backgroundStyle)
        .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
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
        HStack(spacing: 0) {
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
            .padding(.trailing, 12)

            VStack(alignment: .leading, spacing: 6) {
                Text(card.title)
                    .font(.subheadline.weight(.semibold))
                    .lineLimit(2)
                Text(card.subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }

            Spacer(minLength: 4)

            statusAccessory
        }
        .padding(.vertical, 4)
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
