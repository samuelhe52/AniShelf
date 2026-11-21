//
//  ScreenSaverDurationSlider.swift
//  AniShelf
//
//  Created by OpenAI Codex on behalf of Samuel He on 2026/11/21.
//

import SwiftUI

public struct ScreenSaverDurationSlider: View {
    public enum Timing {
        case interval
        case flipDelay
        case timelineHold

        fileprivate var presets: [TimeInterval] {
            typealias Settings = ScreenSaverManifest.Settings
            return switch self {
            case .interval: Settings.intervalPresets
            case .flipDelay: Settings.flipDelayPresets
            case .timelineHold: Settings.timelineHoldPresets
            }
        }
    }

    private let title: LocalizedStringKey
    @Binding private var value: TimeInterval
    private let timing: Timing
    private let controlWidth: CGFloat?

    /// `value` must be one of the presets for `timing`.
    public init(
        _ title: LocalizedStringKey, value: Binding<TimeInterval>, timing: Timing, controlWidth: CGFloat? = nil
    ) {
        self.title = title
        _value = value
        self.timing = timing
        self.controlWidth = controlWidth
    }

    public var body: some View {
        let presets = timing.presets
        let duration = durationText(value)
        let selection = Binding(
            get: { Double(presets.firstIndex(of: value)!) },
            set: { value = presets[Int($0.rounded())] }
        )
        return LabeledContent(title) {
            HStack(spacing: 8) {
                Slider(value: selection, in: 0...Double(presets.count - 1), step: 1) { Text(title) }
                    .labelsHidden()
                    .accessibilityValue(duration)
                ZStack(alignment: .trailing) {
                    // Keep the track width stable when crossing from one digit count to another.
                    durationText(presets[presets.count - 1]).hidden()
                    duration
                }
                .fixedSize()
                .monospacedDigit()
                .accessibilityHidden(true)
            }
            .frame(width: controlWidth)
        }
    }

    private func durationText(_ seconds: TimeInterval) -> Text {
        Text(
            Measurement(value: seconds, unit: UnitDuration.seconds),
            format: .measurement(width: .abbreviated, usage: .asProvided)
        )
    }
}
