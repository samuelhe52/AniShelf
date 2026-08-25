//
//  LibrarySyncBackgroundExecutionController.swift
//  AniShelf
//
//  Created by OpenAI Codex on behalf of samuelhe52 on 2026/8/25.
//

import UIKit

/// Keeps a bounded library sync operation executable while the app suspends.
@MainActor
final class LibrarySyncBackgroundExecutionController {
    typealias ExpirationHandler = @MainActor @Sendable () -> Void
    typealias BeginBackgroundTask =
        @MainActor (
            _ name: String,
            _ expirationHandler: @escaping ExpirationHandler
        ) -> UIBackgroundTaskIdentifier
    typealias EndBackgroundTask = @MainActor (UIBackgroundTaskIdentifier) -> Void

    private let beginBackgroundTask: BeginBackgroundTask
    private let endBackgroundTask: EndBackgroundTask
    private var backgroundTaskIdentifier = UIBackgroundTaskIdentifier.invalid
    private var operationTask: Task<Void, Never>?
    private var expirationAction: (@MainActor () -> Void)?

    init(
        beginBackgroundTask: @escaping BeginBackgroundTask = { name, expirationHandler in
            UIApplication.shared.beginBackgroundTask(
                withName: name,
                expirationHandler: expirationHandler
            )
        },
        endBackgroundTask: @escaping EndBackgroundTask = { identifier in
            UIApplication.shared.endBackgroundTask(identifier)
        }
    ) {
        self.beginBackgroundTask = beginBackgroundTask
        self.endBackgroundTask = endBackgroundTask
    }

    /// Starts one protected operation, ignoring duplicate requests until it finishes.
    func run(
        onExpiration: @escaping @MainActor () -> Void,
        operation: @escaping @MainActor () async -> Void
    ) {
        guard operationTask == nil else { return }

        let identifier = beginBackgroundTask("Finish iCloud Library Sync") { [weak self] in
            self?.expire()
        }
        guard identifier != .invalid else { return }

        backgroundTaskIdentifier = identifier
        expirationAction = onExpiration
        operationTask = Task { [weak self] in
            await operation()
            self?.finish(identifier: identifier)
        }
    }

    private func expire() {
        operationTask?.cancel()
        expirationAction?()
        finish(identifier: backgroundTaskIdentifier)
    }

    private func finish(identifier: UIBackgroundTaskIdentifier) {
        guard identifier != .invalid, backgroundTaskIdentifier == identifier else { return }
        backgroundTaskIdentifier = .invalid
        operationTask = nil
        expirationAction = nil
        endBackgroundTask(identifier)
    }
}
