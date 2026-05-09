//
//  WhatsNewActionRunner.swift
//  MyAnimeList
//
//  Created by OpenAI Codex on 2026/5/9.
//

import Foundation
import SwiftUI

@Observable @MainActor
final class WhatsNewActionRunner {
    struct RefreshProgress {
        let messageResource: LocalizedStringResource
        let fractionCompleted: Double?
    }

    enum RefreshState {
        case idle
        case inProgress(RefreshProgress)
        case completed(LibraryRefreshCompletion)
    }

    @ObservationIgnored
    private let refreshMetadata: @MainActor (LibraryRefreshOptions) -> Void

    var refreshState: RefreshState = .idle

    init(
        refreshMetadata: @escaping @MainActor (LibraryRefreshOptions) -> Void
    ) {
        self.refreshMetadata = refreshMetadata
    }

    func run(
        _ action: WhatsNewEntry.Action.Kind,
        openURL: @escaping @MainActor (URL) -> Void
    ) {
        switch action {
        case .refreshMetadata:
            startRefreshMetadata()
        case .openURL(let url):
            openURL(url)
        }
    }

    var isRefreshRunning: Bool {
        if case .inProgress = refreshState {
            true
        } else {
            false
        }
    }

    private func startRefreshMetadata() {
        guard !isRefreshRunning else { return }

        refreshState = .inProgress(
            .init(
                messageResource: "Refreshing Metadata...",
                fractionCompleted: 0
            )
        )
        refreshMetadata(
            .init(
                reporter: .init { [weak self] event in
                    self?.receive(event)
                },
                prefetchImages: true
            )
        )
    }

    private func receive(_ event: LibraryRefreshEvent) {
        switch event {
        case .metadataProgress(let current, let total, let messageResource),
            .imagePrefetchProgress(let current, let total, let messageResource):
            refreshState = .inProgress(
                .init(
                    messageResource: messageResource,
                    fractionCompleted: progressFraction(
                        current: current,
                        total: total
                    )
                )
            )
        case .organizingLibrary(let messageResource):
            refreshState = .inProgress(
                .init(
                    messageResource: messageResource,
                    fractionCompleted: nil
                )
            )
        case .metadataPhaseComplete, .imagePrefetchPhaseComplete:
            break
        case .refreshComplete(let completion):
            refreshState = .completed(completion)
        }
    }

    private func progressFraction(current: Int, total: Int) -> Double? {
        guard total > 0 else { return 1 }
        return min(max(Double(current) / Double(total), 0), 1)
    }
}
