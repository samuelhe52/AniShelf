//
//  LibraryScrollBookmark.swift
//  AniShelf
//
//  Created by Claude Code on behalf of Samuel He on 2026/10/31.
//

import DataProvider
import SwiftUI

/// The entry at the top of what a window's library shows, so a view-style switch lands where the
/// user was (docs-ai 038).
///
/// Only scrolling records it; taps, selection, and context menus never do. It lives in memory for
/// the window's lifetime and is not observable, so recording never re-renders a view.
@MainActor
final class LibraryScrollBookmark {
    private(set) var entryID: LibraryEntryIdentity?
    /// The display order when `entryID` was set, for finding a neighbor once it is gone.
    private var order: [LibraryEntryIdentity] = []
    /// Set while a restore, a style switch, or a scroll command settles. Observations then keep
    /// the bookmark, so layout alone, such as a restore that cannot top-align its entry, never
    /// moves it; the user's next scroll clears it.
    private(set) var isSettling = false

    /// Records what scrolling shows on top, unless a restore or command is settling.
    func record(_ id: LibraryEntryIdentity?, order: [LibraryEntryIdentity]) {
        guard !isSettling, let id else { return }
        entryID = id
        self.order = order
    }

    /// Sets the bookmark to where a scroll command goes, and holds it there until the user scrolls.
    func settle(on id: LibraryEntryIdentity?, order: [LibraryEntryIdentity]) {
        if let id {
            entryID = id
            self.order = order
        }
        isSettling = true
    }

    /// Holds the bookmark as it is, as a style switch or a reflow does.
    func freeze() {
        isSettling = true
    }

    func userDidScroll() {
        isSettling = false
    }

    /// The entry to restore: the bookmark when `ids` still shows it, otherwise its nearest
    /// surviving neighbor.
    func target(in ids: [LibraryEntryIdentity]) -> LibraryEntryIdentity? {
        guard let entryID else { return nil }
        if ids.contains(entryID) { return entryID }
        return Self.nearest(to: entryID, in: order, surviving: ids)
    }

    /// The entry closest to `id` in `previous` that `current` still shows, searching outward and
    /// preferring the one after it, which takes a removed entry's place.
    static func nearest(
        to id: LibraryEntryIdentity,
        in previous: [LibraryEntryIdentity],
        surviving current: [LibraryEntryIdentity]
    ) -> LibraryEntryIdentity? {
        guard let index = previous.firstIndex(of: id) else { return current.first }
        let shown = Set(current)
        for distance in 1..<max(previous.count, 1) {
            let after = index + distance
            if after < previous.endIndex, shown.contains(previous[after]) { return previous[after] }
            let before = index - distance
            if before >= 0, shown.contains(previous[before]) { return previous[before] }
            if after >= previous.endIndex, before < 0 { break }
        }
        return nil
    }
}

/// The visible entries of one List or Grid page.
///
/// Each page owns its tracker, so an outgoing page's callbacks never reach the incoming one.
@MainActor
final class LibraryVisibleEntryTracker {
    private(set) var order: [LibraryEntryIdentity] = []
    private var indices: [LibraryEntryIdentity: Int] = [:]
    private var visible: Set<LibraryEntryIdentity> = []
    /// The Mac List's visible rows, remapped to entries whenever the order changes.
    private var visibleRows: [Int]?

    func updateOrder(_ ids: [LibraryEntryIdentity]) {
        guard ids != order else { return }
        order = ids
        indices = Dictionary(ids.enumerated().map { ($0.element, $0.offset) }, uniquingKeysWith: { first, _ in first })
        if let visibleRows {
            visible = Set(entries(atRows: visibleRows))
        } else {
            visible.formIntersection(indices.keys)
        }
    }

    func isVisible(_ id: LibraryEntryIdentity) -> Bool {
        visible.contains(id)
    }

    /// One row crossed the visibility threshold, as a List reports it.
    func setVisible(_ id: LibraryEntryIdentity, _ isVisible: Bool, recordingInto bookmark: LibraryScrollBookmark) {
        if isVisible {
            visible.insert(id)
        } else {
            visible.remove(id)
        }
        bookmark.record(first, order: order)
    }

    /// The visible set changed, as a scroll-target layout reports it.
    func setVisible(_ ids: [LibraryEntryIdentity], recordingInto bookmark: LibraryScrollBookmark) {
        visible = Set(ids)
        bookmark.record(first, order: order)
    }

    /// The visible rows by display position, as the Mac List's table reports them.
    func setVisibleRows(_ rows: [Int], recordingInto bookmark: LibraryScrollBookmark) {
        visibleRows = rows
        setVisible(entries(atRows: rows), recordingInto: bookmark)
    }

    private func entries(atRows rows: [Int]) -> [LibraryEntryIdentity] {
        rows.compactMap { order.indices.contains($0) ? order[$0] : nil }
    }

    private var first: LibraryEntryIdentity? {
        visible.min { indices[$0, default: .max] < indices[$1, default: .max] }
    }
}

/// What moves a page's scroll position other than the user: an explicit request, or a change to
/// what the window shows or how it orders it.
struct LibraryScrollInputs: Equatable {
    var definition: LibraryBrowseScope.DisplayDefinition
    /// The Mac's toolbar Find, which narrows the window's scope further.
    var findQuery = ""
    var request: LibraryScrollRequest?
}

extension View {
    /// Restores, follows, and moves a vertical List or Grid page by entry (docs-ai 038).
    ///
    /// The page reports visibility to `tracker` itself, since a List and a lazy grid observe it
    /// differently.
    func libraryScrollBookmark(
        _ bookmark: LibraryScrollBookmark,
        tracker: LibraryVisibleEntryTracker,
        displayIDs: [LibraryEntryIdentity],
        inputs: LibraryScrollInputs,
        proxy: ScrollViewProxy
    ) -> some View {
        modifier(
            LibraryScrollBookmarkModifier(
                bookmark: bookmark,
                tracker: tracker,
                displayIDs: displayIDs,
                inputs: inputs,
                proxy: proxy
            )
        )
    }
}

fileprivate struct LibraryScrollBookmarkModifier: ViewModifier {
    let bookmark: LibraryScrollBookmark
    let tracker: LibraryVisibleEntryTracker
    let displayIDs: [LibraryEntryIdentity]
    let inputs: LibraryScrollInputs
    let proxy: ScrollViewProxy

    func body(content: Content) -> some View {
        content
            .onChange(of: displayIDs, initial: true) { tracker.updateOrder(displayIDs) }
            .onAppear {
                guard let target = bookmark.target(in: displayIDs) else { return }
                bookmark.settle(on: target, order: displayIDs)
                proxy.scrollTo(target, anchor: .top)
            }
            // One handler for both, so a jump that also leaves a category or clears Find scrolls
            // to its entry instead of to the top.
            .onChange(of: inputs) { old, new in
                if new.request != old.request {
                    guard let entryID = new.request?.entryID, !tracker.isVisible(entryID) else { return }
                    bookmark.settle(on: entryID, order: displayIDs)
                    withAnimation(.bouncy) { proxy.scrollTo(entryID) }
                } else if let first = displayIDs.first {
                    bookmark.settle(on: first, order: displayIDs)
                    proxy.scrollTo(first, anchor: .top)
                }
            }
            .onScrollPhaseChange { _, phase in
                if phase.isUserScroll { bookmark.userDidScroll() }
            }
    }
}

extension ScrollPhase {
    /// A scroll the user drives; programmatic scrolls report `.animating`.
    var isUserScroll: Bool {
        self == .interacting || self == .tracking || self == .decelerating
    }
}
