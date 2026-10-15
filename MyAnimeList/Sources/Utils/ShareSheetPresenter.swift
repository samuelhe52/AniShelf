//
//  ShareSheetPresenter.swift
//  MyAnimeList
//
//  Created by OpenAI Codex on behalf of Samuel He on 2026/5/9.
//

#if os(macOS)
    import AppKit
    import UniformTypeIdentifiers
#else
    import UIKit
#endif

#if os(macOS)
    @MainActor
    enum ShareSheetPresenter {
        /// A single file (a backup or an export) is saved with a save panel, as Mac users expect;
        /// anything else goes to the sharing picker.
        static func present(items: [Any], sceneIdentifier: String?) {
            guard let window = presentationWindow(sceneIdentifier), let view = window.contentView else { return }
            if items.count == 1, let fileURL = items.first as? URL, fileURL.isFileURL {
                saveCopy(of: fileURL, in: window)
                return
            }
            let picker = NSSharingServicePicker(items: items)
            picker.show(
                relativeTo: CGRect(x: view.bounds.midX, y: view.bounds.midY, width: 1, height: 1),
                of: view, preferredEdge: .minY)
        }

        /// Offers to save a copy of a local file. `completion` runs once the panel closes, saved
        /// or not, so a caller can remove a temporary source.
        static func saveCopy(
            of fileURL: URL,
            in window: NSWindow,
            completion: @escaping () -> Void = {}
        ) {
            let panel = NSSavePanel()
            panel.nameFieldStringValue = fileURL.lastPathComponent
            panel.canCreateDirectories = true
            if let type = UTType(filenameExtension: fileURL.pathExtension) {
                panel.allowedContentTypes = [type]
            }
            panel.beginSheetModal(for: window) { response in
                defer { completion() }
                guard response == .OK, let destination = panel.url else { return }
                do {
                    // An atomic write replaces an existing file safely on any volume, and keeps
                    // the source, which may be an export the caller still owns.
                    let data = try Data(contentsOf: fileURL, options: .mappedIfSafe)
                    try data.write(to: destination, options: .atomic)
                } catch {
                    NSAlert(error: error).beginSheetModal(for: window, completionHandler: nil)
                }
            }
        }

        /// Downloads a remote file, such as a poster, and offers to save it.
        static func saveDownload(of remoteURL: URL, in window: NSWindow) async {
            let fileManager = FileManager.default
            let staging = fileManager.temporaryDirectory
                .appendingPathComponent(UUID().uuidString, isDirectory: true)
            do {
                let (downloadedURL, response) = try await URLSession.shared.download(from: remoteURL)
                // A server error still downloads its error page; never offer that as the image.
                if let response = response as? HTTPURLResponse, !(200..<300).contains(response.statusCode) {
                    try? fileManager.removeItem(at: downloadedURL)
                    throw URLError(.badServerResponse, userInfo: [NSURLErrorFailingURLErrorKey: remoteURL])
                }
                try fileManager.createDirectory(at: staging, withIntermediateDirectories: true)
                let namedURL = staging.appendingPathComponent(remoteURL.lastPathComponent)
                try fileManager.moveItem(at: downloadedURL, to: namedURL)
                saveCopy(of: namedURL, in: window) {
                    try? fileManager.removeItem(at: staging)
                }
            } catch {
                try? fileManager.removeItem(at: staging)
                NSAlert(error: error).beginSheetModal(for: window, completionHandler: nil)
            }
        }

        static func presentationWindow(_ identifier: String?) -> NSWindow? {
            if let identifier {
                return NSApplication.shared.windows.first { $0.sceneIdentifier == identifier }
            }
            let windows = NSApplication.shared.windows.filter { $0.isVisible && $0.canBecomeMain }
            return windows.count == 1 ? windows.first : nil
        }
    }
#else
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

#endif
