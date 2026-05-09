//
//  WhatsNewView.swift
//  MyAnimeList
//
//  Created by OpenAI Codex on 2026/5/9.
//

import SwiftUI

struct WhatsNewView: View {
    let entry: WhatsNewEntry
    let actionRunner: WhatsNewActionRunner
    let onDismiss: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.openURL) private var openURL

    var body: some View {
        ZStack {
            LibraryProfileBackdrop(reduceMotion: reduceMotion)

            ScrollView {
                VStack(spacing: 16) {
                    heroCard
                    highlightsCard
                    if showsInlinePrimaryAction {
                        primaryActionButton
                    } else if showsActionsCard {
                        actionsCard
                    }
                }
                .padding(.horizontal, 20)
                .padding(.top, 16)
                .padding(.bottom, 20)
            }
            .scrollBounceBehavior(.basedOnSize)
        }
        .navigationTitle(whatsNewTitleResource)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button(doneTitleResource, action: onDismiss)
            }
        }
    }

    private var heroCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            versionBadge

            Text(entry.summary)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(18)
        .popupGlassPanel(cornerRadius: 28, tint: .clear)
    }

    private var versionBadge: some View {
        HStack(spacing: 10) {
            Image(systemName: "sparkles.rectangle.stack.fill")
                .font(.subheadline.weight(.bold))
            Text("Version \(entry.version)")
                .font(.callout.weight(.semibold))
        }
        .foregroundStyle(.orange)
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(.orange.opacity(0.12), in: Capsule(style: .continuous))
        .overlay {
            Capsule(style: .continuous)
                .stroke(.orange.opacity(0.18), lineWidth: 1)
        }
    }

    private var highlightsCard: some View {
        PopupSectionCard(
            "Highlights",
            systemImage: "checklist"
        ) {
            VStack(alignment: .leading, spacing: 12) {
                ForEach(entry.highlights.indices, id: \.self) { index in
                    highlightRow(entry.highlights[index])
                }
            }
        }
    }

    private var actionsCard: some View {
        PopupSectionCard(
            "Actions",
            systemImage: "arrow.forward.circle"
        ) {
            VStack(alignment: .leading, spacing: 12) {
                if let primaryAction = entry.primaryAction {
                    primaryActionSection(for: primaryAction)
                }

                ForEach(entry.secondaryActions) { action in
                    Button {
                        actionRunner.run(
                            action.kind,
                            openURL: { url in
                                openURL(url)
                            }
                        )
                    } label: {
                        HStack(spacing: 12) {
                            Image(systemName: action.systemImage)
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(.secondary)
                            Text(action.title)
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(.primary)
                            Spacer(minLength: 12)
                            Image(systemName: "arrow.up.right")
                                .font(.footnote.weight(.bold))
                                .foregroundStyle(.tertiary)
                        }
                        .padding(.horizontal, 12)
                        .padding(.vertical, 10)
                        .background(.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                    }
                    .buttonStyle(.plain)
                }
            }
            .animation(.default, value: actionRunner.isRefreshRunning)
        }
    }

    private var primaryActionButton: some View {
        Group {
            if let primaryAction = entry.primaryAction {
                primaryActionSection(for: primaryAction)
            }
        }
    }

    @ViewBuilder
    private func primaryActionSection(for action: WhatsNewEntry.Action) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            primaryActionButton(for: action)

            if showsRefreshDismissalNotice(for: action) {
                refreshDismissalNotice
            }
        }
    }

    @ViewBuilder
    private func primaryActionButton(for action: WhatsNewEntry.Action) -> some View {
        let presentation = primaryActionPresentation(for: action)

        WhatsNewPrimaryActionButton(
            title: presentation.title,
            systemImage: presentation.systemImage,
            tint: presentation.tint,
            progressFraction: presentation.progressFraction,
            showsActivity: presentation.showsActivity,
            isEnabled: presentation.isEnabled
        ) {
            actionRunner.run(
                action.kind,
                openURL: { url in
                    openURL(url)
                }
            )
        }
    }

    private var refreshDismissalNotice: some View {
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

    private func showsRefreshDismissalNotice(for action: WhatsNewEntry.Action) -> Bool {
        guard actionRunner.isRefreshRunning else { return false }
        if case .refreshMetadata = action.kind {
            return true
        }
        return false
    }

    @ViewBuilder
    private func highlightRow(_ text: LocalizedStringResource) -> some View {
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

    private var whatsNewTitleResource: LocalizedStringResource {
        "What's New"
    }

    private var doneTitleResource: LocalizedStringResource {
        "Done"
    }

    private func primaryActionPresentation(
        for action: WhatsNewEntry.Action
    ) -> WhatsNewPrimaryActionPresentation {
        guard case .refreshMetadata = action.kind else {
            return .init(
                title: action.title,
                systemImage: action.systemImage,
                tint: .orange,
                progressFraction: nil,
                showsActivity: false,
                isEnabled: true
            )
        }

        switch actionRunner.refreshState {
        case .idle:
            return .init(
                title: action.title,
                systemImage: action.systemImage,
                tint: .orange,
                progressFraction: nil,
                showsActivity: false,
                isEnabled: true
            )
        case .inProgress(let progress):
            return .init(
                title: progress.messageResource,
                systemImage: nil,
                tint: .orange,
                progressFraction: progress.fractionCompleted,
                showsActivity: true,
                isEnabled: false
            )
        case .completed(let completion):
            return .init(
                title: completion.messageResource,
                systemImage: completionSystemImage(for: completion.state),
                tint: completionTint(for: completion.state),
                progressFraction: nil,
                showsActivity: false,
                isEnabled: completion.state != .completed
            )
        }
    }

    private func completionSystemImage(
        for state: LibraryRefreshCompletionState
    ) -> String {
        switch state {
        case .completed:
            "checkmark.circle.fill"
        case .failed:
            "xmark.circle.fill"
        case .partialComplete:
            "exclamationmark.triangle.fill"
        }
    }

    private func completionTint(
        for state: LibraryRefreshCompletionState
    ) -> Color {
        switch state {
        case .completed:
            .green
        case .failed:
            .red
        case .partialComplete:
            .orange
        }
    }

    private var showsInlinePrimaryAction: Bool {
        entry.primaryAction != nil && entry.secondaryActions.isEmpty
    }

    private var showsActionsCard: Bool {
        !entry.secondaryActions.isEmpty
    }
}

#Preview {
    NavigationStack {
        WhatsNewView(
            entry: WhatsNewRegistry.currentEntry(for: "1.54")!,
            actionRunner: .init(refreshMetadata: { _ in }),
            onDismiss: {}
        )
    }
}

