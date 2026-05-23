import DataProvider
import SwiftUI

struct LibraryWatchStatusIndicator: View {
    let status: AnimeEntry.WatchStatus
    var diameter: CGFloat
    var strokeColor: Color = .clear
    var strokeWidth: CGFloat = 0
    var shadowColor: Color = .clear
    var shadowRadius: CGFloat = 0
    var shadowYOffset: CGFloat = 0

    var body: some View {
        Circle()
            .fill(status.libraryTintColor)
            .frame(width: diameter, height: diameter)
            .overlay {
                if strokeWidth > 0 {
                    Circle()
                        .stroke(strokeColor, lineWidth: strokeWidth)
                }
            }
            .shadow(color: shadowColor, radius: shadowRadius, y: shadowYOffset)
    }
}

struct LibraryWatchStatusBadge: View {
    let status: AnimeEntry.WatchStatus

    var body: some View {
        HStack(spacing: 6) {
            LibraryWatchStatusIndicator(status: status, diameter: 5)
            Text(status.localizedStringResource)
                .font(Self.textFont)
                .foregroundStyle(status.libraryTintColor.opacity(0.92))
                .lineLimit(1)
        }
        .padding(.horizontal, Self.horizontalPadding)
        .padding(.vertical, Self.verticalPadding)
        .background {
            Capsule(style: .continuous)
                .fill(status.libraryTintColor.opacity(0.09))
        }
    }

    fileprivate static let horizontalPadding: CGFloat = 8
    fileprivate static let verticalPadding: CGFloat = 4
    fileprivate static let textFont = Font.caption2.weight(.semibold)
    fileprivate static let iconFont = Font.system(size: 10).weight(.semibold)
}

struct LibraryScoreBadge: View {
    enum Style {
        case inline
        case posterOverlay
    }

    @AppStorage(.libraryScoringEnabled) private var scoringEnabled = true

    let score: Int?
    var style: Style = .inline

    var body: some View {
        if scoringEnabled, let score {
            HStack(alignment: .lastTextBaseline, spacing: 4) {
                Image(systemName: "star.fill")
                    .font(iconFont)
                    .symbolRenderingMode(.hierarchical)
                Text("\(score)")
                    .font(textFont)
                    .monospacedDigit()
            }
            .foregroundStyle(foregroundStyle)
            .lineLimit(1)
            .padding(.horizontal, horizontalPadding)
            .padding(.vertical, verticalPadding)
            .background {
                Capsule(style: .continuous)
                    .fill(backgroundStyle)
            }
            .accessibilityLabel(Text("Score \(score)"))
        }
    }

    private var iconFont: Font {
        switch style {
        case .inline: LibraryWatchStatusBadge.iconFont
        case .posterOverlay: .system(size: 10, weight: .bold)
        }
    }

    private var textFont: Font {
        switch style {
        case .inline: LibraryWatchStatusBadge.textFont
        case .posterOverlay: .system(size: 11, weight: .bold)
        }
    }

    private var foregroundStyle: some ShapeStyle {
        switch style {
        case .inline: return .yellow.opacity(0.95)
        case .posterOverlay: return .white.opacity(0.96)
        }
    }

    private var backgroundStyle: some ShapeStyle {
        switch style {
        case .inline: return .yellow.opacity(0.12)
        case .posterOverlay: return .black.opacity(0.38)
        }
    }

    private var horizontalPadding: CGFloat {
        switch style {
        case .inline: 7
        case .posterOverlay: 7
        }
    }

    private var verticalPadding: CGFloat {
        switch style {
        case .inline: 4
        case .posterOverlay: 5
        }
    }
}

struct LibraryEpisodeProgressBadge: View {
    @AppStorage(.episodeProgressTrackingEnabled) private var episodeProgressTrackingEnabled = false
    @Environment(\.colorScheme) private var colorScheme

    let label: String?
    let fractionCompleted: Double?

    var body: some View {
        if episodeProgressTrackingEnabled, let label, !label.isEmpty {
            HStack(spacing: 5) {
                Image(systemName: "play.rectangle.fill")
                    .font(LibraryWatchStatusBadge.iconFont)
                    .symbolRenderingMode(.hierarchical)
                Text(label)
                    .font(LibraryWatchStatusBadge.textFont)
                    .monospacedDigit()
                    .lineLimit(1)
                    .minimumScaleFactor(0.78)
            }
            .foregroundStyle(progressTint)
            .padding(.horizontal, 7)
            .padding(.vertical, 4)
            .background {
                progressBackground
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(Text("Episode progress \(label)"))
        }
    }

    private var progressBackground: some View {
        GeometryReader { geometry in
            ZStack(alignment: .leading) {
                Capsule(style: .continuous)
                    .fill(progressTint.opacity(colorScheme == .dark ? 0.12 : 0.08))

                if let fillWidth = fillWidth(for: geometry.size.width) {
                    Capsule(style: .continuous)
                        .fill(fillGradient)
                        .frame(width: fillWidth)
                }
            }
            .clipShape(Capsule(style: .continuous))
        }
    }

    private var clampedFractionCompleted: Double? {
        fractionCompleted.map { min(max($0, 0), 1) }
    }

    private func fillWidth(for totalWidth: CGFloat) -> CGFloat? {
        guard let clampedFractionCompleted, clampedFractionCompleted > 0 else { return nil }
        return min(totalWidth, max(totalWidth * clampedFractionCompleted, 18))
    }

    private var progressTint: Color {
        .cyan
    }

    private var fillGradient: LinearGradient {
        LinearGradient(
            colors: [
                // progressTint.opacity(colorScheme == .dark ? 0.24 : 0.18),
                // progressTint.opacity(colorScheme == .dark ? 0.14 : 0.1)
                progressTint.opacity(0.24),
                progressTint.opacity(0.14)
            ],
            startPoint: .leading,
            endPoint: .trailing
        )
    }
}

struct LibraryPosterEpisodeProgressBar: View {
    enum Style {
        case compact
        case regular

