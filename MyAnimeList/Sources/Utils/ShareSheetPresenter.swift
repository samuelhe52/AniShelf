//
//  ShareSheetPresenter.swift
//  MyAnimeList
//
//  Created by OpenAI Codex on behalf of Samuel He on 2026/5/9.
//

import UIKit

@MainActor
enum ShareSheetPresenter {
    /// Presents in the window of `sceneIdentifier`, normally read from `\.windowSceneIdentifier`.
    ///
    /// Every foreground scene has its own key window, so only the invoking scene identifies the
    /// right window. If that scene disconnected meanwhile, nothing is presented.
    static func present(items: [Any], sceneIdentifier: String?) {
        guard let presenter = presentationViewController(sceneIdentifier: sceneIdentifier) else { return }

        let activityViewController = UIActivityViewController(
            activityItems: items,
            applicationActivities: nil
        )

        if let popover = activityViewController.popoverPresentationController {
            popover.sourceView = presenter.view
            popover.sourceRect = CGRect(
                x: presenter.view.bounds.midX,
                y: presenter.view.bounds.midY,
                width: 0,
                height: 0
            )
            popover.permittedArrowDirections = []
        }

        presenter.present(activityViewController, animated: true)
    }

    private static func presentationViewController(sceneIdentifier: String?) -> UIViewController? {
        let windowScenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
        let scene: UIWindowScene?
        if let sceneIdentifier {
            scene = windowScenes.first { $0.session.persistentIdentifier == sceneIdentifier }
        } else {
            // Unresolved identifier: only unambiguous with a single foreground window.
            let activeScenes = windowScenes.filter { $0.activationState == .foregroundActive }
            scene = activeScenes.count == 1 ? activeScenes.first : nil
        }

        let window = scene?.keyWindow ?? scene?.windows.first(where: { !$0.isHidden })

        guard let rootViewController = window?.rootViewController else { return nil }
        return topViewController(from: rootViewController)
    }

    private static func topViewController(from viewController: UIViewController) -> UIViewController {
        if let presentedViewController = viewController.presentedViewController,
            !presentedViewController.isBeingDismissed
        {
            return topViewController(from: presentedViewController)
        }

        if let navigationController = viewController as? UINavigationController,
            let visibleViewController = navigationController.visibleViewController
        {
            return topViewController(from: visibleViewController)
        }

        if let tabBarController = viewController as? UITabBarController,
            let selectedViewController = tabBarController.selectedViewController
        {
            return topViewController(from: selectedViewController)
        }

        return viewController
    }
}
