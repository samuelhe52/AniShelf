//
//  DemoViews.swift
//  AniShelf
//
//  Created by Claude Code on behalf of Samuel He on 2026/11/21.
//

import AppKit
import ScreenSaverKit
import SwiftUI

struct DemoApp: App {
    @State private var model = DemoModel()

    init() {
        // A SwiftPM executable starts as a background process; make it a regular app with a Dock icon.
        NSApplication.shared.setActivationPolicy(.regular)
        DispatchQueue.main.async { NSApp.activate() }
    }

    var body: some Scene {
        Window("Screen Saver Demo", id: "demo") {
            DemoWindow(model: model)
                .frame(minWidth: 960, minHeight: 620)
        }
        .defaultSize(width: 1440, height: 860)

        // The current configuration at the window's real size; Control-Command-F makes it full screen.
        Window("Stage", id: "stage") {
            RendererView(configuration: model.configuration, layoutSize: nil)
                .ignoresSafeArea()
                .frame(minWidth: 480, minHeight: 300)
        }
        .defaultSize(width: 1512, height: 982)
    }
}

struct DemoWindow: View {
    @Bindable var model: DemoModel
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        HSplitView {
            DemoSidebar(model: model)
                .frame(minWidth: 280, idealWidth: 300, maxWidth: 360)
            VStack(spacing: 8) {
                GeometryReader { proxy in
                    let fitted = fittedSize(in: proxy.size)
                    RendererView(configuration: model.configuration, layoutSize: model.preset.size)
                        .frame(width: fitted.width, height: fitted.height)
                        .clipShape(.rect(cornerRadius: 6))
                        .shadow(radius: 8)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
                Text(caption)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding(16)
            .frame(minWidth: 480)
            .background(Color(white: 0.12))
        }
        .toolbar {
            ToolbarItemGroup {
                Button("Reshuffle", systemImage: "shuffle") { model.reshuffle() }
                    .help("Play other entries, in another order")
                Button("Open Stage", systemImage: "rectangle.on.rectangle") { openWindow(id: "stage") }
                    .help("Play at real size in a window that can go full screen")
            }
        }
    }

    private var caption: String {
        let size = model.preset.size.map { "\(Int($0.width)) × \(Int($0.height)) pt, scaled to fit" } ?? "real size"
        return "\(model.layout.title) · \(size)"
    }

    private func fittedSize(in available: CGSize) -> CGSize {
        guard let size = model.preset.size else { return available }
        let fit = min(available.width / size.width, available.height / size.height)
        return CGSize(width: floor(size.width * fit), height: floor(size.height * fit))
    }
}

struct DemoSidebar: View {
    @Bindable var model: DemoModel

