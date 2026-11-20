//
//  AniShelfScreenSaverView.swift
//  AniShelf
//
//  Created by OpenAI Codex on behalf of Samuel He on 2026/11/20.
//

import AppKit
import ScreenSaver
import ScreenSaverKit

@objc(AniShelfScreenSaverView)
final class AniShelfScreenSaverView: ScreenSaverView {
    private let renderer = ScreenSaverRenderer { notice in
        let bundle = Bundle(for: AniShelfScreenSaverView.self)
        switch notice {
        case .empty:
            return String(localized: "Set up the screen saver in AniShelf.", bundle: bundle)
        case .requiresUpdate:
            return String(localized: "Update the screen saver from AniShelf.", bundle: bundle)
        }
    }
    private var stopObserver: NSObjectProtocol?
    private var activation: UUID?

    override init?(frame: NSRect, isPreview: Bool) {
        super.init(frame: frame, isPreview: isPreview)
        configureView()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        configureView()
    }

    isolated deinit {
        if let stopObserver { DistributedNotificationCenter.default().removeObserver(stopObserver) }
    }

    override func startAnimation() {
        endSession()
        super.startAnimation()
        // The host is sandboxed. Look up the login user's home explicitly.
        guard let home = FileManager.default.homeDirectory(forUser: NSUserName()) else { return }
        let activation = UUID()
        self.activation = activation
        stopObserver = DistributedNotificationCenter.default().addObserver(
            forName: Notification.Name("com.apple.screensaver.willstop"), object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self, self.activation == activation else { return }
                self.endSession()
            }
        }
        updateViewport()
        renderer.start(in: ScreenSaverSnapshotReader.snapshotDirectory(in: home))
    }

    override func stopAnimation() {
        endSession()
        super.stopAnimation()
    }

    override func animateOneFrame() {}

    override func layout() {
        super.layout()
        updateViewport()
    }

    override func viewDidChangeBackingProperties() {
        super.viewDidChangeBackingProperties()
        updateViewport()
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        if window == nil {
            endSession()
        } else {
            updateViewport()
        }
    }

    private func configureView() {
        layer = renderer.layer
        wantsLayer = true
        animationTimeInterval = 1
        updateViewport()
    }

    private func updateViewport() {
        renderer.resize(to: bounds.size, scale: window?.backingScaleFactor ?? 1)
    }

    private func endSession() {
        activation = nil
        if let stopObserver {
            DistributedNotificationCenter.default().removeObserver(stopObserver)
            self.stopObserver = nil
        }
        renderer.stop()
    }
}
