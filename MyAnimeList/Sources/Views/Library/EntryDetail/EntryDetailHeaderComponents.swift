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

            hero(width: proxy.size.width, height: stretchedHeight)
                .offset(y: -overscroll)
        }
        .frame(height: height)
    }

    private func hero(width: CGFloat, height: CGFloat) -> some View {
        ZStack(alignment: .bottom) {
            heroBackground
                .clipped()
                .verticalBarBackgroundExtension()

            heroText
        }
        // A portrait fallback must fill these bounds without increasing the layout height
        // and pushing the title over the controls below it.
        .frame(width: width, height: height)
    }

    /// The artwork and its scrims, which extend under iPhone Duo's vertical bar; the text stays
    /// inset.
    @ViewBuilder
    private var heroBackground: some View {
        #if os(macOS)
            // The inspector sits on a system material, so the artwork fades to transparent
            // instead of to a color.
            Color.clear
                .overlay { heroArtwork }
                // A lighter top scrim than iOS; the toolbar's glass controls need less help.
                .overlay {
                    LinearGradient(
                        colors: [.black.opacity(0.25), .clear],
                        startPoint: .top,
                        endPoint: UnitPoint(x: 0.5, y: 0.2)
                    )
                }
                .overlay { textScrim }
                .mask {
                    LinearGradient(
                        // Like the iOS fade, the text overlaps the lower part.
                        stops: [.init(color: .black, location: 0.7), .init(color: .clear, location: 1)],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                }
        #else
            Color.clear
                .overlay { heroArtwork }
                // Top scrim — keeps toolbar buttons legible
                .overlay {
                    LinearGradient(
                        colors: [.black.opacity(0.42), .clear],
                        startPoint: .top,
                        endPoint: UnitPoint(x: 0.5, y: 0.22)
                    )
                }
                .overlay { textScrim }
                // Fade bottom edge into page background
                .overlay(alignment: .bottom) {
                    LinearGradient(
                        colors: [.clear, pageBackground],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                    .frame(height: 120)
                }
        #endif
    }

    /// Gradient scrim for text legibility.
    private var textScrim: some View {
        LinearGradient(
            colors: [.clear, .black.opacity(0.78)],
            startPoint: UnitPoint(x: 0.5, y: 0.35),
            endPoint: .bottom
        )
    }

    private var heroText: some View {
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
    @Environment(\.popupPanelStyle) private var panelStyle
    let card: EntryDetailStatCard

    private var valueIsShrinkable: Bool { card.valueIsShrinkable }

    var body: some View {
        switch panelStyle {
        case .glass: tile
        case .grouped: compactTile
        }
    }

    /// One column of the Mac inspector's metric strip: a bold value over a gray caption.
    private var compactTile: some View {
        VStack(spacing: 2) {
            Text(card.value)
                .font(.title3.weight(.semibold))
                .lineLimit(1)
                .allowsTightening(valueIsShrinkable)
                .minimumScaleFactor(valueIsShrinkable ? 0.6 : 1)
            Text(String(localized: card.title))
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .minimumScaleFactor(0.85)
        }
        .padding(.horizontal, 6)
        .frame(maxWidth: .infinity)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
    }

    private var tile: some View {
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
    @Environment(\.popupPanelStyle) private var panelStyle
    @State private var editingReminder: AiringReminderSubscription?

    let openInLinks: EntryOpenInLinks
    let isFavorite: Bool
    let isCentered: Bool
    let showsConvertAction: Bool
    let conversionInProgress: Bool
    let convertMenuTitle: () -> LocalizedStringResource
    let dropActionTitle: LocalizedStringResource
    let dropActionSystemImage: String
    let dropActionIsDestructive: Bool
    let broadcastPhase: EntryDetailBroadcastModel.Phase
    let airingReminderContext: EntryDetailAiringReminderContext
    let hasAiringReminder: Bool
    let onShare: () -> Void
    let onToggleFavorite: () -> Void
    let onChangePoster: () -> Void
    let onPresentBroadcastValidation: () -> Void
    let onRetryBroadcast: () -> Void
    let onConvert: () async -> Void
    let onToggleDroppedStatus: () -> Void

    /// The Mac inspector uses compact bordered buttons instead of large glass circles.
    private var isCompact: Bool { panelStyle == .grouped }

    var body: some View {
        HStack(spacing: isCompact ? 6 : 10) {
            if isCentered {
                Spacer(minLength: 0)
            }

            EntryDetailOpenInMenu(links: openInLinks)

            PopupActionCircleButton(
                systemImage: "square.and.arrow.up",
                verticalOffset: -1,
                action: onShare
            )
            .macHelp(Text("Share"))

            PopupActionCircleButton(
                systemImage: isFavorite ? "heart.fill" : "heart",
                tint: isFavorite ? .pink : .primary,
                action: onToggleFavorite
            )
            .macHelp(Text(isFavorite ? "Remove from Favorites" : "Add to Favorites"))

            Menu {
                let broadcastMenuContent = EntryDetailBroadcastMenuContent(
                    phase: broadcastPhase,
                    airingReminderContext: airingReminderContext,
                    hasAiringReminder: hasAiringReminder,
                    onPresentValidation: onPresentBroadcastValidation,
                    onRetry: onRetryBroadcast,
                    onPresentReminderTiming: { editingReminder = $0 }
                )
                broadcastMenuContent

                if broadcastMenuContent.isVisible {
                    Divider()
                }

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
                PopupActionButtonLabel(systemImage: "ellipsis")
            }
            .popupActionButtonChrome()
            .menuIndicator(isCompact ? .hidden : .automatic)
            .macHelp(Text("More"))

            Spacer(minLength: 0)
        }
        .sheet(item: $editingReminder) { subscription in
            #if os(macOS)
                MacAiringReminderTimingSheet(
                    subscription: subscription,
                    defaultTiming: AiringReminderCoordinator.shared.snapshot.defaultTiming
                )
            #else
                AiringReminderTimingSheet(
                    subscription: subscription,
                    defaultTiming: AiringReminderCoordinator.shared.snapshot.defaultTiming
                )
            #endif
        }
    }
}

extension View {
    /// Mirrors this view under iPhone Duo's vertical bar, as Apple recommends for hero imagery;
    /// it has no effect where the system never places a vertical bar.
    fileprivate func verticalBarBackgroundExtension() -> some View {
        modifier(VerticalBarBackgroundExtension())
    }
}

fileprivate struct VerticalBarBackgroundExtension: ViewModifier {
    @Environment(\.self) private var environment

    func body(content: Content) -> some View {
        #if os(macOS)
            content
        #else
            if #available(iOS 27.1, *) {
                content.backgroundExtensionEffect(isEnabled: environment.toolbarVerticalEdge != nil)
            } else {
                content
            }
        #endif
    }
}
