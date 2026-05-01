import SwiftUI

fileprivate struct LibraryCapsuleSurface<Content: View>: View {
    var horizontalPadding: CGFloat
    var verticalPadding: CGFloat
    let content: Content

    init(
        horizontalPadding: CGFloat = 13,
        verticalPadding: CGFloat = 6,
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
            .background {
                Capsule(style: .continuous)
                    .fill(.white.opacity(0.055))
            }
            .overlay {
                Capsule(style: .continuous)
                    .stroke(.white.opacity(0.11), lineWidth: 1)
            }
    }
}

struct LibraryNavigationTitleCapsule: View {
    let count: Int

    var body: some View {
        LibraryCapsuleSurface {
            HStack(alignment: .firstTextBaseline, spacing: 5) {
                Text("\(count)")
                    .font(.title3.weight(.bold))
                    .monospacedDigit()
                Text(animeTitleResource)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var animeTitleResource: LocalizedStringResource {
        "Anime"
    }
}

struct LibraryToolbarSummaryCapsule: View {
    let primary: LocalizedStringResource

    var body: some View {
        LibraryCapsuleSurface(horizontalPadding: 12, verticalPadding: 6) {
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
            .minimumScaleFactor(0.82)
        }
    }
}
