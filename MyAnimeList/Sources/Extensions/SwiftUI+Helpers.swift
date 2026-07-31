//
//  SwiftUI+Helpers.swift
//  MyAnimeList
//
//  Created by Samuel He on 2025/5/11.
//

import SwiftUI

extension AnyTransition {
    static var opacityScale: AnyTransition { .opacity.combined(with: .scale) }
}

extension SensoryFeedback {
    static var lighterImpact: SensoryFeedback { .impact(weight: .light, intensity: 0.7) }
}

fileprivate struct PreferredNavigationBarScrollEdgeEffectModifier: ViewModifier {
    @AppStorage(.useSoftNavigationBarEdges) private var useSoftNavigationBarEdges = true

    func body(content: Content) -> some View {
        content.scrollEdgeEffectStyle(
            useSoftNavigationBarEdges ? .soft : .automatic,
            for: .all
        )
    }
}

extension View {
    func preferredNavigationBarScrollEdgeEffect() -> some View {
        modifier(PreferredNavigationBarScrollEdgeEffectModifier())
    }
}