    var body: some View {
        Form {
            Section("Snapshot") {
                LabeledContent("Folder") {
                    Text(
                        model.directory.path(percentEncoded: false).replacingOccurrences(
                            of: FileManager.default.homeDirectoryForCurrentUser.path(percentEncoded: false), with: "~/")
                    )
                    .lineLimit(2)
                    .truncationMode(.middle)
                    .textSelection(.enabled)
                }
                LabeledContent("Entries", value: model.entryCount.map { "\($0)" } ?? "none found")
                Button("Choose Folder…", action: chooseFolder)
            }

            Section("Layout") {
                Picker("Layout", selection: $model.layout) {
                    Section("Drafts") {
                        ForEach(DemoLayout.draftCases) { Text($0.title).tag($0) }
                    }
                    Section("Shipping") {
                        ForEach(DemoLayout.shippedCases) { Text($0.title).tag($0) }
                    }
                }
                Picker("Screen", selection: $model.preset) {
                    ForEach(ScreenPreset.all) { Text($0.name).tag($0) }
                }
                Picker("Entries", selection: $model.entryLimit) {
                    Text("All").tag(Int?.none)
                    ForEach(DemoModel.entryLimits, id: \.self) { Text("\($0)").tag(Int?.some($0)) }
                }
            }

            Section("Options") {
                if model.layout.usesWash {
                    Toggle("Flowing Wash", isOn: $model.washFlows)
                }
                if model.layout.usesInterval {
                    slider("Interval", value: $model.interval, in: 2...30, unit: "s")
                }
                if model.layout.usesRows {
                    Stepper(
                        "Rows: \(model.rows)", value: $model.rows,
                        in: ScreenSaverManifest.Settings.coverWallRowRange)
                }
                switch model.layout {
                case .draft(.deckFan):
                    Stepper("Cards: \(model.deckDepth)", value: $model.deckDepth, in: 2...9)
                case .draft(.deckPile):
                    Stepper("Cards: \(model.pileDepth)", value: $model.pileDepth, in: 2...12)
                case .draft(.flipWall):
                    slider("Flip every", value: $model.flipDelay, in: 1...30, unit: "s")
                case .draft(.depthDrift):
                    slider("Posters per 10 s", value: $model.driftRate, in: 1...20, unit: "")
                case .draft(.seasonTimeline):
                    slider("Hold", value: $model.timelineHold, in: 2...30, unit: "s")
                default:
                    EmptyView()
                }
            }

            if model.layout.usesDetails {
                Section("Details") {
                    ForEach(ScreenSaverManifest.Detail.allCases, id: \.self) { detail in
                        Toggle(detail.rawValue, isOn: binding(for: detail))
                    }
                }
            }
        }
        .formStyle(.grouped)
    }

    private func slider(_ title: String, value: Binding<Double>, in range: ClosedRange<Double>, unit: String)
        -> some View
    {
        LabeledContent(title) {
            HStack {
                Slider(value: value, in: range, step: 1).labelsHidden()
                Text("\(Int(value.wrappedValue))\(unit)").monospacedDigit().frame(width: 36, alignment: .trailing)
            }
        }
    }

    private func binding(for detail: ScreenSaverManifest.Detail) -> Binding<Bool> {
        Binding(
            get: { model.details.contains(detail) },
            set: { isOn in
                if isOn { model.details.insert(detail) } else { model.details.remove(detail) }
            })
    }

    private func chooseFolder() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.directoryURL = model.directory
        panel.message = "Choose a folder with a screen saver manifest.json and images."
        if panel.runModal() == .OK, let url = panel.url { model.directory = url }
    }
}

struct RendererView: NSViewRepresentable {
    let configuration: DemoConfiguration
    let layoutSize: CGSize?

    func makeNSView(context: Context) -> Surface { Surface() }

    func updateNSView(_ view: Surface, context: Context) {
        view.update(configuration, layoutSize: layoutSize)
    }

    static func dismantleNSView(_ view: Surface, coordinator: ()) {
        view.renderer.stop()
    }

    final class Surface: NSView {
        let renderer = ScreenSaverRenderer { notice in
            switch notice {
            case .empty:
                "No snapshot in this folder. Turn on the screen saver in AniShelf Settings, or choose a folder."
            case .requiresUpdate: "This snapshot is from a newer AniShelf."
            }
        }
        private var configuration: DemoConfiguration?
        private var layoutSize: CGSize?

        init() {
            super.init(frame: .zero)
            renderer.install(in: self)
        }

        @available(*, unavailable)
        required init?(coder: NSCoder) { fatalError() }

        func update(_ configuration: DemoConfiguration, layoutSize: CGSize?) {
            let resized = self.layoutSize != layoutSize
            self.layoutSize = layoutSize
            if resized { updateViewport() }
            guard self.configuration != configuration else { return }
            self.configuration = configuration
            renderer.start(in: configuration.directory, draft: configuration.draft)
        }

        override func layout() {
            super.layout()
            for subview in subviews { subview.frame = bounds }
            updateViewport()
        }

        override func viewDidChangeBackingProperties() {
            super.viewDidChangeBackingProperties()
            updateViewport()
        }

        private func updateViewport() {
            renderer.resize(
                to: bounds.size, scale: window?.backingScaleFactor ?? 2, layoutSize: layoutSize)
        }
    }
}
