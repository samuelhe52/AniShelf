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
    /// Resolves the hosting window, registers it with `AppWindowCoordinator` in `role`, and
    /// publishes its identifier as `\.windowSceneIdentifier` to descendants.
    func providesWindowSceneIdentifier(role: AppWindowCoordinator.Role) -> some View {
        modifier(WindowSceneIdentifierProvider(role: role))
    }
}

@MainActor
enum WindowScenes {
    /// Whether the window with `identifier` may still claim an airing-reminder route.
    ///
    /// On the Mac, a window registered with the coordinator, visible or not, so a hidden app or
    /// minimized window still opens the entry; a closing window unregisters first. On iOS, a
    /// scene still in `connectedScenes`, which knows a notification's target scene before its
    /// views register.
    static func canReceiveRoute(_ identifier: String) -> Bool {
        #if os(macOS)
            AppWindowCoordinator.shared.isRegistered(identifier)
        #else
            UIApplication.shared.connectedScenes.contains {
                $0.session.persistentIdentifier == identifier
            }
        #endif
    }
}

/// A resolved hosting window: its identifier and whether it is active now.
fileprivate struct ResolvedWindow: Equatable {
    var identifier: String
    var isActive: Bool
}

fileprivate struct WindowSceneIdentifierProvider: ViewModifier {
    let role: AppWindowCoordinator.Role
    @State private var identifier: String?

    func body(content: Content) -> some View {
        content
            .environment(\.windowSceneIdentifier, identifier)
            .background {
                WindowSceneIdentifierReader(role: role) { window in
                    guard let window else { return }
                    AppWindowCoordinator.shared.register(window.identifier, role: role, isActive: window.isActive)
                    if identifier != window.identifier { identifier = window.identifier }
                }
                .frame(width: 0, height: 0)
                .accessibilityHidden(true)
            }
    }
}

#if os(macOS)
    @MainActor fileprivate var sceneIdentifierKey: UInt8 = 0
    @MainActor fileprivate var appWindowRoleKey: UInt8 = 0

    extension NSWindow {
        /// A UUID assigned on first use: stable for the window's lifetime and never reused by a
        /// later window, unlike an address-derived value.
        ///
        /// Valid before the window has a window device.
        var sceneIdentifier: String {
            if let identifier = objc_getAssociatedObject(self, &sceneIdentifierKey) as? String {
                return identifier
            }
            let identifier = UUID().uuidString
            objc_setAssociatedObject(self, &sceneIdentifierKey, identifier, .OBJC_ASSOCIATION_COPY_NONATOMIC)
            return identifier
        }

        /// The role the window registered with, so the coordinator can re-register a single
        /// window (Settings, Support) that SwiftUI reopens in the same NSWindow.
        var appWindowRole: AppWindowCoordinator.Role? {
            get { objc_getAssociatedObject(self, &appWindowRoleKey) as? AppWindowCoordinator.Role }
            set { objc_setAssociatedObject(self, &appWindowRoleKey, newValue, .OBJC_ASSOCIATION_RETAIN_NONATOMIC) }
        }
    }

    fileprivate struct WindowSceneIdentifierReader: NSViewRepresentable {
        let role: AppWindowCoordinator.Role
        let onResolve: (ResolvedWindow?) -> Void

        func makeNSView(context: Context) -> ProbeView {
            let view = ProbeView()
            view.role = role
            view.onResolve = onResolve
            return view
        }

        func updateNSView(_ view: ProbeView, context: Context) {
            view.role = role
            view.onResolve = onResolve
        }

        final class ProbeView: NSView {
            var role: AppWindowCoordinator.Role = .auxiliary
            var onResolve: ((ResolvedWindow?) -> Void)?
            override func viewDidMoveToWindow() {
                super.viewDidMoveToWindow()
                let resolved = window.map { window in
                    window.appWindowRole = role
                    return ResolvedWindow(
                        identifier: window.sceneIdentifier,
                        isActive: window.isKeyWindow || window.attachedSheet?.isKeyWindow == true
                    )
                }
                // Leave AppKit's hierarchy callback before mutating SwiftUI state.
                Task { @MainActor [weak self] in self?.onResolve?(resolved) }
            }
        }
    }
#else
    fileprivate struct WindowSceneIdentifierReader: UIViewRepresentable {
        let role: AppWindowCoordinator.Role
        let onResolve: (ResolvedWindow?) -> Void

        func makeUIView(context: Context) -> ProbeView {
            let view = ProbeView()
            view.isUserInteractionEnabled = false
            view.onResolve = onResolve
            return view
        }

        func updateUIView(_ uiView: ProbeView, context: Context) {
            uiView.onResolve = onResolve
        }

        final class ProbeView: UIView {
            var onResolve: ((ResolvedWindow?) -> Void)?

            override func didMoveToWindow() {
                super.didMoveToWindow()
                let resolved = window?.windowScene.map { scene in
                    ResolvedWindow(
                        identifier: scene.session.persistentIdentifier,
                        isActive: scene.activationState == .foregroundActive
                    )
                }
                // Leave UIKit's hierarchy callback before mutating SwiftUI state.
                Task { @MainActor [weak self] in
                    self?.onResolve?(resolved)
                }
            }
        }
    }

#endif
