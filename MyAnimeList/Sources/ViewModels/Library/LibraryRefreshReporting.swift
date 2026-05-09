//
//  LibraryRefreshReporting.swift
//  MyAnimeList
//
//  Created by OpenAI Codex on 2026/5/9.
//

import SwiftUI

enum LibraryRefreshCompletionState: Equatable {
    case completed
    case failed
    case partialComplete
}

struct LibraryRefreshCompletion {
    let state: LibraryRefreshCompletionState
    let messageResource: LocalizedStringResource
    let successfulItemCount: Int?
    let failedItemCount: Int?

    init(
        state: LibraryRefreshCompletionState,
        messageResource: LocalizedStringResource,
        successfulItemCount: Int? = nil,
        failedItemCount: Int? = nil
    ) {
        self.state = state
        self.messageResource = messageResource
        self.successfulItemCount = successfulItemCount
        self.failedItemCount = failedItemCount
    }
}

/// Phase-complete events are non-terminal. Reporters should treat
/// `refreshComplete` as the only overall completion signal.
enum LibraryRefreshEvent {
    case metadataProgress(current: Int, total: Int, messageResource: LocalizedStringResource)
    case organizingLibrary(messageResource: LocalizedStringResource)
    case metadataPhaseComplete(LibraryRefreshCompletion)
    case imagePrefetchProgress(current: Int, total: Int, messageResource: LocalizedStringResource)
    case imagePrefetchPhaseComplete(LibraryRefreshCompletion)
    case refreshComplete(LibraryRefreshCompletion)
}

struct LibraryRefreshReporter {
    let reportEvent: @MainActor (LibraryRefreshEvent) -> Void

    @MainActor
    private final class ToastSession {
        var isCompleted = false
    }

    @MainActor
    func report(_ event: LibraryRefreshEvent) {
        reportEvent(event)
    }

    static let silent = Self { _ in }

    @MainActor
    static var toast: Self {
        let session = ToastSession()
        return Self { event in
            switch event {
            case .metadataProgress(let current, let total, let messageResource),
                .imagePrefetchProgress(let current, let total, let messageResource):
                guard !session.isCompleted else { return }
                ToastCenter.global.completionState = nil
                ToastCenter.global.loadingMessage = nil
                ToastCenter.global.progressState = .progress(
                    current: current,
                    total: total,
                    messageResource: messageResource
                )
            case .organizingLibrary(let messageResource):
                guard !session.isCompleted else { return }
                ToastCenter.global.completionState = nil
                ToastCenter.global.progressState = nil
                ToastCenter.global.loadingMessage = .message(messageResource)
            case .metadataPhaseComplete, .imagePrefetchPhaseComplete:
                break
            case .refreshComplete(let completion):
                session.isCompleted = true
                ToastCenter.global.loadingMessage = nil
                ToastCenter.global.progressState = nil
                ToastCenter.global.completionState = toastCompletion(for: completion)
            }
        }
    }

    @MainActor
    private static func toastCompletion(
        for completion: LibraryRefreshCompletion
    ) -> ToastCenter.CompletedWithMessage {
        .init(
            state: toastState(for: completion.state),
            messageResource: completion.messageResource
        )
    }

    private static func toastState(
        for state: LibraryRefreshCompletionState
    ) -> ToastCenter.CompletedWithMessage.State {
        switch state {
        case .completed:
            .completed
        case .failed:
            .failed
        case .partialComplete:
            .partialComplete
        }
    }
}

struct LibraryRefreshOptions {
    let reporter: LibraryRefreshReporter
    let prefetchImages: Bool

    @MainActor
    static var toastDefault: Self {
        Self(
            reporter: .toast,
            prefetchImages: true
        )
    }
}
