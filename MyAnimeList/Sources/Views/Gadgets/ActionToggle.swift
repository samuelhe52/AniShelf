//
//  ActionToggle.swift
//  MyAnimeList
//
//  Created by Samuel He on 2025/5/17.
//

import SwiftUI

struct ActionToggle<ToggleLabel: View>: View {
    @State var isOn: Bool
    let sensoryFeedback: SensoryFeedback?
    @ViewBuilder let label: () -> ToggleLabel
    let on: () -> Void
    let off: () -> Void

    init(
        isOn: Bool = false,
        sensoryFeedback: SensoryFeedback? = .selection,
        on: @escaping () -> Void = {},
        off: @escaping () -> Void = {},
        @ViewBuilder label: @escaping () -> ToggleLabel
    ) {
        self._isOn = .init(initialValue: isOn)
        self.sensoryFeedback = sensoryFeedback
        self.on = on
        self.off = off
        self.label = label
    }

    var body: some View {
        Toggle(isOn: $isOn, label: label)
            .onAppear {
                guard isOn else { return }
                on()
            }
            .onChange(of: isOn) {
                if isOn {
                    on()
                } else {
                    off()
                }
            }
            .sensoryFeedback(trigger: isOn) { _, _ in
                sensoryFeedback
            }
    }
}
