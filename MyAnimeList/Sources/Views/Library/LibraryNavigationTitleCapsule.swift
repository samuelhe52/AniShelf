import SwiftUI

fileprivate struct LibraryCapsuleSurface<Content: View>: View {
    var horizontalPadding: CGFloat
    var verticalPadding: CGFloat
    let content: Content

    init(
        horizontalPadding: CGFloat = 13,
        verticalPadding: CGFloat = 7,
        @ViewBuilder content: () -> Content
    ) {
        self.horizontalPadding = horizontalPadding
        self.verticalPadding = verticalPadding
        self.content = content()
    }

    var body: some View {
        content
            .padding(.horizontal, horizontalPadding)
            .padding(.vertical, verticalPadding)
    }
}

struct LibraryNavigationTitleCapsule: View {
    let count: Int

    var body: some View {
        LibraryCapsuleSurface {
            HStack(alignment: .firstTextBaseline, spacing: 5) {
                Text("\(count)")
                    .font(.title2.weight(.bold))
                    .monospacedDigit()
                    .contentTransition(.numericText(countsDown: false))
                Text(animeTitleResource)
                    .font(.headline.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .contentTransition(.identity)
            }
            .animation(.bouncy, value: count)
        }
    }

    private var animeTitleResource: LocalizedStringResource {
        "Anime"
    }
}

struct LibraryToolbarSummaryCapsule: View {
    let primary: LocalizedStringResource

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: "slider.horizontal.3")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.secondary.opacity(0.92))

            Text(primary)
                .font(.subheadline.weight(.semibold))
                .lineLimit(1)

            Circle()
                .fill(.secondary.opacity(0.45))
                .frame(width: 3.5, height: 3.5)

            Image(systemName: "arrow.up.arrow.down")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.secondary)

            Image(systemName: "chevron.down")
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.tertiary)
        }
        .padding(.horizontal, 2)
        .minimumScaleFactor(0.82)
    }
}
