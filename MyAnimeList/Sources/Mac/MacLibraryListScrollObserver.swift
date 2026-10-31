//
//  MacLibraryListScrollObserver.swift
//  AniShelf
//
//  Created by Claude Code on behalf of Samuel He on 2026/10/31.
//

#if os(macOS)
    import AppKit
    import SwiftUI

    extension View {
        /// Reports the Mac List's visible rows and the user's scrolling from its AppKit table.
        ///
        /// SwiftUI's signals fail here (docs-ai 038): the List reports no user scroll phases, and
        /// rows scrolled out of view never report themselves hidden. The table is found from a
        /// background probe through public AppKit API; until it is found, nothing is reported.
        func macLibraryListScrollObserver(
            visibleRowsChanged: @escaping ([Int]) -> Void,
            userDidScroll: @escaping () -> Void
        ) -> some View {
            background {
                MacLibraryListScrollObserver(visibleRowsChanged: visibleRowsChanged, userDidScroll: userDidScroll)
                    .allowsHitTesting(false)
                    .accessibilityHidden(true)
            }
        }
    }

    fileprivate struct MacLibraryListScrollObserver: NSViewRepresentable {
        let visibleRowsChanged: ([Int]) -> Void
        let userDidScroll: () -> Void

        func makeCoordinator() -> Coordinator { Coordinator() }

        func makeNSView(context: Context) -> ProbeView {
            let view = ProbeView()
            view.coordinator = context.coordinator
            return view
        }

        func updateNSView(_ view: ProbeView, context: Context) {
            context.coordinator.visibleRowsChanged = visibleRowsChanged
            context.coordinator.userDidScroll = userDidScroll
            view.attachSoon()
        }

        static func dismantleNSView(_ view: ProbeView, coordinator: Coordinator) {
            coordinator.detach()
        }

        final class ProbeView: NSView {
            weak var coordinator: Coordinator?

            override func viewDidMoveToWindow() {
                super.viewDidMoveToWindow()
                attachSoon()
            }

            override func layout() {
                super.layout()
                attachSoon()
            }

            /// The table may not exist yet when the probe first appears, so try after this update.
            func attachSoon() {
                guard coordinator?.isAttached == false, window != nil else { return }
                DispatchQueue.main.async { [weak self] in
                    guard let self else { return }
                    self.coordinator?.attach(near: self)
                }
            }
        }

        @MainActor
        final class Coordinator {
            var visibleRowsChanged: ([Int]) -> Void = { _ in }
            var userDidScroll: () -> Void = {}
            private weak var scrollView: NSScrollView?
            private var boundsObserver: NSObjectProtocol?
            private var scrollMonitor: Any?
            private var lastRows: [Int]?

            var isAttached: Bool { scrollView != nil }

            func attach(near probe: NSView) {
                guard !isAttached, let scrollView = Self.tableScrollView(near: probe) else { return }
                self.scrollView = scrollView
                let clipView = scrollView.contentView
                clipView.postsBoundsChangedNotifications = true
                boundsObserver = NotificationCenter.default.addObserver(
                    forName: NSView.boundsDidChangeNotification,
                    object: clipView,
                    queue: .main
                ) { [weak self] _ in
                    MainActor.assumeIsolated { self?.reportVisibleRows() }
                }
                // Wheel and trackpad scrolling over this table count as the user's; a restore
                // or command moves the table without one.
                scrollMonitor = NSEvent.addLocalMonitorForEvents(matching: .scrollWheel) { [weak self] event in
                    MainActor.assumeIsolated {
                        if let self, let scrollView = self.scrollView, event.window === scrollView.window,
                            scrollView.bounds.contains(scrollView.convert(event.locationInWindow, from: nil))
                        {
                            self.userDidScroll()
                        }
                    }
                    return event
                }
                reportVisibleRows()
            }

            func detach() {
                if let boundsObserver { NotificationCenter.default.removeObserver(boundsObserver) }
                if let scrollMonitor { NSEvent.removeMonitor(scrollMonitor) }
                boundsObserver = nil
                scrollMonitor = nil
                scrollView = nil
            }

            /// Rows at least half inside the viewport, excluding what the toolbar covers.
            private func reportVisibleRows() {
                guard let scrollView, let table = scrollView.documentView as? NSTableView else { return }
                var viewport = scrollView.contentView.documentVisibleRect
                let insets = scrollView.contentInsets
                viewport.origin.y += insets.top
                viewport.size.height -= insets.top + insets.bottom
                let candidates = table.rows(in: viewport)
                let rows = (candidates.location..<(candidates.location + candidates.length)).filter { row in
                    let rect = table.rect(ofRow: row)
                    return rect.height > 0 && rect.intersection(viewport).height >= rect.height / 2
                }
                guard rows != lastRows else { return }
                lastRows = rows
                visibleRowsChanged(rows)
            }

            /// The scroll view whose document is a table and which overlaps the probe the most;
            /// the probe sits behind the List, so that is the List's own table.
            private static func tableScrollView(near probe: NSView) -> NSScrollView? {
                let probeFrame = probe.convert(probe.bounds, to: nil)
                var best: (view: NSScrollView, area: CGFloat)?
                var ancestor = probe.superview
                for _ in 0..<12 {
                    guard let current = ancestor else { break }
                    for scrollView in tableScrollViews(in: current) {
                        let overlap = scrollView.convert(scrollView.bounds, to: nil).intersection(probeFrame)
                        let area = overlap.isNull ? 0 : overlap.width * overlap.height
                        if area > (best?.area ?? 0) { best = (scrollView, area) }
                    }
                    if best != nil { break }
                    ancestor = current.superview
                }
                return best?.view
            }

            private static func tableScrollViews(in view: NSView) -> [NSScrollView] {
                if let scrollView = view as? NSScrollView, scrollView.documentView is NSTableView {
                    return [scrollView]
                }
                return view.subviews.flatMap(tableScrollViews(in:))
            }
        }
    }
#endif
