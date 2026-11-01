//
//  MacWatchStatusPickerTests.swift
//  AniShelf
//
//  Created by OpenAI Codex on behalf of Samuel He on 2026/10/18.
//

#if os(macOS)
    import AppKit
    import DataProvider
    import SwiftUI
    import Testing

    @testable import MyAnimeList

    @MainActor
    struct MacWatchStatusPickerTests {
        @Test func deferredStatusChangeKeepsTheModelSelectionVisible() {
            var requested: AnimeEntry.WatchStatus?
            let coordinator = MacWatchStatusPicker.Coordinator(
                selection: Binding(get: { .planToWatch }, set: { requested = $0 })
            )
            let control = NSSegmentedControl()
            control.segmentCount = 3
            control.selectedSegment = 1

            coordinator.selectStatus(control)

            #expect(requested == .watching)
            #expect(control.selectedSegment == 0)
        }

        @Test func reusedCoordinatorWritesOnlyToTheCurrentBinding() {
            var original: AnimeEntry.WatchStatus = .planToWatch
            var current: AnimeEntry.WatchStatus = .watching
            let coordinator = MacWatchStatusPicker.Coordinator(
                selection: Binding(get: { original }, set: { original = $0 })
            )
            coordinator.selection = Binding(get: { current }, set: { current = $0 })
            let control = NSSegmentedControl()
            control.segmentCount = 3
            control.selectedSegment = 2

            coordinator.selectStatus(control)

            #expect(original == .planToWatch)
            #expect(current == .watched)
            #expect(control.selectedSegment == 2)
        }
    }
#endif
