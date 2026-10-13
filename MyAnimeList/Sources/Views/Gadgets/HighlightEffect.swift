//
//  HighlightEffect.swift
//  MyAnimeList
//
//  Created by Samuel He on 7/10/25.
//

import SwiftUI

struct HighlightEffectModifier: ViewModifier {
    var trigger: UUID?
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
            .task(id: trigger) {
                // Each trigger restarts the pulse from rest; a cancelled pulse leaves the
                // state to its successor, and clearing the trigger settles the row.
                let animation = Animation.interactiveSpring(duration: highlightDuration - 0.05)
                if isLit { withAnimation(animation) { isLit = false } }
                guard trigger != nil,
                    (try? await Task.sleep(for: .seconds(delay))) != nil
                else { return }
                withAnimation(animation) { isLit = true }
                guard (try? await Task.sleep(for: .seconds(highlightDuration))) != nil else { return }
                withAnimation(animation) { isLit = false }
            }
    }
}

extension View {
    func highlightEffect(
        trigger: UUID?,
        color: Color = .yellow,
        delay: TimeInterval = 0,
        duration: TimeInterval = 0.5
    ) -> some View {
        self.modifier(
            HighlightEffectModifier(
                trigger: trigger,
                highlightColor: color,
                delay: delay,
                highlightDuration: duration))
    }
}
