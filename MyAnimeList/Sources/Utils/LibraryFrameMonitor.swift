//
//  LibraryFrameMonitor.swift
//  AniShelf
//
//  Created by Claude Code on behalf of samuelhe52 on 2026/10/17.
//

#if (DEBUG || LIBRARY_FIXTURES) && os(iOS)
    import SwiftUI
    import UIKit

    /// Counts late main-thread frames in fixture launches, for the UI benchmarks; see docs-ai 026.
    ///
    /// The simulator records no system hitch metrics, so the benchmarks read these running totals
    /// instead. A display-link callback that arrives more than half a frame late means the main
    /// thread missed a frame; the lateness beyond one frame counts as hitch time. Render-server
    /// hitches are not visible here.
    @MainActor
    final class LibraryFrameMonitor: NSObject {
        static let shared = LibraryFrameMonitor()

        private(set) var frameCount = 0
        private(set) var hitchCount = 0
        private(set) var hitchTime: CFTimeInterval = 0
        private var link: CADisplayLink?
        private var lastTimestamp: CFTimeInterval?
        private var frameDuration: CFTimeInterval = 1.0 / 60

        func start() {
            guard link == nil else { return }
            let link = CADisplayLink(target: self, selector: #selector(frame(_:)))
            link.add(to: .main, forMode: .common)
            self.link = link
        }

        /// Cumulative totals; the benchmark metric takes differences between two reads.
        var summary: String {
            let now = CACurrentMediaTime()
            return "time=\(now);frames=\(frameCount);hitches=\(hitchCount);hitchTime=\(hitchTime)"
        }

        @objc private func frame(_ link: CADisplayLink) {
            defer {
                lastTimestamp = link.timestamp
                frameDuration = max(link.targetTimestamp - link.timestamp, 1.0 / 240)
            }
            frameCount += 1
            guard let lastTimestamp else { return }
            let delta = link.timestamp - lastTimestamp
            if delta > frameDuration * 1.5 {
                hitchCount += 1
                hitchTime += delta - frameDuration
            }
        }
    }

    /// An invisible accessibility element whose value is read only when a UI test queries it,
    /// so exposing the totals causes no SwiftUI updates.
    struct LibraryFrameStatsElement: UIViewRepresentable {
        func makeUIView(context: Context) -> FrameStatsView {
            LibraryFrameMonitor.shared.start()
            return FrameStatsView()
        }

        func updateUIView(_ uiView: FrameStatsView, context: Context) {}

        final class FrameStatsView: UIView {
            override init(frame: CGRect) {
                super.init(frame: frame)
                isUserInteractionEnabled = false
                isAccessibilityElement = true
                accessibilityIdentifier = "library-frame-stats"
                // Fully transparent views drop out of the accessibility tree.
                alpha = 0.02
            }

            required init?(coder: NSCoder) {
                fatalError("init(coder:) has not been implemented")
            }

            override var accessibilityValue: String? {
                get { MainActor.assumeIsolated { LibraryFrameMonitor.shared.summary } }
                set {}
            }
        }
    }
#endif
