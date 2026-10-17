//
//  GlobalToastsModifier.swift
//  MyAnimeList
//
//  Created by Samuel He on 2025/4/26.
//

import AlertToast
import SwiftUI

struct GlobalToastsModifier: ViewModifier {
    var center: ToastCenter

    @Environment(\.windowSceneIdentifier) private var windowSceneIdentifier
    #if os(macOS)
        @Environment(\.appearsActive) private var appearsActive
    #endif

    func body(content: Content) -> some View {
        @Bindable var center = center
        content
            .toast(
                isPresenting: shown($center.copied), duration: 1.5, offsetY: 20,
                alert: {
                    AlertToast(
                        displayMode: .hud,
                        type: .systemImage("checkmark.circle", .green),
                        titleResource: "Copied!")
                }
            )
            .sensoryFeedback(.lighterImpact, trigger: center.copied) { !$0 && $1 }
            .toast(
                isPresenting: shown($center.pasted), duration: 1.5, offsetY: 20,
                alert: {
                    AlertToast(
                        displayMode: .hud,
                        type: .systemImage("checkmark.circle", .green),
                        titleResource: "Pasted!")
                }
            )
            .sensoryFeedback(.lighterImpact, trigger: center.pasted) { !$0 && $1 }
            .toast(
                isPresenting: shown($center.regularCompleted), offsetY: 20,
                alert: {
                    AlertToast(
                        displayMode: .hud,
                        type: .complete(.green),
                        titleResource: "Done")
                }
            )
            .sensoryFeedback(.success, trigger: center.regularCompleted) { !$0 && $1 }
            .toast(
                isPresenting: shown($center.regularFailed), offsetY: 20,
                alert: {
                    AlertToast(
                        displayMode: .hud,
                        type: .error(.red),
                        titleResource: "An error occurred")
                }
            )
            .sensoryFeedback(.error, trigger: center.regularFailed) { !$0 && $1 }
            .toast(
                item: shown($center.completionState), offsetY: 20,
                alert: { completion in
                    var alertType: AlertToast.AlertType = .regular
                    if let state = completion?.state {
                        switch state {
                        case .completed: alertType = .complete(.green)
                        case .failed: alertType = .error(.red)
                        case .partialComplete: alertType = .regular
                        }
                    }
                    return AlertToast(
                        displayMode: .hud,
                        type: alertType,
                        titleResource: center.completionState?.messageResource)
                }
            )
            .sensoryFeedback(trigger: center.completionState) { _, new in
                guard let state = new?.state else { return nil }
                switch state {
                case .failed: return .error
                case .completed: return .success
                case .partialComplete: return .warning
                }
            }
            .toast(
                item: shown($center.progressState), offsetY: 20,
                alert: { progress in
                    guard let progress else {
                        return AlertToast(
                            displayMode: .hud,
                            type: .loading,
                            titleResource: "Loading...")
                    }
                    let fraction = Double(progress.current) / Double(progress.total)
                    return AlertToast(
                        displayMode: .hud,
                        type: .progress(fraction),
                        titleResource: progress.messageResource
                    )
                }
            )
            .toast(
                item: shown($center.loadingMessage),
                duration: 0,
                tapToDismiss: false,
                offsetY: 20
            ) { message in
                AlertToast(
                    displayMode: .hud,
                    type: .systemImage("arrow.clockwise.circle", .blue),
                    titleResource: message?.messageResource)
            }
            .toast(
                isPresenting: shown($center.favorited), duration: 1.5, offsetY: 35,
                alert: {
                    AlertToast(
                        displayMode: .hud,
                        type: .systemImage("heart.fill", .pink),
                        titleResource: "Favorited")
                }
            )
            .toast(
                isPresenting: shown($center.unFavorited), duration: 1.5, offsetY: 35,
                alert: {
                    AlertToast(
                        displayMode: .hud,
                        type: .systemImage("heart.slash.fill", .gray),
                        titleResource: "Unfavorited")
                }
            )
            #if os(macOS)
                .onChange(of: appearsActive, initial: true) { claimIfActive() }
                .onChange(of: windowSceneIdentifier) { claimIfActive() }
            #endif
    }

    private var isPresentingWindow: Bool {
        center.presentsToasts(inSceneIdentifier: windowSceneIdentifier)
    }

    /// Hides the toast in windows other than the presenting one, and keeps them from
    /// dismissing it there.
    private func shown(_ binding: Binding<Bool>) -> Binding<Bool> {
        Binding(
            get: { isPresentingWindow && binding.wrappedValue },
            set: { if isPresentingWindow { binding.wrappedValue = $0 } }
        )
    }

    private func shown<Item>(_ binding: Binding<Item?>) -> Binding<Item?> {
        Binding(
            get: { isPresentingWindow ? binding.wrappedValue : nil },
            set: { if isPresentingWindow { binding.wrappedValue = $0 } }
        )
    }

    #if os(macOS)
        private func claimIfActive() {
            if appearsActive { center.windowBecameActive(sceneIdentifier: windowSceneIdentifier) }
        }
    #endif
}

extension View {
    /// Attach globalToasts to this view.
    ///
    /// It is advised to use this modifer on the root view.
    ///
    /// - Note:
    /// Should not be used when a modal view is being presented.
    func globalToasts(center: ToastCenter = .global) -> some View {
        self.modifier(GlobalToastsModifier(center: center))
    }
}
