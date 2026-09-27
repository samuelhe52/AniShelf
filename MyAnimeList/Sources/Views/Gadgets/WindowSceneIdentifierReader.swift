//
//  WindowSceneIdentifierReader.swift
//  AniShelf
//
//  Created by Claude Code on behalf of Samuel He on 2026/9/27.
//

import SwiftUI
import UIKit

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
