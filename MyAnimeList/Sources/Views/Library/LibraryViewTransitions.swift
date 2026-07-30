//
//  LibraryViewTransitions.swift
//  AniShelf
//
//  Created by OpenAI Codex on behalf of Samuel He on 2026/7/25.
//

import SwiftUI

enum LibraryViewTransitions {
    static func libraryViewStyleAnimation() -> Animation {
        .smooth(duration: 0.34, extraBounce: 0.12)
    }

    static func selectionModeAnimation() -> Animation {
        .smooth(duration: 0.26, extraBounce: 0.06)
    }

    static func libraryViewTransition() -> AnyTransition {
        .asymmetric(
            insertion: .modifier(
                active: LibraryViewTransitionModifier(
                    opacity: 0,
                    scale: 0.975,
                    blurRadius: 8,
                    yOffset: 14
                ),
                identity: LibraryViewTransitionModifier(
                    opacity: 1,
                    scale: 1,
                    blurRadius: 0,
                    yOffset: 0
                )
            ),
            removal: .modifier(
                active: LibraryViewTransitionModifier(
                    opacity: 0,
                    scale: 1.018,
                    blurRadius: 5,
                    yOffset: -10
                ),
                identity: LibraryViewTransitionModifier(
                    opacity: 1,
                    scale: 1,
                    blurRadius: 0,
                    yOffset: 0
                )
            )
        )
    }

    static func profileSettingsAnimation() -> Animation {
        .smooth(duration: 0.45, extraBounce: 0)
    }

    static func profileSettingsTransition() -> AnyTransition {
        .asymmetric(
            insertion: .modifier(
                active: LibraryProfileSettingsBlendModifier(
                    opacity: 0,
                    blurRadius: 22
                ),
                identity: LibraryProfileSettingsBlendModifier(
                    opacity: 1,
                    blurRadius: 0
                )
            ),
            removal: .modifier(
                active: LibraryProfileSettingsBlendModifier(
                    opacity: 0,
                    blurRadius: 14
                ),
                identity: LibraryProfileSettingsBlendModifier(
                    opacity: 1,
                    blurRadius: 0
                )
            )
        )
    }
}

fileprivate struct LibraryProfileSettingsBlendModifier: ViewModifier {
    let opacity: Double
    let blurRadius: CGFloat

    func body(content: Content) -> some View {
        content
            .blur(radius: blurRadius)
            .opacity(opacity)
            .compositingGroup()
    }
}

fileprivate struct LibraryViewTransitionModifier: ViewModifier {
    let opacity: Double
    let scale: CGFloat
    let blurRadius: CGFloat
    let yOffset: CGFloat

    func body(content: Content) -> some View {
        content
            .scaleEffect(scale)
            .offset(y: yOffset)
            .blur(radius: blurRadius)
            .opacity(opacity)
            .compositingGroup()
    }
}
