//
//  MacWatchStatusPicker.swift
//  AniShelf
//
//  Created by OpenAI Codex on behalf of samuelhe52 on 2026/10/18.
//

#if os(macOS)
    import AppKit
    import DataProvider
    import SwiftUI

    /// Explicit native sizing avoids the SwiftUI segmented picker's initial horizontal drift.
    struct MacWatchStatusPicker: NSViewRepresentable {
        @Binding var selection: AnimeEntry.WatchStatus
        let isRewatching: Bool
        @Environment(\.isEnabled) private var isEnabled
        @Environment(\.locale) private var locale

        private static let statuses: [AnimeEntry.WatchStatus] = [.planToWatch, .watching, .watched]

        func makeCoordinator() -> Coordinator {
            Coordinator(selection: $selection)
        }

        func makeNSView(context: Context) -> NSSegmentedControl {
            let control = NSSegmentedControl()
            control.segmentCount = Self.statuses.count
            control.trackingMode = .selectOne
            control.segmentStyle = .rounded
            control.segmentDistribution = .fillEqually
            control.target = context.coordinator
            control.action = #selector(Coordinator.selectStatus(_:))
            return control
        }

        func updateNSView(_ control: NSSegmentedControl, context: Context) {
            context.coordinator.selection = $selection
            let labels = [
                EntryDetailL10n.planned, isRewatching ? EntryDetailL10n.rewatching : EntryDetailL10n.watching,
                EntryDetailL10n.watched
            ]
            for (index, label) in labels.enumerated() {
                let title = localized(label)
                if control.label(forSegment: index) != title {
                    control.setLabel(title, forSegment: index)
                }
            }
            control.selectedSegment = Self.statuses.firstIndex(of: selection) ?? -1
            control.isEnabled = isEnabled
            control.setAccessibilityLabel(localized(EntryDetailL10n.watchStatus))
        }

        func sizeThatFits(_ proposal: ProposedViewSize, nsView: NSSegmentedControl, context: Context) -> CGSize? {
            nsView.intrinsicContentSize
        }

        private func localized(_ resource: LocalizedStringResource) -> String {
            var resource = resource
            resource.locale = locale
            return String(localized: resource)
        }

        @MainActor
        final class Coordinator: NSObject {
            var selection: Binding<AnimeEntry.WatchStatus>

            init(selection: Binding<AnimeEntry.WatchStatus>) {
                self.selection = selection
            }

            @objc func selectStatus(_ sender: NSSegmentedControl) {
                guard MacWatchStatusPicker.statuses.indices.contains(sender.selectedSegment) else { return }
                selection.wrappedValue = MacWatchStatusPicker.statuses[sender.selectedSegment]
                // The parent may defer the change for a confirmation prompt.
                sender.selectedSegment = MacWatchStatusPicker.statuses.firstIndex(of: selection.wrappedValue) ?? -1
            }
        }
    }
#endif
