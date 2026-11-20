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
                LabeledContent {
                    Button("Open Wallpaper Settings", action: openSettings)
                } label: {
                    Text("2. Choose AniShelf")
                    Text("Click Screen Saver…, then choose AniShelf under Other at the bottom of the list.")
                }
                ScreenSaverArtworkStatus(publisher: publisher)
                if publisher.settings.isEnabled {
                    LabeledContent {
                        Button("Turn Off Screen Saver") {
                            publisher.settings.isEnabled = false
                        }
                    } label: {
                        Text(
                            "AniShelf stops updating the screen saver and deletes its saved posters. To use it again, click Install…."
                        )
                        .foregroundStyle(.secondary)
                    }
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
            if publisher.showsSlideOptions {
                ScreenSaverDetailsSection(publisher: publisher)
            }
        }
    }

    fileprivate struct ScreenSaverDetailsSection: View {
        @Bindable var publisher: ScreenSaverPublisher

        var body: some View {
            let layout = publisher.settings.layout
            Section {
                ForEach(ScreenSaverManifest.Detail.allCases, id: \.self) { detail in
                    Toggle(detail.title, isOn: binding(for: detail, in: layout))
                }
            } header: {
                Text("Details")
            } footer: {
                if layout == .backdrop {
                    Text("Title shows the logo when there is one.")
                }
            }
        }

        private func binding(for detail: ScreenSaverManifest.Detail, in layout: ScreenSaverManifest.Layout)
            -> Binding<Bool>
        {
            Binding(
                get: { publisher.settings.details(for: layout).contains(detail) },
                set: { publisher.settings.setDetail(detail, $0, for: layout) }
            )
        }
    }

    fileprivate struct ScreenSaverPreviewSurface: View {
        let draft: ScreenSaverSnapshotDraft
        @State private var screenSize = Self.mainScreenSize

        var body: some View {
            let aspectRatio = screenSize.width / screenSize.height
            ScreenSaverPreviewView(draft: draft, layoutSize: screenSize)
                .accessibilityLabel("Screen saver preview")
                .aspectRatio(aspectRatio, contentMode: .fit)
                .frame(width: min(300, 205 * aspectRatio))
                .clipShape(.rect(cornerRadius: 8))
                .onReceive(
                    NotificationCenter.default.publisher(for: NSApplication.didChangeScreenParametersNotification)
                ) { _ in
                    screenSize = Self.mainScreenSize
                }
        }

        private static var mainScreenSize: CGSize {
            guard let size = NSScreen.screens.first?.frame.size, size.width > 0, size.height > 0 else {
                return CGSize(width: 1920, height: 1080)
            }
            return size
        }
    }

    fileprivate struct ScreenSaverOptions: View {
        @Bindable var publisher: ScreenSaverPublisher
        private static let intervals: [TimeInterval] = [5, 8, 12, 20, 30, 60]

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
                if publisher.settings.layout == .coverWall {
                    coverWallRowsSlider
                }
                if publisher.showsSlideOptions {
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

        private var coverWallRowsSlider: some View {
            let range = ScreenSaverManifest.Settings.coverWallRowRange
            let rows = Binding(
                get: { Double(publisher.settings.coverWallRows) },
                set: { publisher.settings.coverWallRows = Int($0.rounded()) }
            )
            return LabeledContent("Rows") {
                HStack(spacing: 8) {
                    Slider(value: rows, in: Double(range.lowerBound)...Double(range.upperBound), step: 1) {
                        Text("Rows")
                    } tick: { value in
                        SliderTick(value)
                    }
                    .labelsHidden()
                    Text(publisher.settings.coverWallRows, format: .number)
                        .monospacedDigit()
                }
                .frame(width: 176)
            }
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

    extension ScreenSaverPublisher {
        /// Slide options apply to Poster Focus, Backdrop, and Cover Wall's fallback for fewer than 4 posters.
        fileprivate var showsSlideOptions: Bool {
            settings.layout != .coverWall || draft.entries.lazy.filter { $0.poster != nil }.prefix(4).count < 4
        }
    }

    extension ScreenSaverManifest.Detail {
        fileprivate var title: LocalizedStringResource {
            switch self {
            case .title: "Title"
            case .season: "Season"
            case .year: "Year"
            case .genres: "Genres"
            case .status: "Status"
            }
        }
    }

    extension ScreenSaverManifest.Layout {
        fileprivate var title: LocalizedStringResource {
            switch self {
            case .coverWall: "Cover Wall"
            case .posterFocus: "Poster Focus"
            case .backdrop: "Backdrop"
            }
        }
    }
#endif
