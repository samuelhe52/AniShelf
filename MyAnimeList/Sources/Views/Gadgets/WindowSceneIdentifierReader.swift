//
//  WindowSceneIdentifierReader.swift
//  AniShelf
//
//  Created by Claude Code on behalf of Samuel He on 2026/9/27.
//

import SwiftUI

#if os(macOS)
    import AppKit
#else
    import UIKit
#endif

extension EnvironmentValues {
    /// Persistent identifier of the UIKit scene hosting this view hierarchy, or `nil` until known.
    ///
    /// Menus and sheets inherit it, so imperative UIKit presentation can target the invoking window.
    @Entry var windowSceneIdentifier: String? = nil
}

extension View {
    /// Resolves the hosting scene once and publishes it as `\.windowSceneIdentifier` to descendants.
    func providesWindowSceneIdentifier() -> some View {
        modifier(WindowSceneIdentifierProvider())
    }

    /// Runs `action` when a window other than the one with `identifier` closes.
    ///
    /// `action` runs in a new main-actor task after the notification, which gives the closing
    /// window's teardown a chance to progress but does not guarantee that it has finished.
    func onOtherWindowSceneClosed(
        than identifier: String?,
        perform action: @escaping @MainActor () -> Void
    ) -> some View {
        #if os(macOS)
            onReceive(NotificationCenter.default.publisher(for: NSWindow.willCloseNotification)) { notification in
                let closedIdentifier = (notification.object as? NSWindow)?.sceneIdentifier
                guard closedIdentifier != identifier else { return }
                Task { @MainActor in action() }
            }
        #else
            onReceive(NotificationCenter.default.publisher(for: UIScene.didDisconnectNotification)) { notification in
                // The disconnecting window still receives this before it is purged; only survivors act.
                let disconnectedIdentifier = (notification.object as? UIScene)?.session.persistentIdentifier
                guard disconnectedIdentifier != identifier else { return }
                // Deferring lets the disconnected scene leave `connectedScenes` first.
                Task { @MainActor in action() }
            }
        #endif
    }
}

@MainActor
enum WindowScenes {
    /// Whether the window with `identifier` may still claim an airing-reminder route: on the Mac,
    /// a visible window; on iOS, a scene still in `connectedScenes`.
    static func canReceiveRoute(_ identifier: String) -> Bool {
        #if os(macOS)
            NSApplication.shared.windows.contains { $0.sceneIdentifier == identifier && $0.isVisible }
        #else
            UIApplication.shared.connectedScenes.contains {
                $0.session.persistentIdentifier == identifier
            }
        #endif
    }
}

fileprivate struct WindowSceneIdentifierProvider: ViewModifier {
    @State private var identifier: String?

    func body(content: Content) -> some View {
        content
            .environment(\.windowSceneIdentifier, identifier)
            .background {
                WindowSceneIdentifierReader(identifier: $identifier)
                    .frame(width: 0, height: 0)
                    .accessibilityHidden(true)
            }
    }
}

#if os(macOS)
    extension NSWindow {
        /// Stable for the window's lifetime and unique among live windows. Unlike
        /// `windowNumber`, it is valid before the window has a window device.
        var sceneIdentifier: String {
            String(UInt(bitPattern: ObjectIdentifier(self).hashValue), radix: 16)
        }
    }

    fileprivate struct WindowSceneIdentifierReader: NSViewRepresentable {
        @Binding var identifier: String?

        func makeNSView(context: Context) -> ProbeView {
            let view = ProbeView()
            view.onWindowChange = { identifier = $0 }
            return view
        }

        func updateNSView(_ view: ProbeView, context: Context) {
            view.onWindowChange = { identifier = $0 }
        }

        final class ProbeView: NSView {
            var onWindowChange: ((String?) -> Void)?
            override func viewDidMoveToWindow() {
                super.viewDidMoveToWindow()
                let identifier = window?.sceneIdentifier
                Task { @MainActor [weak self] in self?.onWindowChange?(identifier) }
            }
        }
    }
#else
    fileprivate struct WindowSceneIdentifierReader: UIViewRepresentable {
        @Binding var identifier: String?

        func makeUIView(context: Context) -> ProbeView {
            let view = ProbeView()
            view.isUserInteractionEnabled = false
            view.onSceneIdentifierChange = report
            return view
        }

        func updateUIView(_ uiView: ProbeView, context: Context) {
            uiView.onSceneIdentifierChange = report
        }

        private func report(_ newIdentifier: String?) {
            guard identifier != newIdentifier else { return }
            identifier = newIdentifier
        }

        final class ProbeView: UIView {
            var onSceneIdentifierChange: ((String?) -> Void)?

            override func didMoveToWindow() {
                super.didMoveToWindow()
                let sceneIdentifier = window?.windowScene?.session.persistentIdentifier
                // Leave UIKit's hierarchy callback before mutating SwiftUI state.
                Task { @MainActor [weak self] in
                    self?.onSceneIdentifierChange?(sceneIdentifier)
                }
            }
        }
    }

#endif
