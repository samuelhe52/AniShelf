import SwiftUI

struct LibraryNavigationTitleCapsule: View {
    let count: Int

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 5) {
            Text("\(count)")
                .font(.title3.weight(.bold))
                .monospacedDigit()
            Text(animeTitleResource)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 13)
        .padding(.vertical, 6)
        .background {
            Capsule(style: .continuous)
                .fill(.white.opacity(0.055))
        }
        .overlay {
            Capsule(style: .continuous)
                .stroke(.white.opacity(0.11), lineWidth: 1)
        }
    }

    private var animeTitleResource: LocalizedStringResource {
        "Anime"
    }
}
