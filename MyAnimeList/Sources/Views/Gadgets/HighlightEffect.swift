//
//  HighlightEffect.swift
//  MyAnimeList
//
//  Created by Samuel He on 7/10/25.
//

import SwiftUI

struct HighlightEffectModifier: ViewModifier {
    @Binding var showHighlight: Bool
    var highlightColor: Color
    var delay: TimeInterval
    var highlightDuration: TimeInterval

    // Rendered apart from the request so a lazily created row that appears while the
    // request is already active still animates in from rest instead of popping in lit.
    @State private var isLit = false

    func body(content: Content) -> some View {
        content
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .strokeBorder(highlightColor, lineWidth: 3)
                    .fill(highlightColor.secondary.opacity(0.5))
                    .opacity(isLit ? 0.8 : 0)
            )
            .scaleEffect(isLit ? 1.05 : 1)
            .animation(
                .interactiveSpring(duration: highlightDuration - 0.05).delay(delay),
                value: isLit)
            .task(id: showHighlight) {
                isLit = showHighlight
                guard showHighlight,
                    (try? await Task.sleep(for: .seconds(highlightDuration))) != nil
                else { return }
                showHighlight = false
            }
    }
}

extension View {
    func highlightEffect(
        showHighlight: Binding<Bool>,
        color: Color = .yellow,
        delay: TimeInterval = 0,
        duration: TimeInterval = 0.5
    ) -> some View {
        self.modifier(
            HighlightEffectModifier(
                showHighlight: showHighlight,
                highlightColor: color,
                delay: delay,
                highlightDuration: duration))
    }
}
