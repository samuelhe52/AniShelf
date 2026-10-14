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
