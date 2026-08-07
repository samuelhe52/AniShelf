//
//  EntryDetailHeaderComponents.swift
//  MyAnimeList
//
//  Created by OpenAI Codex on behalf of Samuel He on 2026/5/21.
//

import SwiftUI

struct EntryDetailHeroSection: View {
    let imageURL: URL?
    let logoImageURL: URL?
    let displayTitle: String
    let subtitleText: String?
    let metadataLineItems: [String]
    let genreNames: [String]
    let accentColor: Color
    let pageBackground: Color
    let scrollCoordinateSpaceName: String
    let height: CGFloat

    var body: some View {
        GeometryReader { proxy in
            let overscroll = max(
                proxy.frame(in: .named(scrollCoordinateSpaceName)).minY,
                0
            )
            let stretchedHeight = height + overscroll

            hero(height: stretchedHeight)
                .offset(y: -overscroll)
        }
        .frame(height: height)
    }

    private func hero(height: CGFloat) -> some View {
        ZStack(alignment: .bottom) {
            heroArtwork

            // Top scrim — keeps toolbar buttons legible
            LinearGradient(
                colors: [.black.opacity(0.42), .clear],
                startPoint: .top,
                endPoint: UnitPoint(x: 0.5, y: 0.22)
            )

            // Gradient scrim for text legibility
            LinearGradient(
                colors: [.clear, .black.opacity(0.78)],
                startPoint: UnitPoint(x: 0.5, y: 0.35),
                endPoint: .bottom
            )

            // Fade bottom edge into page background
            VStack(spacing: 0) {
                Spacer()
                LinearGradient(
                    colors: [.clear, pageBackground],
                    startPoint: .top,
                    endPoint: .bottom
                )
                .frame(height: 120)
            }

            VStack(spacing: 0) {
                Spacer(minLength: 0)

                VStack(alignment: .center, spacing: 6) {
                    if let logoImageURL {
                        KFImageView(
                            url: logoImageURL,
                            targetSize: CGSize(width: 500, height: 500),
                            diskCacheExpiration: .longTerm
                        )
                        .scaledToFit()
                        .frame(maxWidth: 280)
                        .frame(height: 78)
                        .shadow(color: .black.opacity(0.28), radius: 10, y: 6)
                    } else {
                        Text(displayTitle)
                            .font(.largeTitle.weight(.bold))
                            .foregroundStyle(.white)
                            .lineLimit(3)
                            .minimumScaleFactor(0.78)
                            .multilineTextAlignment(.center)
                    }

                    if let subtitleText {
                        Text(subtitleText)
                            .font(.subheadline.weight(.regular))
                            .foregroundStyle(.white.opacity(0.82))
                            .lineLimit(2)
                            .multilineTextAlignment(.center)
                    }

                    if !metadataLineItems.isEmpty {
                        Text(metadataLineItems.joined(separator: "  ·  "))
                            .font(.footnote)
                            .foregroundStyle(.white.opacity(0.68))
                            .lineLimit(2)
                            .multilineTextAlignment(.center)
                    }

                    if !genreNames.isEmpty {
                        Text(genreNames.joined(separator: ", "))
                            .font(.caption)
                            .foregroundStyle(.white.opacity(0.56))
                            .lineLimit(1)
                    }
                }
                .frame(maxWidth: 360)
                .padding(.horizontal, 24)
                .padding(.bottom, 36)
                .frame(maxWidth: .infinity)
            }
        }
        .containerRelativeFrame(.horizontal)
        .frame(height: height)
        .clipped()
    }

    @ViewBuilder
    private var heroArtwork: some View {
        if let imageURL {
            KFImageView(
                url: imageURL,
                targetSize: CGSize(width: 1_200, height: 675),
                diskCacheExpiration: .longTerm
            )
            .scaledToFill()
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            LinearGradient(
                colors: [accentColor.opacity(0.45), Color.blue.opacity(0.25)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .overlay {
                Image(systemName: "sparkles.tv")
                    .font(.system(size: 52))
                    .foregroundStyle(.white.opacity(0.55))
            }
        }
    }
}

struct DetailStatCard: View {
    let card: EntryDetailStatCard

    private var valueIsShrinkable: Bool { card.valueIsShrinkable }

    var body: some View {
        VStack(alignment: .leading) {
            Image(systemName: card.symbolName)
                .font(.headline)
                .foregroundStyle(.blue)
            Spacer()
            Text(card.value)
                .font(.title3.weight(.bold))
                .allowsTightening(valueIsShrinkable)
                .minimumScaleFactor(valueIsShrinkable ? 0.65 : 1)
            Spacer()
            Text(String(localized: card.title))
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, minHeight: 85, maxHeight: 85, alignment: .topLeading)
        .padding(16)
        .popupGlassPanel(cornerRadius: 24)
    }
}

struct EntryDetailQuickActionsRow: View {
    let detailURL: URL?
    let isFavorite: Bool
    let showsConvertAction: Bool
    let conversionInProgress: Bool
    let convertMenuTitle: () -> LocalizedStringResource
    let dropActionTitle: LocalizedStringResource
    let dropActionSystemImage: String
    let dropActionIsDestructive: Bool
    let onShare: () -> Void
    let onToggleFavorite: () -> Void
    let onChangePoster: () -> Void
    let onConvert: () async -> Void
    let onToggleDroppedStatus: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            Spacer(minLength: 0)

            if let detailURL {
                Link(destination: detailURL) {
                    Image(systemName: "safari")
                        .font(.title2)
                        .frame(width: 20, height: 20)
                        .padding(10)
                }
                .buttonStyle(.glass)
                .buttonBorderShape(.circle)
                .tint(.primary)
            }

            PopupActionCircleButton(
                systemImage: "square.and.arrow.up",
                verticalOffset: -1,
                action: onShare
            )

            PopupActionCircleButton(
                systemImage: isFavorite ? "heart.fill" : "heart",
                tint: isFavorite ? .pink : .primary,
                action: onToggleFavorite
            )

            Menu {
                Button(action: onChangePoster) {
                    Label(EntryDetailL10n.changePoster, systemImage: "photo.on.rectangle")
                }

                if showsConvertAction {
                    Button {
                        Task { await onConvert() }
                    } label: {
                        Label(convertMenuTitle(), systemImage: "arrow.triangle.2.circlepath")
                    }
                    .disabled(conversionInProgress)
                }

                Divider()

                Button(
                    dropActionTitle,
                    systemImage: dropActionSystemImage,
                    role: dropActionIsDestructive ? .destructive : nil,
                    action: onToggleDroppedStatus
                )
                .tint(dropActionIsDestructive ? .red : .primary)
            } label: {
                Image(systemName: "ellipsis")
                    .font(.title2)
                    .frame(width: 20, height: 20)
                    .padding(10)
            }
            .buttonStyle(.glass)
            .buttonBorderShape(.circle)
            .tint(.primary)

            Spacer(minLength: 0)
        }
    }
}
