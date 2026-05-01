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
                .font(.caption2.weight(.semibold))
                .foregroundStyle(status.libraryTintColor.opacity(0.92))
                .lineLimit(1)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background {
            Capsule(style: .continuous)
                .fill(status.libraryTintColor.opacity(0.09))
        }
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
    private let label: (Bool) -> Label

    init(entry: AnimeEntry, @ViewBuilder label: @escaping (Bool) -> Label) {
        self.entry = entry
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
        .onChange(of: entry.favorite, initial: true) { _, newValue in
            guard favoriteOverride != nil else { return }
            if favoriteOverride == newValue {
                favoriteOverride = nil
            }
        }
    }

    private var isFavorite: Bool {
        favoriteOverride ?? entry.favorite
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
