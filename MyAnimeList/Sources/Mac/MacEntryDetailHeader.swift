//
//  MacEntryDetailHeader.swift
//  AniShelf
//
//  Created by Claude Code on behalf of samuelhe52 on 2026/10/16.
//

#if os(macOS)
    import SwiftUI

    /// The inspector's entry header on the Mac: a small poster beside the title, metadata,
    /// and the quick actions, in place of the iOS full-width hero artwork.
    struct MacEntryDetailHeader<Actions: View>: View {
        let posterURL: URL?
        let displayTitle: String
        let subtitleText: String?
        let metadataLineItems: [String]
        let genreNames: [String]
        @ViewBuilder let actions: Actions

        private let posterSize = CGSize(width: 96, height: 144)

        var body: some View {
            HStack(alignment: .top, spacing: 14) {
                poster

                VStack(alignment: .leading, spacing: 4) {
                    Text(displayTitle)
                        .font(.title2.weight(.bold))
                        .lineLimit(3)
                        .textSelection(.enabled)

                    if let subtitleText {
                        Text(subtitleText)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .lineLimit(2)
                    }

                    if !metadataLineItems.isEmpty {
                        Text(metadataLineItems.joined(separator: " · "))
                            .font(.callout)
                            .foregroundStyle(.secondary)
                            .lineLimit(2)
                    }

                    if !genreNames.isEmpty {
                        Text(genreNames.joined(separator: ", "))
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                            .lineLimit(2)
                    }

                    Spacer(minLength: 8)

                    actions
                }
                .frame(maxWidth: .infinity, minHeight: posterSize.height, alignment: .topLeading)
            }
        }

        private var poster: some View {
            KFImageView(
                url: posterURL,
                targetSize: CGSize(width: posterSize.width * 2, height: posterSize.height * 2),
                diskCacheExpiration: .longTerm
            )
            .scaledToFill()
            .frame(width: posterSize.width, height: posterSize.height)
            .background(.fill.tertiary)
            .clipShape(.rect(cornerRadius: 8, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .stroke(.separator, lineWidth: 0.5)
            }
            .shadow(color: .black.opacity(0.18), radius: 4, y: 2)
            .accessibilityHidden(true)
        }
    }
#endif
