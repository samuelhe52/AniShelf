//
//  LibraryProfileSettingsLayoutPolicyTests.swift
//  MyAnimeListTests
//
//  Created by OpenAI Codex on behalf of Samuel He on 2026/7/22.
//

import SwiftUI
import Testing

@testable import MyAnimeList

struct LibraryProfileSettingsLayoutPolicyTests {
    private let policy = LibraryProfileSettingsLayoutPolicy()

    @Test func regularWidthUsesWideGridAtStandardDynamicType() {
        #expect(
            policy.layout(horizontalSizeClass: .regular, dynamicTypeSize: .large) == .wideGrid
        )
    }

    @Test func compactOrAccessibilityLayoutUsesPhoneComposition() {
        #expect(
            policy.layout(horizontalSizeClass: .compact, dynamicTypeSize: .large) == .compactScroll
        )
        #expect(
            policy.layout(horizontalSizeClass: .regular, dynamicTypeSize: .accessibility1)
                == .compactScroll
        )
        #expect(
            policy.layout(horizontalSizeClass: nil, dynamicTypeSize: .large) == .compactScroll
        )
    }
}
