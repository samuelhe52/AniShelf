//
//  ShareSheetPresenter.swift
//  MyAnimeList
//
//  Created by OpenAI Codex on 2026/5/9.
//

import SwiftUI
import UIKit

@MainActor
enum ShareSheetPresenter {
    static func present(items: [Any]) {
        let activityViewController = UIActivityViewController(
            activityItems: items,
            applicationActivities: nil
        )

        if UIDevice.current.userInterfaceIdiom == .pad {
            let hostingController = UIHostingController(rootView: EmptyView())
            activityViewController.popoverPresentationController?.sourceView = hostingController.view
        }

        let rootViewController = UIApplication.shared.connectedScenes
            .flatMap { ($0 as? UIWindowScene)?.windows ?? [] }
            .first { $0.isKeyWindow }?
            .rootViewController
        guard let rootViewController else { return }

        if let presentedViewController = rootViewController.presentedViewController {
            presentedViewController.dismiss(
                animated: true,
                completion: {
                    rootViewController.present(activityViewController, animated: true)
                }
            )
        } else {
            rootViewController.present(activityViewController, animated: true)
        }
    }
}
