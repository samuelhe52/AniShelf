//
//  LibraryPresentationPolicy.swift
//  AniShelf
//
//  Created by OpenAI Codex on behalf of Samuel He on 2026/7/14.
//

import SwiftUI

/// Selects responsive library presentations from the space the content can actually use.
struct LibraryPresentationPolicy {
    struct GeometryTokens: Equatable {
        /// Minimum width at which entry detail remains useful as a trailing surface.
        var minimumDetailWidth: CGFloat = 400

        /// Width retained for the active library mode while detail is visible.
        var minimumGalleryWidthWithDetail: CGFloat = 430
        var minimumListWidthWithDetail: CGFloat = 400
        var minimumGridWidthWithDetail: CGFloat = 380

        /// Minimum height for each library surface while detail is visible.
        var minimumGalleryHeightWithDetail: CGFloat = 480
        var minimumListHeightWithDetail: CGFloat = 360
        var minimumGridHeightWithDetail: CGFloat = 360
        var minimumDetailHeight: CGFloat = 520

        /// Extra width that lets a short scene retain both vertically scrolling surfaces.
        var additionalWidthForShortDetail: CGFloat = 200

        /// Space occupied by the separator between the library and its inspector.
        var detailColumnSpacing: CGFloat = 1

        /// Gallery shelf geometry, derived from its 2:3 poster cards and visible chrome.
        var minimumGalleryShelfHeight: CGFloat = 480
        var galleryVerticalChromeHeight: CGFloat = 160
        var minimumGalleryCardWidth: CGFloat = 220
        var maximumGalleryCardWidth: CGFloat = 420
        var galleryCardSpacing: CGFloat = 24
        var galleryVisibleCardSpan: CGFloat = 1.55

        /// Minimum content regions for purpose-sized modal presentations.
        var minimumFormModalWidth: CGFloat = 520
        var minimumFormModalHeight: CGFloat = 420
        var minimumPageModalWidth: CGFloat = 700
        var minimumPageModalHeight: CGFloat = 520

        static let standard = GeometryTokens()
    }

    enum LibraryMode: Equatable {
        case gallery
        case list
        case grid
    }

    enum ModalIntent: Equatable {
        case automatic
        case form
        case page
    }

    enum DetailPresentation: Equatable {
        case sheet
        case inspector
    }

    enum GalleryArrangement: Equatable {
        case singlePage
        case shelf(cardWidth: CGFloat)
    }

    enum ModalSizing: Equatable {
        case automatic
        case form
        case page
    }

    struct Input: Equatable {
        var availableSize: CGSize
        var libraryMode: LibraryMode
        var dynamicTypeSize: DynamicTypeSize
        var modalIntent: ModalIntent

        init(
            availableSize: CGSize,
            libraryMode: LibraryMode,
            dynamicTypeSize: DynamicTypeSize = .large,
            modalIntent: ModalIntent = .automatic
        ) {
            self.availableSize = availableSize
            self.libraryMode = libraryMode
            self.dynamicTypeSize = dynamicTypeSize
            self.modalIntent = modalIntent
        }
    }

    struct Result: Equatable {
        var detailPresentation: DetailPresentation
        var galleryArrangement: GalleryArrangement
        var modalSizing: ModalSizing
    }

    var tokens: GeometryTokens

    init(tokens: GeometryTokens = .standard) {
        self.tokens = tokens
    }

    func evaluate(_ input: Input) -> Result {
        let scale = contentScale(for: input.dynamicTypeSize)

        return Result(
            detailPresentation: detailPresentation(
                availableSize: input.availableSize,
                mode: input.libraryMode,
                scale: scale
            ),
            galleryArrangement: galleryArrangement(
                availableSize: input.availableSize,
                mode: input.libraryMode,
                scale: scale
            ),
            modalSizing: modalSizing(
                availableSize: input.availableSize,
                intent: input.modalIntent,
                scale: scale
            )
        )
    }

