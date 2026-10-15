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
    var hold: TimeInterval

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
                if isLit { withAnimation(.smooth(duration: 0.4)) { isLit = false } }
                guard trigger != nil,
                    (try? await Task.sleep(for: .seconds(delay))) != nil
                else { return }
                withAnimation(.smooth(duration: 0.25)) { isLit = true }
                guard (try? await Task.sleep(for: .seconds(0.25 + hold))) != nil else { return }
                withAnimation(.smooth(duration: 0.4)) { isLit = false }
            }
    }
}

extension View {
    func highlightEffect(
        trigger: UUID?,
        color: Color = .yellow,
        // Lets the jump scroll settle so the pulse does not compete with its bounce.
        delay: TimeInterval = 0.4,
        hold: TimeInterval = 0.25
    ) -> some View {
        self.modifier(
            HighlightEffectModifier(
                trigger: trigger,
                highlightColor: color,
                delay: delay,
                hold: hold))
    }
}
