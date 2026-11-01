//
//  MacLibrarySelectionTests.swift
//  AniShelf
//
//  Created by Claude Code on behalf of Samuel He on 2026/10/16.
//

#if os(macOS)
    import DataProvider
    import Testing

    @testable import MyAnimeList

    @MainActor
    struct MacLibrarySelectionTests {
        private let layout = (1...5).map { LibraryEntryIdentity(entryType: .movie, tmdbID: $0) }

        @Test func clicksReplaceToggleAndExtendFromTheAnchor() {
            let selection = MacLibrarySelection()

            selection.click(layout[1], .replace, layoutIDs: layout)
            selection.click(layout[3], .toggle, layoutIDs: layout)
            #expect(selection.ids == [layout[1], layout[3]])
            #expect(selection.anchor == layout[3])

            // ⇧-click spans from the last plain or ⌘-click, in either direction.
            selection.click(layout[0], .extend, layoutIDs: layout)
            #expect(selection.ids == Set(layout[0...3]))
            #expect(selection.anchor == layout[3])

            selection.click(layout[3], .toggle, layoutIDs: layout)
            #expect(selection.ids == Set(layout[0...2]))
        }

        @Test func extendWithoutAnAnchorSelectsOnlyTheClickedEntry() {
            let selection = MacLibrarySelection()

            selection.click(layout[2], .extend, layoutIDs: layout)

            #expect(selection.ids == [layout[2]])
            #expect(selection.single == layout[2])
        }

        @Test func arrowMovesStartAtTheFirstEntryAndStopAtEdges() {
            let selection = MacLibrarySelection()

            #expect(selection.move(by: 1, in: layout) == layout[0])
            #expect(selection.move(by: -1, in: layout) == nil)
            #expect(selection.ids == [layout[0]])

            // A batch collapses to one entry, moving from where the last click was.
            selection.click(layout[2], .replace, layoutIDs: layout)
            selection.click(layout[4], .extend, layoutIDs: layout)
            #expect(selection.move(by: 1, in: layout) == layout[3])
            #expect(selection.ids == [layout[3]])
        }

        @Test func pruningKeepsOnlyVisibleEntriesAndDropsAStaleAnchor() {
            let selection = MacLibrarySelection()
            selection.select([layout[0]])
            selection.click(layout[2], .toggle, layoutIDs: layout)

            selection.prune(keeping: [layout[0], layout[1]])

            #expect(selection.ids == [layout[0]])
            #expect(selection.anchor == layout[0])

            selection.prune(keeping: [])
            #expect(selection.isEmpty)
            #expect(selection.anchor == nil)
        }
    }
#endif
