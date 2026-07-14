//
//  ShareSheetPresenter.swift
//  MyAnimeList
//
//  Created by OpenAI Codex on behalf of Samuel He on 2026/5/9.
//

import UIKit

@MainActor
enum ShareSheetPresenter {
    static func present(items: [Any]) {
        guard let presenter = activePresentationViewController() else { return }

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

    private static func activePresentationViewController() -> UIViewController? {
        let activeScenes = UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .filter { $0.activationState == .foregroundActive }

        let window =
            activeScenes
            .flatMap(\.windows)
            .first(where: \.isKeyWindow)
            ?? activeScenes.flatMap(\.windows).first(where: { !$0.isHidden })

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