fileprivate struct WhatsNewPrimaryActionPresentation {
    let title: LocalizedStringResource
    let systemImage: String?
    let tint: Color
    let progressFraction: Double?
    let showsActivity: Bool
    let isEnabled: Bool
}

fileprivate struct WhatsNewPrimaryActionButton: View {
    let title: LocalizedStringResource
    let systemImage: String?
    let tint: Color
    let progressFraction: Double?
    let showsActivity: Bool
    let isEnabled: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                if showsActivity {
                    ProgressView()
                        .tint(foregroundColor)
                } else if let systemImage {
                    Image(systemName: systemImage)
                        .font(.subheadline.weight(.bold))
                }

                Text(title)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .font(.subheadline.weight(.semibold))
            .frame(maxWidth: .infinity)
            .frame(minHeight: 44)
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .background {
                GeometryReader { geometry in
                    let shape = RoundedRectangle(cornerRadius: 18, style: .continuous)
                    ZStack(alignment: .leading) {
                        shape
                            .fill(trackGradient)

                        if let progressFraction {
                            shape
                                .fill(progressGradient)
                                .frame(
                                    width: max(
                                        geometry.size.width * progressFraction,
                                        progressFraction > 0 ? 42 : 0
                                    )
                                )
                        } else {
                            shape
                                .fill(progressGradient)
                        }
                    }
                    .clipShape(shape)
                }
            }
            .foregroundStyle(foregroundColor)
            .overlay {
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .stroke(.white.opacity(0.18), lineWidth: 1)
            }
            .shadow(color: tint.opacity(0.18), radius: 16, y: 10)
            .animation(.spring(response: 0.3, dampingFraction: 0.85), value: progressFraction)
            .animation(.spring(response: 0.3, dampingFraction: 0.85), value: tint)
            .opacity(isEnabled ? 1 : 0.96)
        }
        .buttonStyle(.plain)
        .allowsHitTesting(isEnabled)
    }

    private var isProgressBar: Bool {
        progressFraction != nil
    }

    private var foregroundColor: Color {
        if isProgressBar {
            Color(red: 0.39, green: 0.21, blue: 0.05)
        } else {
            .white
        }
    }

    private var trackGradient: LinearGradient {
        if isProgressBar {
            return LinearGradient(
                colors: [
                    Color(red: 0.99, green: 0.94, blue: 0.88),
                    Color(red: 0.98, green: 0.89, blue: 0.80)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        }

        return LinearGradient(
            colors: [
                tint.opacity(0.92),
                tint.opacity(0.76)
            ],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }

    private var progressGradient: LinearGradient {
        if isProgressBar {
            return LinearGradient(
                colors: [
                    Color(red: 0.99, green: 0.76, blue: 0.44),
                    Color(red: 0.95, green: 0.56, blue: 0.15)
                ],
                startPoint: .leading,
                endPoint: .trailing
            )
        }

        return LinearGradient(
            colors: [
                tint,
                tint.opacity(0.84)
            ],
            startPoint: .leading,
            endPoint: .trailing
        )
    }
}