    private func detailPresentation(
        availableSize: CGSize,
        mode: LibraryMode,
        scale: CGFloat
    ) -> DetailPresentation {
        let minimumLibrarySize = minimumLibrarySize(for: mode, scale: scale)
        let requiredWidth =
            minimumLibrarySize.width
            + tokens.minimumDetailWidth * scale
            + tokens.detailColumnSpacing
        let requiredHeight = max(
            minimumLibrarySize.height,
            tokens.minimumDetailHeight * scale
        )
        let fitsPreferredGeometry =
            availableSize.width >= requiredWidth
            && availableSize.height >= requiredHeight
        let fitsWideShortGeometry =
            availableSize.width
            >= requiredWidth + tokens.additionalWidthForShortDetail * scale
            && availableSize.height >= minimumLibrarySize.height

        guard fitsPreferredGeometry || fitsWideShortGeometry else {
            return .sheet
        }

        return .inspector
    }

    private func galleryArrangement(
        availableSize: CGSize,
        mode: LibraryMode,
        scale: CGFloat
    ) -> GalleryArrangement {
        guard mode == .gallery,
            availableSize.height >= tokens.minimumGalleryShelfHeight * scale
        else {
            return .singlePage
        }

        let availableCardHeight = max(
            0,
            availableSize.height - tokens.galleryVerticalChromeHeight * scale
        )
        let heightDerivedCardWidth = availableCardHeight * 2 / 3
        let cardWidth = min(
            max(heightDerivedCardWidth, tokens.minimumGalleryCardWidth * scale),
            tokens.maximumGalleryCardWidth * scale
        )
        let requiredWidth =
            cardWidth * tokens.galleryVisibleCardSpan
            + tokens.galleryCardSpacing * scale

        guard availableSize.width >= requiredWidth else {
            return .singlePage
        }

        return .shelf(cardWidth: cardWidth)
    }

    private func modalSizing(
        availableSize: CGSize,
        intent: ModalIntent,
        scale: CGFloat
    ) -> ModalSizing {
        switch intent {
        case .automatic:
            .automatic
        case .form:
            if fits(
                availableSize,
                minimumWidth: tokens.minimumFormModalWidth * scale,
                minimumHeight: tokens.minimumFormModalHeight * scale
            ) {
                .form
            } else {
                .automatic
            }
        case .page:
            if fits(
                availableSize,
                minimumWidth: tokens.minimumPageModalWidth * scale,
                minimumHeight: tokens.minimumPageModalHeight * scale
            ) {
                .page
            } else {
                .automatic
            }
        }
    }

    private func minimumLibrarySize(for mode: LibraryMode, scale: CGFloat) -> CGSize {
        switch mode {
        case .gallery:
            CGSize(
                width: tokens.minimumGalleryWidthWithDetail * scale,
                height: tokens.minimumGalleryHeightWithDetail * scale
            )
        case .list:
            CGSize(
                width: tokens.minimumListWidthWithDetail * scale,
                height: tokens.minimumListHeightWithDetail * scale
            )
        case .grid:
            CGSize(
                width: tokens.minimumGridWidthWithDetail * scale,
                height: tokens.minimumGridHeightWithDetail * scale
            )
        }
    }

    private func fits(
        _ availableSize: CGSize,
        minimumWidth: CGFloat,
        minimumHeight: CGFloat
    ) -> Bool {
        availableSize.width >= minimumWidth && availableSize.height >= minimumHeight
    }

    private func contentScale(for dynamicTypeSize: DynamicTypeSize) -> CGFloat {
        switch dynamicTypeSize {
        case .xSmall, .small, .medium, .large:
            1
        case .xLarge:
            1.04
        case .xxLarge:
            1.08
        case .xxxLarge:
            1.12
        case .accessibility1:
            1.20
        case .accessibility2:
            1.30
        case .accessibility3:
            1.40
        case .accessibility4:
            1.50
        case .accessibility5:
            1.60
        @unknown default:
            1.60
        }
    }
}
