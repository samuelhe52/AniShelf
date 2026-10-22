//
//  MacWhatsNewView.swift
//  AniShelf
//
//  Created by Claude Code on behalf of samuelhe52 on 2026/10/17.
//

#if os(macOS)
    import SwiftUI

    /// What's New on the Mac: a grouped form with this version's summary, highlights, and
    /// actions, then one section per earlier version.
    ///
    /// It is a sheet on a library window, both
    /// after an update and from Help ▸ What's New in AniShelf.
    struct MacWhatsNewView: View {
        let entry: WhatsNewEntry
        let pastEntries: [WhatsNewEntry]
        let actionRunner: WhatsNewActionRunner
        let onDismiss: () -> Void

        @Environment(\.openURL) private var openURL

        var body: some View {
            Form {
                Section {
                    VStack(alignment: .leading, spacing: 6) {
                        Label {
                            Text("Version \(entry.version)")
                        } icon: {
                            Image(systemName: "sparkles.rectangle.stack.fill")
                                .foregroundStyle(.orange)
                        }
                        .font(.title2.weight(.bold))
                        Text(entry.summary)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .padding(.vertical, 4)
                    highlights(of: entry)
                }

                if entry.primaryAction != nil || !entry.secondaryActions.isEmpty {
                    Section {
                        if let primaryAction = entry.primaryAction {
                            primaryActionRow(primaryAction)
                        }
                        ForEach(entry.secondaryActions) { action in
                            Button {
                                run(action)
                            } label: {
                                Label(action.title, systemImage: action.systemImage)
                            }
                        }
                    }
                    .animation(.default, value: actionRunner.isRefreshRunning)
                }

                ForEach(pastEntries) { pastEntry in
                    Section {
                        Text(pastEntry.summary)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                        highlights(of: pastEntry)
                    } header: {
                        Text("Version \(pastEntry.version)")
                    }
                }
            }
            .formStyle(.grouped)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button(LocalizedStringResource("Done"), action: onDismiss)
                }
            }
            .macSheetFrame(width: 600, height: 640)
        }

        private func highlights(of entry: WhatsNewEntry) -> some View {
            ForEach(entry.highlights.indices, id: \.self) { index in
                WhatsNewHighlightRow(text: entry.highlights[index])
            }
        }

        /// The primary action as a prominent button, or a progress bar while it runs.
        private func primaryActionRow(_ action: WhatsNewEntry.Action) -> some View {
            let presentation = WhatsNewPrimaryActionPresentation(action: action, runner: actionRunner)
            return VStack(alignment: .leading, spacing: 8) {
                if let fraction = presentation.progressFraction {
                    ProgressView(value: fraction) {
                        Text(presentation.title)
                    }
                } else {
                    Button {
                        run(action)
                    } label: {
                        Label {
                            Text(presentation.title)
                        } icon: {
                            if let systemImage = presentation.systemImage {
                                Image(systemName: systemImage)
                            }
                        }
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(presentation.tint)
                    .disabled(!presentation.isEnabled)
                }
                if actionRunner.showsRefreshDismissalNotice(for: action) {
                    WhatsNewRefreshNotice()
                }
            }
        }

        private func run(_ action: WhatsNewEntry.Action) {
            actionRunner.run(action.kind, openURL: { openURL($0) })
        }
    }
#endif
