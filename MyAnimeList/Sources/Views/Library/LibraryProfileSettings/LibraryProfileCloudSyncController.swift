//
//  LibraryProfileCloudSyncController.swift
//  AniShelf
//
//  Created by OpenAI Codex on behalf of Samuel He on 2026/10/13.
//

import SwiftUI
import UIKit

/// Presentation state stays alive when a destination is pushed, popped, or resized.
@MainActor @Observable
final class LibraryProfileCloudSyncController {
    var actionInFlight = false
    var showConflictAlert = false
    var showRebuildAlert = false
    var showRestoreUnavailableAlert = false

    func reconcileConflict(needsChoice: Bool, presentationBlocked: Bool) {
        if !needsChoice {
            showConflictAlert = false
        } else if !presentationBlocked, !actionInFlight {
            showConflictAlert = true
        }
    }

    /// SwiftUI sheets, popovers, alerts, and UIKit share sheets all occupy the
    /// presenting scene.
    ///
    /// Keep the conflict pending until their dismissal finishes.
    static func sceneIsReadyForAlert(_ sceneIdentifier: String?) -> Bool {
        let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
        let scene: UIWindowScene?
        if let sceneIdentifier {
            scene = scenes.first { $0.session.persistentIdentifier == sceneIdentifier }
        } else {
            let active = scenes.filter { $0.activationState == .foregroundActive }
            scene = active.count == 1 ? active.first : nil
        }
        guard let scene, scene.activationState == .foregroundActive,
            let root = (scene.keyWindow ?? scene.windows.first { !$0.isHidden })?.rootViewController
        else { return false }
        return !hasPresentedModal(root)
    }

    private static func hasPresentedModal(_ controller: UIViewController) -> Bool {
        if controller.presentedViewController != nil { return true }
        return controller.children.contains { hasPresentedModal($0) }
    }
}
