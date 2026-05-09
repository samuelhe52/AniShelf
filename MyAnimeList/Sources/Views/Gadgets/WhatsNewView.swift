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
        VStack(alignment: .leading, spacing: 14) {
            versionBadge

            VStack(alignment: .leading, spacing: 8) {
                Text(entry.title)
                    .font(.title2.weight(.bold))
                    .fixedSize(horizontal: false, vertical: true)

                Text(entry.summary)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(18)
        .popupGlassPanel(cornerRadius: 28, tint: .clear)
    }

    private var versionBadge: some View {
        HStack(spacing: 8) {
            Image(systemName: "sparkles.rectangle.stack.fill")
                .font(.footnote.weight(.bold))
            Text("Version \(entry.version)")
                .font(.footnote.weight(.semibold))
        }
        .foregroundStyle(.orange)
        .padding(.horizontal, 12)
        .padding(.vertical, 7)
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
                    primaryActionButton(for: primaryAction)
                }

                ForEach(entry.secondaryActions) { action in
                    Button {
                        actionRunner.run(action.kind)
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
        }
    }

    private var primaryActionButton: some View {
        Group {
            if let primaryAction = entry.primaryAction {
                primaryActionButton(for: primaryAction)
            }
        }
    }

    private func primaryActionButton(for action: WhatsNewEntry.Action) -> some View {
        Button {
            actionRunner.run(action.kind)
        } label: {
            Label {
                Text(action.title)
            } icon: {
                Image(systemName: action.systemImage)
            }
            .font(.subheadline.weight(.semibold))
            .frame(maxWidth: .infinity)
        }
        .buttonStyle(LibraryProfileCommandButtonStyle(tint: .orange, filled: true))
    }

    private func highlightRow(_ text: LocalizedStringResource) -> some View {
        HStack(alignment: .top, spacing: 12) {
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
            actionRunner: .init(
                refreshMetadata: {},
                openURL: { _ in }
            ),
            onDismiss: {}
        )
    }
}
