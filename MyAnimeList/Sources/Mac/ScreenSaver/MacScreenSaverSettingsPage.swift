//
//  MacScreenSaverSettingsPage.swift
//  AniShelf
//
//  Created by OpenAI Codex on behalf of Samuel He on 2026/11/20.
//

#if os(macOS)
    import AppKit
    import ScreenSaverKit
    import SwiftUI

    struct MacScreenSaverSettingsPage: View {
        @Environment(LibraryStore.self) private var library

        var body: some View {
            if let publisher = library.screenSaverPublisher {
                ScreenSaverOptionsSection(publisher: publisher, library: library)
                ScreenSaverPreviewSection(publisher: publisher)
                ScreenSaverPublicationSection(publisher: publisher)
            } else {
                Text("Settings Unavailable")
            }
        }
    }

    fileprivate struct ScreenSaverOptionsSection: View {
        @Bindable var publisher: ScreenSaverPublisher
        let library: LibraryStore
        private static let intervals: [TimeInterval] = [5, 8, 12, 20, 30, 60]

        var body: some View {
            Section {
                Toggle("Enable Screen Saver", isOn: $publisher.settings.isEnabled)
                Picker("Library Scope", selection: $publisher.settings.scope) {
                    ForEach(ScreenSaverSettings.Scope.allCases, id: \.self) { scope in
                        Text(scope.title).tag(scope)
                    }
                }
                LabeledContent("Eligible Entries") {
                    Text(library.library.count(where: publisher.settings.scope.includes), format: .number)
                        .monospacedDigit()
                }
                Picker("Layout", selection: $publisher.settings.layout) {
                    ForEach(ScreenSaverManifest.Layout.allCases, id: \.self) { layout in
                        Text(layout.title).tag(layout)
                    }
                }
                Toggle("Show Titles", isOn: $publisher.settings.showsTitles)
                if publisher.settings.layout != .coverWall {
                    Picker("Interval", selection: $publisher.settings.interval) {
                        let current = publisher.settings.interval
                        let intervals =
                            Self.intervals.contains(current) ? Self.intervals : (Self.intervals + [current]).sorted()
                        ForEach(intervals, id: \.self) { seconds in
                            Text(
                                Measurement(value: seconds, unit: UnitDuration.seconds),
                                format: .measurement(width: .wide, usage: .asProvided)
                            )
                            .tag(seconds)
                        }
                    }
                }
            }
        }
    }

    fileprivate struct ScreenSaverPreviewSection: View {
        let publisher: ScreenSaverPublisher

        var body: some View {
            Section("Preview") {
                Group {
                    if publisher.settings.isEnabled {
                        ScreenSaverPreviewView(directory: publisher.directory, generation: publisher.status.generation)
                            .accessibilityLabel("Screen saver preview")
                    } else {
                        Text("Enable the screen saver to see a preview.")
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                            .padding()
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                            .background(.quaternary)
                    }
                }
                .aspectRatio(16.0 / 9, contentMode: .fit)
                .frame(maxWidth: 384)
                .clipShape(.rect(cornerRadius: 8))
                .frame(maxWidth: .infinity)
            }
        }
    }

    fileprivate struct ScreenSaverPublicationSection: View {
        let publisher: ScreenSaverPublisher
        @State private var showInstallError = false

        var body: some View {
            Section("Publication") {
                LabeledContent("Last Published") {
                    if let date = publisher.status.lastPublication {
                        Text(date, format: .dateTime.year().month(.abbreviated).day().hour().minute().second())
                            .monospacedDigit()
                    } else {
                        Text("Never")
                    }
                }
                LabeledContent("Entries Without Artwork") {
                    Text(publisher.status.unavailableImageCount, format: .number)
                        .monospacedDigit()
                }
                if let error = publisher.status.error {
                    LabeledContent("Publication Error") {
                        Text(error.localizedDescription)
                            .foregroundStyle(.red)
                            .multilineTextAlignment(.trailing)
                            .textSelection(.enabled)
                    }
                }
                HStack {
                    Button("Refresh Now") {
                        Task { await publisher.refreshNow() }
                    }
                    .disabled(!publisher.settings.isEnabled || publisher.status.isPublishing)

                    Button("Show in Finder") {
                        NSWorkspace.shared.activateFileViewerSelecting([publisher.directory])
                    }
                    .disabled(publisher.status.generation == nil)

                    if publisher.status.isPublishing {
                        ProgressView("Publishing…")
                            .controlSize(.small)
                    }

                    Spacer()
                    Button("Install Screen Saver…", action: install)
                }
            }
            .alert("Couldn’t Open Screen Saver", isPresented: $showInstallError) {
                Button("OK", role: .cancel) {}
            }
        }

        private func install() {
            let bundle = Bundle.main.bundleURL
                .appending(path: "Contents/Library/Screen Savers/AniShelf.saver", directoryHint: .isDirectory)
            if !NSWorkspace.shared.open(bundle) { showInstallError = true }
        }
    }

    extension ScreenSaverSettings.Scope {
        fileprivate var title: LocalizedStringResource {
            switch self {
            case .favorites: "Favorites"
            case .watched: "Watched"
            case .all: "All Library Entries"
            }
        }
    }

    extension ScreenSaverManifest.Layout {
        fileprivate var title: LocalizedStringResource {
            switch self {
            case .coverWall: "Cover Wall"
            case .posterFocus: "Poster Focus"
            case .heroStill: "Hero Still"
            }
        }
    }
#endif