        var containerHeight: CGFloat {
            switch self {
            case .compact: 14
            case .regular: 18
            }
        }

        var barHeight: CGFloat {
            switch self {
            case .compact: 4
            case .regular: 6
            }
        }

        var fadeHeight: CGFloat {
            switch self {
            case .compact: 14
            case .regular: 18
            }
        }
    }

    @AppStorage(.episodeProgressTrackingEnabled) private var episodeProgressTrackingEnabled = false
    @AppStorage(.libraryPosterProgressBarOverlayEnabled)
    private var posterProgressBarOverlayEnabled = true

    let fractionCompleted: Double?
    var style: Style = .regular

    var body: some View {
        if episodeProgressTrackingEnabled, posterProgressBarOverlayEnabled, let clampedFractionCompleted {
            LibraryEpisodeProgressTrack(
                fractionCompleted: clampedFractionCompleted,
                style: style
            )
            .frame(maxWidth: .infinity)
            .frame(height: style.containerHeight)
            .allowsHitTesting(false)
            .accessibilityHidden(true)
        }
    }

    private var clampedFractionCompleted: Double? {
        fractionCompleted.map { min(max($0, 0), 1) }
    }
}

fileprivate struct LibraryEpisodeProgressTrack: View {
    let fractionCompleted: Double
    let style: LibraryPosterEpisodeProgressBar.Style
    private let minimumFillWidth: CGFloat = 14

    var body: some View {
        GeometryReader { geometry in
            let availableWidth = max(geometry.size.width, 0)
            let fillWidth = min(
                availableWidth,
                max(availableWidth * fractionCompleted, minimumFillWidth)
            )

            ZStack(alignment: .bottomLeading) {
                LinearGradient(
                    colors: [
                        .clear,
                        .black.opacity(0.1),
                        .black.opacity(0.22)
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )
                .frame(height: style.fadeHeight)
                .frame(maxHeight: .infinity, alignment: .bottom)

                Capsule(style: .continuous)
                    .fill(progressFill)
                    .frame(width: fillWidth, height: style.barHeight)
            }
        }
    }

    private var progressFill: LinearGradient {
        LinearGradient(
            colors: [
                Color(red: 1.0, green: 0.69, blue: 0.26),
                Color(red: 0.98, green: 0.56, blue: 0.16)
            ],
            startPoint: .leading,
            endPoint: .trailing
        )
    }
}

struct LibraryFavoriteSymbol: View {
    let isFavorite: Bool
    var font: Font
    var filledColor: Color = .pink.opacity(0.94)
    var emptyColor: Color = .secondary.opacity(0.9)
    var shadowColor: Color = .clear
    var shadowRadius: CGFloat = 0
    var shadowYOffset: CGFloat = 0

    var body: some View {
        Image(systemName: isFavorite ? "heart.fill" : "heart")
            .font(font)
            .foregroundStyle(isFavorite ? filledColor : emptyColor)
            .shadow(color: shadowColor, radius: shadowRadius, y: shadowYOffset)
            .contentTransition(.symbolEffect(.replace))
            .animation(.snappy(duration: 0.18), value: isFavorite)
    }
}

struct LibraryFavoriteToggle<Label: View>: View {
    @Environment(\.toggleFavorite) private var toggleFavorite
    @State private var favoriteOverride: Bool?

    let entry: AnimeEntry
    let displayedIsFavorite: Bool
    private let label: (Bool) -> Label

    init(
        entry: AnimeEntry,
        displayedIsFavorite: Bool? = nil,
        @ViewBuilder label: @escaping (Bool) -> Label
    ) {
        self.entry = entry
        self.displayedIsFavorite = displayedIsFavorite ?? entry.favorite
        self.label = label
    }

    var body: some View {
        Button {
            favoriteOverride = !isFavorite
            toggleFavorite(entry)
        } label: {
            label(isFavorite)
        }
        .buttonStyle(.borderless)
        .sensoryFeedback(.impact, trigger: isFavorite)
        .accessibilityLabel(Text(favoriteActionResource))
        .onChange(of: displayedIsFavorite, initial: true) { _, newValue in
            guard favoriteOverride != nil else { return }
            if favoriteOverride == newValue {
                favoriteOverride = nil
            }
        }
    }

    private var isFavorite: Bool {
        favoriteOverride ?? displayedIsFavorite
    }

    private var favoriteActionResource: LocalizedStringResource {
        isFavorite ? "Unfavorite" : "Favorite"
    }
}

extension AnimeEntry.WatchStatus {
    var libraryTintColor: Color {
        switch self {
        case .planToWatch:
            .secondary
        case .watching:
            .orange
        case .watched:
            .green
        case .dropped:
            .pink
        }
    }
}
