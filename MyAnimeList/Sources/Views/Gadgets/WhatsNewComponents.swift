//
//  WhatsNewComponents.swift
//  AniShelf
//
//  Created by Claude Code on behalf of samuelhe52 on 2026/10/17.
//

import SwiftUI

/// How a What's New entry's primary action looks: its own title, or the metadata refresh's
/// progress and result while the action is a refresh.
///
/// Shared by the iOS and Mac layouts.
struct WhatsNewPrimaryActionPresentation {
    let title: LocalizedStringResource
    let systemImage: String?
    let tint: Color
    let progressFraction: Double?
    let showsActivity: Bool
    let isEnabled: Bool

    @MainActor
    init(action: WhatsNewEntry.Action, runner: WhatsNewActionRunner) {
        guard case .refreshMetadata = action.kind else {
            self.init(title: action.title, systemImage: action.systemImage)
            return
        }

        switch runner.refreshState {
        case .idle:
            self.init(title: action.title, systemImage: action.systemImage)
        case .inProgress(let progress):
            self.init(
                title: progress.messageResource,
                systemImage: nil,
                progressFraction: progress.fractionCompleted,
                showsActivity: true,
                isEnabled: false
            )
        case .completed(let completion):
            self.init(
                title: completion.messageResource,
                systemImage: Self.systemImage(for: completion.state),
                tint: Self.tint(for: completion.state),
                isEnabled: completion.state != .completed
            )
        }
    }

    private init(
        title: LocalizedStringResource,
        systemImage: String?,
        tint: Color = .orange,
        progressFraction: Double? = nil,
        showsActivity: Bool = false,
        isEnabled: Bool = true
    ) {
        self.title = title
        self.systemImage = systemImage
        self.tint = tint
        self.progressFraction = progressFraction
        self.showsActivity = showsActivity
        self.isEnabled = isEnabled
    }

    private static func systemImage(for state: LibraryRefreshCompletionState) -> String {
        switch state {
        case .completed: "checkmark.circle.fill"
        case .failed: "xmark.circle.fill"
        case .partialComplete: "exclamationmark.triangle.fill"
        }
    }

    private static func tint(for state: LibraryRefreshCompletionState) -> Color {
        switch state {
        case .completed: .green
        case .failed: .red
        case .partialComplete: .orange
        }
    }
}

extension WhatsNewActionRunner {
    /// Whether to ask the user to keep What's New open: a metadata refresh it started is running.
    func showsRefreshDismissalNotice(for action: WhatsNewEntry.Action) -> Bool {
        guard isRefreshRunning else { return false }
        if case .refreshMetadata = action.kind { return true }
        return false
    }
}

/// One highlight of a What's New entry, with an orange check.
struct WhatsNewHighlightRow: View {
    let text: LocalizedStringResource

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            Image(systemName: "checkmark.circle.fill")
                .font(.subheadline.weight(.bold))
                .foregroundStyle(.orange)
                .padding(.top, 2)
            Text(text)
                .font(.subheadline)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

/// Asks the user to keep What's New open while its metadata refresh runs.
struct WhatsNewRefreshNotice: View {
    var body: some View {
        Label {
            Text("Keep this page open until the refresh finishes.")
                .font(.footnote)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        } icon: {
            Image(systemName: "info.circle.fill")
                .font(.footnote.weight(.semibold))
                .foregroundStyle(.orange)
        }
    }
}
