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

fileprivate nonisolated struct LibraryViewTransitionModifier: ViewModifier, Animatable {
    var opacity: Double
    let scale: CGFloat
    var blurRadius: CGFloat
    let yOffset: CGFloat

    // Geometry animates separately; interpolate the values captured by visualEffect.
    var animatableData: AnimatablePair<CGFloat, Double> {
        get { AnimatablePair(blurRadius, opacity) }
        set {
            blurRadius = newValue.first
            opacity = newValue.second
        }
    }

    func body(content: Content) -> some View {
        content
            .modifier(LibraryPageGeometryEffect(scale: scale, yOffset: yOffset).ignoredByLayout())
            // Group before the visual effects so blur remains visible during insertion.
            // Applying blur/opacity directly to the scroll view caused its soft edge
            // to change strength when the transition finished.
            .compositingGroup()
            .visualEffect { effect, _ in
                effect
                    .blur(radius: blurRadius)
                    .opacity(opacity)
            }
    }
}

fileprivate struct LibraryPageGeometryEffect: GeometryEffect {
    var scale: CGFloat
    var yOffset: CGFloat

    var animatableData: AnimatablePair<CGFloat, CGFloat> {
        get { AnimatablePair(scale, yOffset) }
        set {
            scale = newValue.first
            yOffset = newValue.second
        }
    }

    func effectValue(size: CGSize) -> ProjectionTransform {
        // Scale about the center, then shift.
        let transform = CGAffineTransform(
            translationX: size.width * (1 - scale) / 2,
            y: size.height * (1 - scale) / 2 + yOffset
        )
        .scaledBy(x: scale, y: scale)
        return ProjectionTransform(transform)
    }
}
