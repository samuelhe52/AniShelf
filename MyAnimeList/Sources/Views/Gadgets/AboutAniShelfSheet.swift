import SwiftUI

struct AboutAniShelfSheet: View {
    @Environment(\.dismiss) private var dismiss

    private let githubURL = URL(string: "https://github.com/samuelhe52/AniShelf")!
    private let githubProfileURL = URL(string: "https://github.com/samuelhe52")!
    private let tmdbURL = URL(string: "https://www.themoviedb.org/")!

    var body: some View {
        ScrollView {
            VStack(spacing: 14) {
                heroCard
                summaryCard
                linksCard
            }
            .padding(.horizontal, 20)
            .padding(.top, 16)
            .padding(.bottom, 16)
        }
        .scrollBounceBehavior(.basedOnSize)
        .navigationTitle(aboutTitleResource)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button(doneTitleResource) { dismiss() }
            }
        }
    }

    private var heroCard: some View {
        HStack(spacing: 16) {
            Image("app-icon")
                .resizable()
                .interpolation(.high)
                .scaledToFit()
                .frame(width: 90, height: 90)
                .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
                .shadow(color: .black.opacity(0.14), radius: 12, y: 6)

            VStack(alignment: .leading, spacing: 6) {
                Text(appNameResource)
                    .font(.title2.weight(.bold))

                Text(taglineResource)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.leading)
                    .fixedSize(horizontal: false, vertical: true)

                if let versionDescription {
                    Text(versionDescription)
                        .font(.footnote)
                        .foregroundStyle(.tertiary)
                }
            }

            Spacer(minLength: 0)
        }
        .padding(16)
        .popupGlassPanel(cornerRadius: 28, tint: .clear)
    }

    private var summaryCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(introductionBodyResource)
                .font(.subheadline)
                .fixedSize(horizontal: false, vertical: true)
            featureRow
        }
        .padding(16)
        .popupGlassPanel(cornerRadius: 28, tint: .clear)
    }

    private var featureRow: some View {
        HStack(spacing: 10) {
            featureBadge(
                title: trackingTitleResource,
                systemImage: "checklist"
            )
            featureBadge(
                title: notesTitleResource,
                systemImage: "note.text"
            )
            featureBadge(
                title: syncTitleResource,
                systemImage: "externaldrive"
            )
        }
    }

    private func featureBadge(
        title: LocalizedStringResource,
        systemImage: String
    ) -> some View {
        HStack(spacing: 6) {
            Image(systemName: systemImage)
                .font(.footnote.weight(.semibold))
            Text(title)
                .font(.footnote.weight(.semibold))
                .lineLimit(1)
                .minimumScaleFactor(0.9)
        }
        .foregroundStyle(.secondary)
        .frame(maxWidth: .infinity)
        .padding(.vertical, 10)
        .background(.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    private var linksCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(linksTitleResource)
                .font(.footnote.weight(.semibold))
                .foregroundStyle(.secondary)

            VStack(spacing: 10) {
                aboutLinkRow(
                    title: sourceCodeTitleResource,
                    systemImage: "chevron.left.forwardslash.chevron.right",
                    destination: githubURL
                )

                aboutLinkRow(
                    title: githubProfileTitleResource,
                    systemImage: "person.crop.circle",
                    destination: githubProfileURL
                )

                aboutLinkRow(
                    title: tmdbTitleResource,
                    systemImage: "film.stack",
                    destination: tmdbURL
                )
            }

            Text(creditsBodyResource)
                .font(.caption)
                .foregroundStyle(.tertiary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(16)
        .popupGlassPanel(cornerRadius: 28, tint: .clear)
    }

    private func aboutLinkRow(
        title: LocalizedStringResource,
        systemImage: String,
        destination: URL
    ) -> some View {
        Link(destination: destination) {
            HStack(spacing: 12) {
                Image(systemName: systemImage)
                    .font(.headline.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .frame(width: 32, height: 32)
                    .background(.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 12, style: .continuous))

                Text(title)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.primary)

                Spacer(minLength: 12)

                Image(systemName: "arrow.up.right")
                    .font(.footnote.weight(.bold))
                    .foregroundStyle(.tertiary)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .background(.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private var versionDescription: String? {
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String
        let build = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String

        switch (version, build) {
        case (.some(let version), .some(let build)) where !version.isEmpty && !build.isEmpty:
            return "Version \(version) (\(build))"
        case (.some(let version), _) where !version.isEmpty:
            return "Version \(version)"
        default:
            return nil
        }
    }

    private var aboutTitleResource: LocalizedStringResource {
        "About AniShelf"
    }

    private var doneTitleResource: LocalizedStringResource {
        "Done"
    }

    private var appNameResource: LocalizedStringResource {
        "AniShelf"
    }

    private var taglineResource: LocalizedStringResource {
        "A native anime tracker built around your own library."
    }

    private var introductionBodyResource: LocalizedStringResource {
        "AniShelf keeps watch status, dates, and quick notes together so your collection stays useful over time."
    }

    private var creditsBodyResource: LocalizedStringResource {
        "Made by Samuel He. Metadata and artwork are provided by TMDb."
    }

    private var trackingTitleResource: LocalizedStringResource {
        "Tracking"
    }

    private var notesTitleResource: LocalizedStringResource {
        "Notes"
    }

    private var syncTitleResource: LocalizedStringResource {
        "Backups"
    }

    private var sourceCodeTitleResource: LocalizedStringResource {
        "AniShelf on GitHub"
    }

    private var tmdbTitleResource: LocalizedStringResource {
        "TMDb"
    }

    private var githubProfileTitleResource: LocalizedStringResource {
        "Samuel He on GitHub"
    }

    private var linksTitleResource: LocalizedStringResource {
        "Links"
    }
}

#Preview {
    NavigationStack {
        AboutAniShelfSheet()
    }
}
