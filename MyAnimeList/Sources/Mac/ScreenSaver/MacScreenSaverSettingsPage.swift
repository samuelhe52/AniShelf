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
                ScreenSaverUninstallSection(publisher: publisher)
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
            Section {
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
            } header: {
                Text("Setup")
            } footer: {
                Text(
                    "After installation, AniShelf updates the screen saver automatically when you change the options below."
                )
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
            let bundle = ScreenSaverPublisher.embeddedSaverURL
            if NSWorkspace.shared.open(bundle) {
                publisher.settings.isEnabled = true
            } else {
                launchError = "Couldn’t Open Screen Saver"
            }
        }

        private func openSettings() {
            guard NSWorkspace.shared.open(ScreenSaverSettingsLink.wallpaper) else {
                launchError = "Couldn’t Open System Settings"
                return
            }
        }

    }

    fileprivate struct ScreenSaverUninstallSection: View {
        let publisher: ScreenSaverPublisher
        @State private var showsRemovalSteps = false

        var body: some View {
            Section {
                LabeledContent {
                    Button("Uninstall Screen Saver…") {
                        // The sandbox can't delete the installed saver, but System Settings can.
                        publisher.settings.isEnabled = false
                        showsRemovalSteps = true
                    }
                } label: {
                    Text("Uninstalling makes the AniShelf option disappear in the screen saver settings.")
                }
            }
            .alert("Remove AniShelf from Screen Savers", isPresented: $showsRemovalSteps) {
                Button("Open Wallpaper Settings") { NSWorkspace.shared.open(ScreenSaverSettingsLink.wallpaper) }
                Button("Done", role: .cancel) {}
            } message: {
                Text(
                    "AniShelf stopped updating the screen saver and deleted its artwork. To finish, click Screen Saver… in Wallpaper settings, Control-click AniShelf, then choose Delete “AniShelf”."
                )
            }
        }
    }

    /// macOS 27 keeps screen savers in the Wallpaper pane; there is no separate Screen Saver pane.
    fileprivate enum ScreenSaverSettingsLink {
        static let wallpaper = URL(string: "x-apple.systempreferences:com.apple.Wallpaper-Settings.extension")!
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
            if status.isPublishing || !status.hasPublished {
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
        @Environment(\.layoutDirection) private var layoutDirection
        @State private var isCustomizeExpanded = false

        var body: some View {
            let controls = publisher.optionsLayout.controls
            Section("Preview") {
                HStack(spacing: 24) {
                    ScreenSaverPreviewSurface(draft: publisher.draft)
                    ScreenSaverOptions(publisher: publisher)
                }
                .padding(.vertical, 4)
                if !controls.isEmpty {
                    Button {
                        withAnimation(.smooth(duration: 0.25)) {
                            isCustomizeExpanded.toggle()
                        }
                    } label: {
                        HStack {
                            Text("Customize")
                            Spacer()
                            Image(systemName: "chevron.down")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(.secondary)
                                .rotationEffect(
                                    .degrees(isCustomizeExpanded ? 0 : (layoutDirection == .rightToLeft ? 90 : -90))
                                )
                                .accessibilityHidden(true)
                        }
                        .frame(minHeight: 36)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityValue(isCustomizeExpanded ? Text("Expanded") : Text("Collapsed"))

                    if isCustomizeExpanded {
                        ForEach(controls, id: \.self) { control in
                            ScreenSaverLayoutControl(control: control, publisher: publisher)
                        }
                    }
                }
            }
            ScreenSaverDetailsSection(publisher: publisher)
        }
    }

    fileprivate struct ScreenSaverDetailsSection: View {
        @Bindable var publisher: ScreenSaverPublisher
        @AppStorage(.libraryScoringEnabled) private var scoringEnabled = true

        var body: some View {
            let layout = publisher.optionsLayout
            // With scoring turned off in the app, the user's score is not offered or drawn.
            let details = ScreenSaverManifest.Detail.available(for: layout).filter {
                scoringEnabled || $0 != .userScore
            }
            if !details.isEmpty {
                Section("Details") {
                    ForEach(details, id: \.self) { detail in
                        Toggle(detail.title, isOn: binding(for: detail, in: layout))
                    }
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
        @Environment(LibraryStore.self) private var library
        @State private var lastDeckLayout: ScreenSaverManifest.Layout = .deckFan
        @State private var lastPosterLayout: ScreenSaverManifest.Layout = .posterFocus
        @State private var lastWallLayout: ScreenSaverManifest.Layout = .coverWall

        /// Custom categories, listed when categories are on. The selected category stays listed
        /// when categories are later turned off or the category is deleted, so the picker keeps
        /// a valid selection.
        private var categoryScopes: [(scope: ScreenSaverSettings.Scope, name: String)] {
            var items =
                library.categoriesEnabled
                ? library.categories.map { (scope: ScreenSaverSettings.Scope.category($0.id), name: $0.name) } : []
            if case .category(let id) = publisher.settings.scope,
                !items.contains(where: { $0.scope == publisher.settings.scope })
            {
                let name = library.categories.first { $0.id == id }?.name
                items.append((publisher.settings.scope, name ?? String(localized: "Deleted Category")))
            }
            return items
        }

        var body: some View {
            VStack(spacing: 12) {
                Picker("Show", selection: $publisher.settings.scope) {
                    ForEach(ScreenSaverSettings.Scope.builtIn, id: \.self) { scope in
                        Text(scope.title).tag(scope)
                    }
                    if !categoryScopes.isEmpty {
                        Divider()
                        ForEach(categoryScopes, id: \.scope) { item in
                            Text(item.name).tag(item.scope)
                        }
                    }
                }
                Picker("Entry Type", selection: $publisher.settings.entryType) {
                    ForEach(ScreenSaverSettings.EntryType.allCases, id: \.self) { type in
                        Text(type.title).tag(type)
                    }
                }
                Picker("Layout", selection: layoutSelection) {
                    ForEach(
                        ScreenSaverManifest.Layout.allCases.filter {
                            $0 != .deckPile && $0 != .coverFusion && $0 != .flipWall
                        },
                        id: \.self
                    ) { layout in
                        Text(layout.title).tag(layout)
                    }
                }
                if publisher.settings.layout == .deckFan || publisher.settings.layout == .deckPile {
                    Picker("Mode", selection: $publisher.settings.layout) {
                        Text("Fan").tag(ScreenSaverManifest.Layout.deckFan)
                        Text("Pile").tag(ScreenSaverManifest.Layout.deckPile)
                    }
                    .pickerStyle(.segmented)
                }
                if publisher.settings.layout == .posterFocus || publisher.settings.layout == .coverFusion {
                    Picker("Mode", selection: $publisher.settings.layout) {
                        Text("Focus").tag(ScreenSaverManifest.Layout.posterFocus)
                        Text("Fusion").tag(ScreenSaverManifest.Layout.coverFusion)
                    }
                    .pickerStyle(.segmented)
                }
                if publisher.settings.layout == .coverWall || publisher.settings.layout == .flipWall {
                    Picker("Mode", selection: $publisher.settings.layout) {
                        Text("Cover").tag(ScreenSaverManifest.Layout.coverWall)
                        Text("Flip").tag(ScreenSaverManifest.Layout.flipWall)
                    }
                    .pickerStyle(.segmented)
                }
            }
            .onAppear { rememberLayout(publisher.settings.layout) }
            .onChange(of: publisher.settings.layout) { _, layout in
                rememberLayout(layout)
            }
            .frame(maxWidth: .infinity)
        }

        private var layoutSelection: Binding<ScreenSaverManifest.Layout> {
            Binding(
                get: {
                    switch publisher.settings.layout {
                    case .deckPile: .deckFan
                    case .coverFusion: .posterFocus
                    case .flipWall: .coverWall
                    default: publisher.settings.layout
                    }
                },
                set: { layout in
                    switch layout {
                    case .deckFan: publisher.settings.layout = lastDeckLayout
                    case .posterFocus: publisher.settings.layout = lastPosterLayout
                    case .coverWall: publisher.settings.layout = lastWallLayout
                    default: publisher.settings.layout = layout
                    }
                }
            )
        }

        private func rememberLayout(_ layout: ScreenSaverManifest.Layout) {
            switch layout {
            case .deckFan, .deckPile: lastDeckLayout = layout
            case .posterFocus, .coverFusion: lastPosterLayout = layout
            case .coverWall, .flipWall: lastWallLayout = layout
            default: break
            }
        }
    }

    fileprivate struct ScreenSaverLayoutControl: View {
        typealias Settings = ScreenSaverManifest.Settings

        let control: ScreenSaverManifest.Layout.Control
        @Bindable var publisher: ScreenSaverPublisher

        var body: some View {
            switch control {
            case .interval:
                ScreenSaverDurationSlider(
                    "Interval", value: $publisher.settings.interval, timing: .interval, controlWidth: 176)
            case .backdropSubjectAwareText:
                Toggle("Smart Text Placement", isOn: $publisher.settings.backdropSubjectAwareText)
            case .rows:
                integerSlider("Rows", value: $publisher.settings.coverWallRows, in: Settings.coverWallRowRange)
            case .flowingBackground:
                Toggle("Flowing Background", isOn: $publisher.settings.washFlows)
                if publisher.settings.washFlows {
                    washSpeedSlider
                }
            case .posterOverviewLines:
                ScreenSaverOverviewLinesSlider(value: $publisher.settings.posterOverviewLines, controlWidth: 176)
            case .deckDepth:
                integerSlider("Cards", value: $publisher.settings.deckDepth, in: Settings.deckDepthRange)
            case .pileDepth:
                integerSlider("Cards", value: $publisher.settings.pileDepth, in: Settings.deckDepthRange)
            case .flipDelay:
                ScreenSaverDurationSlider(
                    "Flip Delay", value: $publisher.settings.flipDelay, timing: .flipDelay, controlWidth: 176)
            case .driftRate:
                LabeledContent("Posters per 10 Seconds") {
                    HStack(spacing: 8) {
                        Slider(value: $publisher.settings.driftRate, in: Settings.driftRateRange, step: 1) {
                            Text("Posters per 10 Seconds")
                        }
                        .labelsHidden()
                        Text(publisher.settings.driftRate, format: .number)
                            .monospacedDigit()
                    }
                    .frame(width: 176)
                }
            case .timelineHold:
                ScreenSaverDurationSlider(
                    "Hold Duration", value: $publisher.settings.timelineHold, timing: .timelineHold, controlWidth: 176)
            case .timelineDateSource:
                Picker("Date Source", selection: $publisher.settings.timelineDateSource) {
                    Text("Date On Air").tag(ScreenSaverManifest.TimelineDateSource.airDate)
                    Text("Watch Dates").tag(ScreenSaverManifest.TimelineDateSource.watchDates)
                }
            case .timelineDatePrecision:
                Picker("Date Format", selection: $publisher.settings.timelineDatePrecision) {
                    Text("Year").tag(ScreenSaverManifest.TimelineDatePrecision.year)
                    Text("Year and Month").tag(ScreenSaverManifest.TimelineDatePrecision.yearAndMonth)
                    Text("Full Date").tag(ScreenSaverManifest.TimelineDatePrecision.fullDate)
                }
            }
        }

        /// Snaps to the offered speeds, one tick each.
        private var washSpeedSlider: some View {
            let speeds = ScreenSaverManifest.Settings.washSpeeds
            let step = Binding(
                get: { Double(speeds.firstIndex(of: publisher.settings.washSpeed) ?? speeds.firstIndex(of: 1) ?? 0) },
                set: { publisher.settings.washSpeed = speeds[min(max(Int($0.rounded()), 0), speeds.count - 1)] }
            )
            return LabeledContent("Flow Speed") {
                Slider(value: step, in: 0...Double(speeds.count - 1), step: 1) {
                    Text("Flow Speed")
                } minimumValueLabel: {
                    Image(systemName: "tortoise")
                        .accessibilityLabel("Slower")
                } maximumValueLabel: {
                    Image(systemName: "hare")
                        .accessibilityLabel("Faster")
                } tick: { value in
                    SliderTick(value)
                }
                .labelsHidden()
                .frame(width: 176)
            }
        }

        private func integerSlider(_ title: LocalizedStringKey, value: Binding<Int>, in range: ClosedRange<Int>)
            -> some View
        {
            let step = Binding(
                get: { Double(value.wrappedValue) },
                set: { value.wrappedValue = Int($0.rounded()) }
            )
            return LabeledContent(title) {
                HStack(spacing: 8) {
                    Slider(value: step, in: Double(range.lowerBound)...Double(range.upperBound), step: 1) {
                        Text(title)
                    } tick: { value in
                        SliderTick(value)
                    }
                    .labelsHidden()
                    Text(value.wrappedValue, format: .number)
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
            // Category scopes are listed by their names, not through this title.
            case .category: "Category"
            }
        }
    }

    extension ScreenSaverSettings.EntryType {
        fileprivate var title: LocalizedStringResource {
            switch self {
            case .all: "All"
            case .movies: "Movies"
            case .series: "Series"
            }
        }
    }

    extension ScreenSaverPublisher {
        fileprivate var optionsLayout: ScreenSaverManifest.Layout {
            let layout = settings.layout
            guard layout == .coverWall else { return layout }
            // Posters that failed to download leave the saver with fewer than the draft offers.
            let posters = draft.entries.count { $0.poster != nil } - status.failedPosterCount
            return layout.layout(forPosterCount: posters)
        }
    }

    extension ScreenSaverManifest.Detail {
        fileprivate var title: LocalizedStringResource {
            switch self {
            case .season: "Season"
            case .year: "Year"
            case .genres: "Genres"
            case .status: "Airing Status"
            case .score: "TMDb Score"
            case .watchStatus: "Watch Status"
            case .userScore: "Your Score"
            case .tagline: "Tagline"
            case .overview: "Overview"
            }
        }
    }

    extension ScreenSaverManifest.Layout {
        fileprivate var title: LocalizedStringResource {
            switch self {
            case .coverWall, .flipWall: "Wall"
            case .posterFocus, .coverFusion: "Poster"
            case .backdrop: "Backdrop"
            case .deckFan, .deckPile: "Deck"
            case .timeline: "Timeline"
            case .depthDrift: "Depth Drift"
            case .editorialCover: "Editorial Cover"
            }
        }
    }
#endif
