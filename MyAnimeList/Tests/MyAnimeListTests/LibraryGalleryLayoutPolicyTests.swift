//
//  LibraryGalleryLayoutPolicyTests.swift
//  AniShelf
//
//  Created by OpenAI Codex on behalf of Samuel He on 2026/7/14.
//

import SwiftUI
import Testing

@testable import MyAnimeList

struct LibraryGalleryLayoutPolicyTests {
    private let policy = LibraryGalleryLayoutPolicy()

    @Test func wideGalleryUsesHeightDerivedPosterWidthAndShowsNeighbors() {
        let arrangement = policy.arrangement(
            for: .init(
                availableSize: CGSize(width: 820, height: 560)
            )
        )

        guard case .shelf = arrangement else {
            Issue.record("Expected a Gallery shelf")
            return
        }
    }

    @Test func tallButNarrowGalleryRetainsSinglePageLayout() {
        let arrangement = policy.arrangement(
            for: .init(
                availableSize: CGSize(width: 430, height: 932)
            )
        )

        #expect(arrangement == .singlePage)
    }

    @Test func shortGalleryRetainsSinglePageLayout() {
        let arrangement = policy.arrangement(
            for: .init(
                availableSize: CGSize(width: 1_000, height: 390)
            )
        )

        #expect(arrangement == .singlePage)
    }

    @Test func accessibilityDynamicTypeRequiresMoreShelfCapacity() {
        let availableSize = CGSize(width: 820, height: 560)
        let standard = policy.arrangement(
            for: .init(
                availableSize: availableSize,
                dynamicTypeSize: .large
            )
        )
        let accessibility = policy.arrangement(
            for: .init(
                availableSize: availableSize,
                dynamicTypeSize: .accessibility2
            )
        )

        guard case .shelf = standard else {
            Issue.record("Expected the standard-size Gallery to use a shelf")
            return
        }
        #expect(accessibility == .singlePage)
    }
}
