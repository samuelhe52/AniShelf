//
//  MacAboutView.swift
//  AniShelf
//
//  Created by Claude Code on behalf of Samuel He on 2026/10/17.
//

#if os(macOS)
    import SwiftUI

    /// The About window (AniShelf ▸ About AniShelf), as Mac apps have: icon, name, version,
    /// and a few links, centered.
    struct MacAboutView: View {
        var body: some View {
            VStack(spacing: 14) {
                Image("app-icon")
                    .resizable()
                    .interpolation(.high)
                    .scaledToFit()
                    .frame(width: 96, height: 96)
                    .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))

                VStack(spacing: 4) {
                    Text(AboutAniShelfContent.appName)
                        .font(.title.weight(.bold))
                    if let versionDescription = AboutAniShelfContent.versionDescription {
                        Text(versionDescription)
                            .font(.callout)
                            .foregroundStyle(.secondary)
                            .textSelection(.enabled)
                    }
                }

                VStack(spacing: 6) {
                    Text(AboutAniShelfContent.tagline)
                    Text(AboutAniShelfContent.introduction)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)

                Divider()

                VStack(spacing: 6) {
                    HStack(spacing: 16) {
                        link(AboutAniShelfContent.website, AboutAniShelfContent.websiteURL)
                        link(AboutAniShelfContent.privacyPolicy, AboutAniShelfContent.privacyPolicyURL)
                        link(AboutAniShelfContent.tmdb, AboutAniShelfContent.tmdbURL)
                    }
                    HStack(spacing: 16) {
                        link(AboutAniShelfContent.sourceCode, AboutAniShelfContent.githubURL)
                        link(AboutAniShelfContent.githubProfile, AboutAniShelfContent.githubProfileURL)
                    }
                }
                .font(.callout)

                Text(AboutAniShelfContent.credits)
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.horizontal, 28)
            .padding(.top, 8)
            .padding(.bottom, 24)
            .frame(width: 380)
        }

        private func link(_ title: LocalizedStringResource, _ url: URL) -> some View {
            Link(destination: url) { Text(title) }
        }
    }
#endif
