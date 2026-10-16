import SwiftUI

struct AboutAniShelfSheet: View {
    @Environment(\.dismiss) private var dismiss

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
            .frame(maxWidth: 620)
            .frame(maxWidth: .infinity)
        }
        .scrollBounceBehavior(.basedOnSize)
        .preferredNavigationBarScrollEdgeEffect()
        .navigationTitle(AboutAniShelfContent.title)
        .inlineNavigationTitle()
        .toolbar {
            ToolbarItem(placement: .sheetTrailing) {
                Button(LocalizedStringResource("Done")) { dismiss() }
            }
        }
        .presentationSizing(.form)
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
                Text(AboutAniShelfContent.appName)
                    .font(.title2.weight(.bold))

                Text(AboutAniShelfContent.tagline)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.leading)
                    .fixedSize(horizontal: false, vertical: true)

                if let versionDescription = AboutAniShelfContent.versionDescription {
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
            Text(AboutAniShelfContent.introduction)
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
                title: AboutAniShelfContent.tracking,
                systemImage: "checklist"
            )
            featureBadge(
                title: AboutAniShelfContent.notes,
                systemImage: "note.text"
            )
            featureBadge(
                title: AboutAniShelfContent.backups,
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
            Text(AboutAniShelfContent.links)
                .font(.footnote.weight(.semibold))
                .foregroundStyle(.secondary)

            VStack(spacing: 10) {
                aboutLinkRow(
                    title: AboutAniShelfContent.website,
                    systemImage: "globe",
                    destination: AboutAniShelfContent.websiteURL
                )

                aboutLinkRow(
                    title: AboutAniShelfContent.privacyPolicy,
                    systemImage: "hand.raised",
                    destination: AboutAniShelfContent.privacyPolicyURL
                )

                aboutLinkRow(
                    title: AboutAniShelfContent.sourceCode,
                    systemImage: "chevron.left.forwardslash.chevron.right",
                    destination: AboutAniShelfContent.githubURL
                )

                aboutLinkRow(
                    title: AboutAniShelfContent.githubProfile,
                    systemImage: "person.crop.circle",
                    destination: AboutAniShelfContent.githubProfileURL
                )

                aboutLinkRow(
                    title: AboutAniShelfContent.tmdb,
                    systemImage: "film.stack",
                    destination: AboutAniShelfContent.tmdbURL
                )
            }

            Text(AboutAniShelfContent.credits)
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
}

#Preview {
    NavigationStack {
        AboutAniShelfSheet()
    }
}

/// Links and copy shared by the iOS About sheet and the Mac About window.
enum AboutAniShelfContent {
    static let websiteURL = URL(string: "https://anishelf.konakona.dev")!
    static let privacyPolicyURL = URL(string: "https://anishelf.konakona.dev/privacy/")!
    static let githubURL = URL(string: "https://github.com/samuelhe52/AniShelf")!
    static let githubProfileURL = URL(string: "https://github.com/samuelhe52")!
    static let tmdbURL = URL(string: "https://www.themoviedb.org/")!

    static let title: LocalizedStringResource = "About AniShelf"
    static let appName: LocalizedStringResource = "AniShelf"
    static let tagline: LocalizedStringResource = "A native anime tracker built around your own library."
    static let introduction: LocalizedStringResource =
        "AniShelf keeps watch status, dates, and quick notes together so your collection stays useful over time."
    static let credits: LocalizedStringResource = "Made by Samuel He. Metadata and artwork are provided by TMDb."
    static let tracking: LocalizedStringResource = "Tracking"
    static let notes: LocalizedStringResource = "Notes"
    static let backups: LocalizedStringResource = "Backups"
    static let website: LocalizedStringResource = "Website"
    static let privacyPolicy: LocalizedStringResource = "Privacy Policy"
    static let sourceCode: LocalizedStringResource = "AniShelf on GitHub"
    static let tmdb: LocalizedStringResource = "TMDb"
    static let githubProfile: LocalizedStringResource = "Samuel He on GitHub"
    static let links: LocalizedStringResource = "Links"

    static var versionDescription: String? {
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
}
