//
//  LibraryPresentationPolicyTests.swift
//  AniShelf
//
//  Created by OpenAI Codex on behalf of Samuel He on 2026/7/14.
//

import SwiftUI
import Testing

@testable import MyAnimeList

struct LibraryPresentationPolicyTests {
    private let policy = LibraryPresentationPolicy()

    @Test func nearlyFullWindowCanUseInspectorWithoutADeviceCategory() {
        let result = policy.evaluate(
            .init(
                availableSize: CGSize(width: 820, height: 560),
                libraryMode: .list
            )
        )

        #expect(result.detailPresentation == .inspector)
    }

    @Test func largeResizableSceneCanUseShelfAndInspectorWithoutIdiomInput() {
        let result = policy.evaluate(
            .init(
                availableSize: CGSize(width: 1_000, height: 700),
                libraryMode: .gallery
            )
        )

        #expect(result.detailPresentation == .inspector)
        guard case .shelf = result.galleryArrangement else {
            Issue.record("Expected a Gallery shelf")
            return
        }
    }

    @Test func insufficientCoexistenceWidthUsesSheet() {
        let result = policy.evaluate(
            .init(
                availableSize: CGSize(width: 700, height: 900),
                libraryMode: .list
            )
        )

        #expect(result.detailPresentation == .sheet)
    }

    @Test func veryShortSceneKeepsCurrentSingleSurfaceBehavior() {
        let result = policy.evaluate(
            .init(
                availableSize: CGSize(width: 900, height: 390),
                libraryMode: .gallery
            )
        )

        #expect(result.detailPresentation == .sheet)
        #expect(result.galleryArrangement == .singlePage)
    }

    @Test func surplusWidthCompensatesForShortListDetail() {
        let belowThreshold = policy.evaluate(
            .init(
                availableSize: CGSize(width: 1_000, height: 430),
                libraryMode: .list
            )
        )
        let atThreshold = policy.evaluate(
            .init(
                availableSize: CGSize(width: 1_001, height: 430),
                libraryMode: .list
            )
        )

        #expect(belowThreshold.detailPresentation == .sheet)
        #expect(atThreshold.detailPresentation == .inspector)
    }

    @Test func wideShortDetailStillRequiresTheActiveModesMinimumHeight() {
        let shortList = policy.evaluate(
            .init(
                availableSize: CGSize(width: 1_100, height: 359),
                libraryMode: .list
            )
        )
        let viableList = policy.evaluate(
            .init(
                availableSize: CGSize(width: 1_100, height: 360),
                libraryMode: .list
            )
        )
        let shortGallery = policy.evaluate(
            .init(
                availableSize: CGSize(width: 1_100, height: 479),
                libraryMode: .gallery
            )
        )
        let viableGallery = policy.evaluate(
            .init(
                availableSize: CGSize(width: 1_100, height: 480),
                libraryMode: .gallery
            )
        )

        #expect(shortList.detailPresentation == .sheet)
        #expect(viableList.detailPresentation == .inspector)
        #expect(shortGallery.detailPresentation == .sheet)
        #expect(viableGallery.detailPresentation == .inspector)
    }

    @Test func currentLargePhoneLandscapeUsesSheetForListAndGrid() {
        let list = policy.evaluate(
            .init(
                availableSize: CGSize(width: 932, height: 430),
                libraryMode: .list
            )
        )
        let grid = policy.evaluate(
            .init(
                availableSize: CGSize(width: 932, height: 430),
                libraryMode: .grid
            )
        )

        #expect(list.detailPresentation == .sheet)
        #expect(grid.detailPresentation == .sheet)
    }

    @Test func currentLargePhonePortraitAndLandscapeKeepLegacyLibraryPresentations() {
        let sizes = [
            CGSize(width: 430, height: 932),
            CGSize(width: 932, height: 430)
        ]
        let modes: [LibraryPresentationPolicy.LibraryMode] = [.gallery, .list, .grid]

        for size in sizes {
            for mode in modes {
                let result = policy.evaluate(
                    .init(availableSize: size, libraryMode: mode)
                )

                #expect(result.detailPresentation == .sheet)
                if mode == .gallery {
                    #expect(result.galleryArrangement == .singlePage)
                }
            }
        }
    }

    @Test func accessibilityDynamicTypeCanReduceSimultaneousSurfaceCapacity() {
        let availableSize = CGSize(width: 820, height: 560)
        let standard = policy.evaluate(
            .init(
                availableSize: availableSize,
                libraryMode: .list,
                dynamicTypeSize: .large
            )
        )
        let accessibility = policy.evaluate(
            .init(
                availableSize: availableSize,
                libraryMode: .list,
                dynamicTypeSize: .accessibility2
            )
        )

        #expect(standard.detailPresentation == .inspector)
        #expect(accessibility.detailPresentation == .sheet)
    }

    @Test func accessibilityDynamicTypeScalesWideShortCompensation() {
        let availableSize = CGSize(width: 1_050, height: 430)
        let standard = policy.evaluate(
            .init(
                availableSize: availableSize,
                libraryMode: .list,
                dynamicTypeSize: .large
            )
        )
        let accessibility = policy.evaluate(
            .init(
                availableSize: availableSize,
                libraryMode: .list,
                dynamicTypeSize: .accessibility2
            )
        )

        #expect(standard.detailPresentation == .inspector)
        #expect(accessibility.detailPresentation == .sheet)
    }

    @Test func galleryShelfUsesHeightDerivedPosterWidthAndShowsNeighbors() {
        let result = policy.evaluate(
            .init(
                availableSize: CGSize(width: 820, height: 560),
                libraryMode: .gallery
            )
        )

        guard case .shelf(let cardWidth) = result.galleryArrangement else {
            Issue.record("Expected a Gallery shelf")
            return
        }

        #expect(abs(cardWidth - (CGFloat(400) * 2 / 3)) < 0.001)
        #expect(cardWidth * 1.55 + 24 < 820)
    }

    @Test func tallButNarrowGalleryRetainsSinglePageLayout() {
        let result = policy.evaluate(
            .init(
                availableSize: CGSize(width: 430, height: 932),
                libraryMode: .gallery
            )
        )

        #expect(result.galleryArrangement == .singlePage)
    }

    @Test func modalSizingHonorsPurposeAndAvailableContentArea() {
        let size = CGSize(width: 820, height: 560)
        let form = policy.evaluate(
            .init(availableSize: size, libraryMode: .list, modalIntent: .form)
        )
        let page = policy.evaluate(
            .init(availableSize: size, libraryMode: .list, modalIntent: .page)
        )
        let constrainedPage = policy.evaluate(
            .init(
                availableSize: CGSize(width: 650, height: 800),
                libraryMode: .list,
                modalIntent: .page
            )
        )

        #expect(form.modalSizing == .form)
        #expect(page.modalSizing == .page)
        #expect(constrainedPage.modalSizing == .automatic)
    }

    @Test func activeModeChangesTheSpaceReservedForLibraryContent() {
        let size = CGSize(width: 800, height: 600)
        let gallery = policy.evaluate(.init(availableSize: size, libraryMode: .gallery))
        let grid = policy.evaluate(.init(availableSize: size, libraryMode: .grid))

        #expect(gallery.detailPresentation == .sheet)
        #expect(grid.detailPresentation == .inspector)
    }
}
