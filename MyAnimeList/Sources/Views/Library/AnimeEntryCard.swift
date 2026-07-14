import DataProvider
import Kingfisher
import SwiftUI

struct AnimeEntryCard: View {
    @AppStorage(.libraryOpenDetailWithSingleTap) private var openDetailWithSingleTap = false
    @Environment(\.libraryEntryDetailActivation) private var detailActivation
    @AppStorage(.libraryLongTermGalleryPosterCachingEnabled)
    private var longTermGalleryPosterCachingEnabled = false

    var entry: AnimeEntry
    var snapshot: LibraryEntrySnapshot
    var onOpenDetails: (() -> Void)? = nil
    @Binding var imageLoaded: Bool
    var imageMissing: Bool { snapshot.posterMissing }
    private let posterShape = RoundedRectangle(cornerRadius: 28, style: .continuous)
    private let favoriteButtonTapClearance: CGFloat = 48

    init(
        entry: AnimeEntry,
        snapshot: LibraryEntrySnapshot? = nil,
        onOpenDetails: (() -> Void)? = nil,
        imageLoaded: Binding<Bool>
    ) {
        self.entry = entry
        self.snapshot = snapshot ?? LibraryEntrySnapshot(entry: entry)
        self.onOpenDetails = onOpenDetails
        self._imageLoaded = imageLoaded
    }

    var body: some View {
        Color.clear
            .aspectRatio(2.0 / 3.0, contentMode: .fit)
            .background {
                posterShape
                    .fill(.white.opacity(imageMissing ? 0.06 : 0.001))
            }
            .overlay { posterImage }
            .overlay { posterTapSurface }
            .overlay(alignment: .topLeading) { statusIndicator }
            .overlay(alignment: .topTrailing) { favoriteIndicator }
            .overlay(alignment: .bottom) { progressBar }
            .overlay(alignment: .bottomLeading) { scoreBadge }
            .overlay {
                posterShape
                    .stroke(.white.opacity(0.14), lineWidth: 1)
            }
            .clipShape(posterShape)
            .shadow(color: .black.opacity(0.12), radius: 16, y: 8)
            .padding(.horizontal, 12)
    }

    private var posterImage: some View {
        KFImageView(
            url: snapshot.displayPosterURL(for: .gallery),
            targetWidth: 1_000,
            diskCacheExpiration: LibraryImageCacheService.galleryPosterDiskCacheExpiration(
                longTermCachingEnabled: longTermGalleryPosterCachingEnabled
            ),
            imageLoaded: $imageLoaded
        )
        .scaledToFill()
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .clipped()
    }

    private var posterTapSurface: some View {
        VStack(spacing: 0) {
            HStack(spacing: 0) {
                Color.clear
                    .contentShape(.rect)
                    .onTapGesture(count: detailTapCount) { onOpenDetails?() }

                Color.clear
                    .frame(width: favoriteButtonTapClearance, height: favoriteButtonTapClearance)
                    .allowsHitTesting(false)
            }
            .frame(height: favoriteButtonTapClearance, alignment: .top)

            Color.clear
                .contentShape(.rect)
                .onTapGesture(count: detailTapCount) { onOpenDetails?() }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var detailTapCount: Int {
        detailActivation.usesSingleTap(userPreference: openDetailWithSingleTap) ? 1 : 2
    }

    private var statusIndicator: some View {
        LibraryWatchStatusIndicator(
            status: snapshot.watchStatus,
            diameter: 14,
            strokeColor: .white.opacity(0.9),
            strokeWidth: 2
        )
        .padding(14)
    }

    private var scoreBadge: some View {
        LibraryScoreBadge(score: snapshot.score, style: .posterOverlay)
            .padding(14)
    }

    private var progressBar: some View {
        LibraryPosterEpisodeProgressBar(fractionCompleted: snapshot.episodeProgressFraction)
    }

    private var favoriteIndicator: some View {
        LibraryFavoriteToggle(entry: entry, displayedIsFavorite: snapshot.isFavorite) { isFavorite in
            LibraryFavoriteSymbol(
                isFavorite: isFavorite,
                font: .system(size: 15, weight: .bold),
                emptyColor: .white.opacity(0.9),
                shadowColor: .black.opacity(0.16),
                shadowRadius: 4,
                shadowYOffset: 1
            )
            .frame(width: 34, height: 34)
        }
        .padding(7)
    }
}

#Preview {
    AnimeEntryCard(entry: .template(), imageLoaded: .constant(true))
}
