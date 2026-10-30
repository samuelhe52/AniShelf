//
//  CategoryDraftPosterCell.swift
//  AniShelf
//
//  Created by Claude Code on behalf of Samuel He on 2026/10/30.
//

import SwiftUI

/// One candidate in the category sieve: a poster that dims while it waits, lights up when the
/// model matches it, and fades back when it does not.
///
/// A tap toggles any candidate the check has resolved. Selection looks and responds like the
/// library grid's multi-selection (`LibraryGridItem`): an unselected poster dims and shrinks a
/// little, and a tap gesture toggles it at once, without a button's delay inside a scroll view.
/// A top-trailing badge also marks selection.
///
/// Equatable on its data, so a toggle redraws only the poster that changed.
struct CategoryDraftPosterCell: View, @MainActor Equatable {
    let candidate: CategoryDraftCandidate
    let isAccepted: Bool
    /// Whether the cell sits under Not included, where rejections stay legible.
    var isNotIncluded = false
    let onToggle: () -> Void
    /// Whether the poster is in its brief bump for a new match.
    @State private var pops = false

    private let posterShape = RoundedRectangle(cornerRadius: 10, style: .continuous)

    static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.candidate == rhs.candidate && lhs.isAccepted == rhs.isAccepted && lhs.isNotIncluded == rhs.isNotIncluded
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            poster
            VStack(alignment: .leading, spacing: 1) {
                Text(candidate.metadata.name)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.primary.opacity(0.88))
                    .lineLimit(2)
                    .lineSpacing(-1)
                // A season shows its series' name, so its number tells sibling seasons apart.
                if let seasonLabel {
                    Text(seasonLabel)
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
            .frame(maxWidth: .infinity, minHeight: 26, alignment: .topLeading)
        }
        .opacity(look.opacity)
        .scaleEffect(look.scale)
        .overlay(alignment: .topTrailing) {
            // Kept outside the dimming, so it stays legible on a dimmed poster.
            badge
                .offset(x: 6, y: -6)
        }
        // A plain scale, not a `keyframeAnimator`: a keyframe-animated cell that the lazy grid
        // builds during the settle could stay undrawn, laid out and tappable but invisible.
        .scaleEffect(pops ? 1.08 : 1)
        .onChange(of: candidate.verdict == .match) { _, isMatch in
            // A verdict only becomes a match, never leaves one, so this plays once.
            guard isMatch else { return }
            Task { await pop() }
        }
        .contentShape(.rect)
        .simultaneousGesture(
            TapGesture().onEnded {
                if candidate.verdict.isResolved { onToggle() }
            }
        )
        .animation(.spring(response: 0.4, dampingFraction: 0.8).delay(revealDelay), value: candidate.verdict)
        .animation(.bouncy(duration: 0.18, extraBounce: 0.1), value: isAccepted)
        .sensoryFeedback(.selection, trigger: isAccepted)
        .accessibilityElement(children: .ignore)
        .accessibilityAddTraits(.isButton)
        .accessibilityAction {
            if candidate.verdict.isResolved { onToggle() }
        }
        .accessibilityLabel(accessibilityLabel)
        .accessibilityValue(accessibilityValue)
        .accessibilityAddTraits(isAccepted ? .isSelected : [])
    }

    private var poster: some View {
        Color.clear
            .aspectRatio(2.0 / 3.0, contentMode: .fit)
            .overlay {
                KFImageView(
                    url: candidate.metadata.posterURL(for: .grid),
                    targetSize: TMDbPosterDisplayType.grid.targetSize,
                    diskCacheExpiration: .shortTerm
                )
                .scaledToFill()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            .overlay {
                if candidate.verdict == .checking {
                    CategoryDraftShimmer()
                        .transition(.opacity)
                }
            }
            .saturation(look.saturation)
            .clipShape(posterShape)
            .shadow(color: .black.opacity(0.22), radius: 6, y: 3)
    }

    /// Selection, once the check has resolved the poster; an unchecked poster shows that instead.
    @ViewBuilder
    private var badge: some View {
        Group {
            if isAccepted {
                Image(systemName: "checkmark.circle.fill")
                    .symbolRenderingMode(.palette)
                    .foregroundStyle(.white, Color.accentColor)
                    .background(Circle().fill(.background).padding(-1.5))
            } else if candidate.verdict == .unchecked {
                Image(systemName: "exclamationmark.circle.fill")
                    .symbolRenderingMode(.palette)
                    .foregroundStyle(.white, .orange)
                    .background(Circle().fill(.background).padding(-1.5))
            } else if candidate.verdict == .match || (isNotIncluded && candidate.verdict == .rejected) {
                Image(systemName: "circle")
                    .foregroundStyle(.white)
                    .background(Circle().fill(.black.opacity(0.25)))
                    .shadow(color: .black.opacity(0.3), radius: 2)
            }
        }
        .font(.system(size: 19, weight: .semibold))
        .transition(.scale(scale: 0.4).combined(with: .opacity))
    }

    private struct Look {
        var opacity: Double
        var saturation: Double
        var scale: CGFloat
    }

    /// The check dims and desaturates waiting posters and fades rejected ones back. Once a
    /// poster is settled, selection alone decides, as in the library's multi-selection.
    private var look: Look {
        if isAccepted { return Look(opacity: 1, saturation: 1, scale: 1) }
        switch candidate.verdict {
        case .pending: return Look(opacity: 0.42, saturation: 0.15, scale: 0.95)
        case .checking: return Look(opacity: 0.6, saturation: 0.15, scale: 0.95)
        case .rejected where !isNotIncluded: return Look(opacity: 0.22, saturation: 0, scale: 0.9)
        default: return Look(opacity: 0.48, saturation: 1, scale: 0.95)
        }
    }

    /// Bumps the poster after its place in the batch's ripple, then lets it settle back.
    private func pop() async {
        try? await Task.sleep(for: .seconds(revealDelay))
        withAnimation(.spring(duration: 0.18)) { pops = true }
        try? await Task.sleep(for: .milliseconds(180))
        withAnimation(.spring(duration: 0.3)) { pops = false }
    }

    /// Staggers a batch's results, so they ripple in rather than land at once.
    private var revealDelay: Double {
        candidate.verdict.isResolved ? min(Double(candidate.revealIndex) * 0.045, 0.6) : 0
    }

    private var seasonLabel: LocalizedStringResource? {
        guard case .season(let seasonNumber, _) = candidate.metadata.type else { return nil }
        return seasonNumber == 0 ? "Specials" : "Season \(seasonNumber)"
    }

    private var accessibilityLabel: Text {
        guard let seasonLabel else { return Text(verbatim: candidate.metadata.name) }
        return Text(verbatim: "\(candidate.metadata.name), \(String(localized: seasonLabel))")
    }

    private var accessibilityValue: Text {
        switch (candidate.verdict, isAccepted) {
        case (_, true): Text("Selected")
        case (.pending, _), (.checking, _): Text("Checking")
        case (.unchecked, _): Text("Could not be checked")
        default: Text("Not selected")
        }
    }
}

/// A light sweep over a poster whose batch is in flight.
struct CategoryDraftShimmer: View {
    @State private var phase: CGFloat = -1

    var body: some View {
        GeometryReader { proxy in
            LinearGradient(
                colors: [.clear, .white.opacity(0.45), .clear],
                startPoint: .leading, endPoint: .trailing
            )
            .frame(width: proxy.size.width * 0.8)
            .rotationEffect(.degrees(12))
            .offset(x: phase * proxy.size.width * 1.4)
        }
        .allowsHitTesting(false)
        .onAppear {
            withAnimation(.linear(duration: 1.2).repeatForever(autoreverses: false)) { phase = 1 }
        }
    }
}
