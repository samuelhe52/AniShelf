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
                ScreenSaverSetupSection(publisher: publisher)
                ScreenSaverPreviewSection(publisher: publisher)
            } else {
                ContentUnavailableView {
                    Label("Screen Saver Unavailable", systemImage: "display")
                } description: {
                    Text("Screen saver options are available when your library is ready.")
                }
            }
        }
    }

    fileprivate struct ScreenSaverSetupSection: View {
        let publisher: ScreenSaverPublisher
        @State private var launchError: LocalizedStringResource?

        var body: some View {
            Section("Setup") {
                LabeledContent("1. Install AniShelf’s screen saver") {
                    Button("Install…", action: install)
                }
                LabeledContent("2. Choose AniShelf") {
                    Button("Open Wallpaper Settings", action: openSettings)
                }
                ScreenSaverArtworkStatus(publisher: publisher)
                if publisher.settings.isEnabled {
                    Button("Stop Updating and Remove Artwork") {
                        publisher.settings.isEnabled = false
                    }
                    .controlSize(.small)
                }
            }
            .alert(
                Text(launchError ?? "Couldn’t Open Screen Saver"),
                isPresented: Binding(
                    get: { launchError != nil },
                    set: { if !$0 { launchError = nil } }
                )
            ) {
                Button("OK", role: .cancel) {}
            }
        }

        private func install() {
            let bundle = Bundle.main.bundleURL
                .appending(path: "Contents/Library/Screen Savers/AniShelf.saver", directoryHint: .isDirectory)
            if NSWorkspace.shared.open(bundle) {
                publisher.settings.isEnabled = true
            } else {
                launchError = "Couldn’t Open Screen Saver"
            }
        }

        private func openSettings() {
            guard let url = URL(string: "x-apple.systempreferences:com.apple.Wallpaper-Settings.extension"),
                NSWorkspace.shared.open(url)
            else {
                launchError = "Couldn’t Open System Settings"
                return
            }
        }

    }

    fileprivate struct ScreenSaverArtworkStatus: View {
        let publisher: ScreenSaverPublisher

        var body: some View {
            let status = publisher.status
            HStack {
                statusText(status)
                    .lineLimit(1)
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .accessibilityIdentifier("screenSaverArtworkStatus")
                if status.error != nil || (!status.isPublishing && status.hasFailedArtwork) {
                    Button("Try Again", action: publisher.retryUpdate)
                }
            }
        }

        private func statusText(_ status: ScreenSaverPublisher.Status) -> Text {
            if let error = status.error {
                switch (error as? CocoaError)?.code {
                case .fileWriteOutOfSpace:
                    return Text("There isn’t enough space to save screen saver artwork.")
                case .fileWriteNoPermission, .fileReadNoPermission:
                    return Text("Give AniShelf access to your Pictures folder to update the artwork.")
                default:
                    return Text("Couldn’t update screen saver artwork.")
                }
            }

            if !publisher.settings.isEnabled {
                return status.isPublishing
                    ? Text("Removing artwork…")
                    : Text("Artwork updates start when you install the screen saver.")
            }
            if status.isPublishing || status.lastPublication == nil {
                let total = publisher.draft.entries.count
                let prepared = min(status.availableCount, total)
                return prepared > 0
                    ? Text("Preparing artwork… \(prepared) of \(total)")
                    : Text("Preparing artwork…")
            }
            if status.failedPosterCount > 0 {
                return Text("\(status.failedPosterCount) posters couldn’t be loaded")
            }
            if status.hasFailedArtwork {
                return Text("Couldn’t update screen saver artwork.")
            }

            let missing = status.unavailableImageCount
            if status.availableCount == 0 {
                return missing > 0 ? Text("Up to date · \(missing) without artwork") : Text("Up to date")
            }
            let posters = Text("\(status.availableCount) posters")
            return missing > 0
                ? Text("Up to date · \(posters) · \(missing) without artwork")
                : Text("Up to date · \(posters)")
        }
    }

    fileprivate struct ScreenSaverPreviewSection: View {
        let publisher: ScreenSaverPublisher

        var body: some View {
            Section("Preview") {
                HStack(spacing: 24) {
                    ScreenSaverPreviewSurface(draft: publisher.draft)
                    ScreenSaverOptions(publisher: publisher)
                }
                .padding(.vertical, 4)
            }
        }
    }

    fileprivate struct ScreenSaverPreviewSurface: View {
        let draft: ScreenSaverSnapshotDraft
        @State private var aspectRatio = Self.mainScreenAspectRatio

        var body: some View {
            ScreenSaverPreviewView(draft: draft)
                .accessibilityLabel("Screen saver preview")
                .aspectRatio(aspectRatio, contentMode: .fit)
                .frame(width: min(300, 205 * aspectRatio))
                .clipShape(.rect(cornerRadius: 8))
                .onReceive(
                    NotificationCenter.default.publisher(for: NSApplication.didChangeScreenParametersNotification)
                ) { _ in
                    aspectRatio = Self.mainScreenAspectRatio
                }
        }

        private static var mainScreenAspectRatio: CGFloat {
            guard let size = NSScreen.screens.first?.frame.size, size.height > 0 else { return 16.0 / 9 }
            return size.width / size.height
        }
    }

    fileprivate struct ScreenSaverOptions: View {
        @Bindable var publisher: ScreenSaverPublisher
        private static let intervals: [TimeInterval] = [5, 8, 12, 20, 30, 60]

        private var showsSlideOptions: Bool {
            publisher.settings.layout != .coverWall
                || publisher.draft.entries.lazy.filter { $0.poster != nil }.prefix(4).count < 4
        }

        var body: some View {
            VStack(spacing: 12) {
                Picker("Show", selection: $publisher.settings.scope) {
                    ForEach(ScreenSaverSettings.Scope.allCases, id: \.self) { scope in
                        Text(scope.title).tag(scope)
                    }
                }
                Picker("Layout", selection: $publisher.settings.layout) {
                    ForEach(ScreenSaverManifest.Layout.allCases, id: \.self) { layout in
                        Text(layout.title).tag(layout)
                    }
                }
                if showsSlideOptions {
                    LabeledContent("Show Titles") {
                        Toggle("Show Titles", isOn: $publisher.settings.showsTitles)
                            .labelsHidden()
                            .toggleStyle(.switch)
                            .controlSize(.small)
                            .accessibilityIdentifier("screenSaverShowTitles")
                    }
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
            .frame(maxWidth: .infinity)
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
