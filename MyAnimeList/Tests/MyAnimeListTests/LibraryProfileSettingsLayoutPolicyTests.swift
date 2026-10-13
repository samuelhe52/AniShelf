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

    @Test func regularWidthUsesTwoHubColumnsAtStandardDynamicType() {
        #expect(
            policy.hubColumns(horizontalSizeClass: .regular, dynamicTypeSize: .large) == .double
        )
    }

    @Test func compactOrAccessibilityLayoutUsesOneHubColumn() {
        #expect(
            policy.hubColumns(horizontalSizeClass: .compact, dynamicTypeSize: .large) == .single
        )
        #expect(
            policy.hubColumns(horizontalSizeClass: .regular, dynamicTypeSize: .accessibility1)
                == .single
        )
        #expect(
            policy.hubColumns(horizontalSizeClass: nil, dynamicTypeSize: .large) == .single
        )
    }
}
