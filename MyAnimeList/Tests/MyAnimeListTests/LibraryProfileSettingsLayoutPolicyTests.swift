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

    @Test func regularWidthUsesWorkspaceAtStandardDynamicType() {
        #expect(
            policy.layout(horizontalSizeClass: .regular, dynamicTypeSize: .large) == .workspace
        )
    }

    @Test func compactOrAccessibilityLayoutUsesHub() {
        #expect(
            policy.layout(horizontalSizeClass: .compact, dynamicTypeSize: .large) == .hub
        )
        #expect(
            policy.layout(horizontalSizeClass: .regular, dynamicTypeSize: .accessibility1)
                == .hub
        )
        #expect(
            policy.layout(horizontalSizeClass: nil, dynamicTypeSize: .large) == .hub
        )
    }
}
