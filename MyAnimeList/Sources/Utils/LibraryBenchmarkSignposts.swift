//
//  LibraryBenchmarkSignposts.swift
//  AniShelf
//
//  Created by Claude Code on behalf of samuelhe52 on 2026/10/17.
//

import Foundation
import os

#if os(iOS)
    import QuartzCore
#endif

/// Signpost intervals the library benchmarks measure; see docs-ai 026.
///
/// Each interaction emits two intervals that begin together:
/// - `<Name>Commit` ends when the Core Animation transaction carrying the change commits. It is
///   the main-thread cost of the update and is not quantized to frames.
/// - `<Name>` ends at the first display-link frame after that commit, the first vsync at which
///   the change can be on screen. It is quantized to frames.
///
/// Compiled only into Debug and `LIBRARY_FIXTURES` builds, and enabled only for fixture
/// launches, so ordinary runs never create display links. Release builds keep the no-op API so
/// call sites need no conditional compilation.
@MainActor
enum LibraryBenchmarkSignposts {
    #if DEBUG || LIBRARY_FIXTURES
        static var isEnabled = false

        /// Matches the UI benchmarks' `XCTOSSignpostMetric` category.
        private static let signposter = OSSignposter(subsystem: .bundleIdentifier, category: "LibraryBenchmark")
        private static var pendingIntervals: Set<String> = []
    #endif

    /// The batch selection changed.
    static func selectionDidChange() {
        #if DEBUG || LIBRARY_FIXTURES
            measureUpdate("SelectionUpdate", commit: "SelectionUpdateCommit")
        #endif
    }

    /// The store's display list went stale; the next frame shows the recomputed list.
    static func displayDidInvalidate() {
        #if DEBUG || LIBRARY_FIXTURES
            measureUpdate("DisplayUpdate", commit: "DisplayUpdateCommit")
        #endif
    }

    /// A batch action started; the intervals cover the writes, the save, and the update.
    static func batchActionWillApply() {
        #if DEBUG || LIBRARY_FIXTURES
            measureUpdate("BatchAction", commit: "BatchActionCommit")
        #endif
    }

    #if DEBUG || LIBRARY_FIXTURES
        /// Begins both intervals unless the same interaction is already being measured, which
        /// coalesces repeated changes within one update.
        private static func measureUpdate(_ name: StaticString, commit commitName: StaticString) {
            let key = "\(name)"
            guard isEnabled, pendingIntervals.insert(key).inserted else { return }
            // Distinct IDs: interactions overlap (a batch action also invalidates the display
            // and ends selection), and the shared exclusive ID made XCTest drop intervals.
            let state = signposter.beginInterval(name, id: signposter.makeSignpostID())
            let commitState = signposter.beginInterval(commitName, id: signposter.makeSignpostID())
            afterCommit {
                signposter.endInterval(commitName, commitState)
                atNextFrame {
                    signposter.endInterval(name, state)
                    pendingIntervals.remove(key)
                }
            }
        }

        /// Core Animation commits the run loop's implicit transaction from a before-waiting
        /// observer at this order; SwiftUI's view updates run before it.
        private static let coreAnimationCommitOrder: CFIndex = 2_000_000

        /// Runs `action` once, right after this run-loop pass commits its transaction.
        private static func afterCommit(_ action: @escaping @MainActor () -> Void) {
            let observer = CFRunLoopObserverCreateWithHandler(
                nil,
                CFRunLoopActivity.beforeWaiting.rawValue,
                false,
                coreAnimationCommitOrder + 1
            ) { _, _ in
                MainActor.assumeIsolated(action)
            }
            CFRunLoopAddObserver(CFRunLoopGetMain(), observer, .commonModes)
        }

        private static func atNextFrame(_ action: @escaping @MainActor () -> Void) {
            #if os(iOS)
                NextFrameCallback.schedule(action)
            #else
                action()
            #endif
        }
    #endif
}

#if (DEBUG || LIBRARY_FIXTURES) && os(iOS)
    @MainActor
    fileprivate final class NextFrameCallback: NSObject {
        private var action: (@MainActor () -> Void)?
        private var link: CADisplayLink?

        /// The display link retains the callback until it fires once.
        static func schedule(_ action: @escaping @MainActor () -> Void) {
            let callback = NextFrameCallback()
            callback.action = action
            let link = CADisplayLink(target: callback, selector: #selector(fire))
            callback.link = link
            link.add(to: .main, forMode: .common)
        }

        @objc private func fire() {
            // Invalidating releases this callback, so take what it needs first.
            let action = self.action
            self.action = nil
            let link = self.link
            self.link = nil
            link?.invalidate()
            action?()
        }
    }
#endif
