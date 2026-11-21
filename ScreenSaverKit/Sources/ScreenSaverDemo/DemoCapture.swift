//
//  DemoCapture.swift
//  AniShelf
//
//  Created by Claude Code on behalf of Samuel He on 2026/11/21.
//

import AppKit
import ImageIO
import ScreenSaverKit
import UniformTypeIdentifiers

/// Writes still frames of each layout, for reviewing layouts without watching them. Frames are
/// drawn by Core Animation at the given times, so they catch motion mid-flight.
///
/// Options: `--layouts deckFan,flipWall`, `--screens 0,3,5` (preset indices), `--times 1.5,4`
/// (seconds after start), `--speed 4`, `--entries 3`, `--seed 7`, `--dates watch` for Timeline's
/// watch dates, and `--snapshot <folder>` to use a particular snapshot.
@MainActor
enum DemoCapture {
    static func run(output: URL) {
        let app = NSApplication.shared
        app.setActivationPolicy(.prohibited)
        Task { @MainActor in
            await capture(into: output)
            exit(0)
        }
        app.run()
    }

    private static func argument(_ name: String) -> String? {
        let arguments = CommandLine.arguments
        guard let index = arguments.firstIndex(of: "--" + name), arguments.indices.contains(index + 1) else {
            return nil
        }
        return arguments[index + 1]
    }

    private static func option(_ name: String) -> [String]? {
        argument(name)?.split(separator: ",").map(String.init)
    }

    private static func capture(into output: URL) async {
        try? FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
        let names = option("layouts")
        let layouts = ScreenSaverManifest.Layout.allCases.filter { names?.contains($0.rawValue) ?? true }
        let snapshotDirectory = argument("snapshot").map { URL(filePath: $0, directoryHint: .isDirectory) }
        let screens = (option("screens")?.compactMap(Int.init) ?? [0, 3, 5]).compactMap {
            ScreenPreset.all.indices.contains($0) ? ScreenPreset.all[$0] : nil
        }
        let times = option("times")?.compactMap(Double.init) ?? [1.5, 4]
        let speed = option("speed")?.first.flatMap(Double.init) ?? 4

        for layout in layouts {
            for screen in screens {
                guard let size = screen.size else { continue }
                let model = DemoModel(directory: snapshotDirectory)
                model.layout = layout
                model.speed = speed
                model.seed = option("seed")?.first.flatMap(UInt64.init) ?? 7
                model.entryLimit = option("entries")?.first.flatMap(Int.init)
                if option("dates")?.first == "watch" { model.timelineDateSource = .watchDates }

                // A panel at half the layout size and the display's scale, at desktop level behind every
                // other window: the window server only draws windows on screen, Stage Manager leaves
                // panels alone, and nothing takes focus.
                let viewSize = CGSize(width: size.width / 2, height: size.height / 2)
                let panel = NSPanel(
                    contentRect: CGRect(origin: .zero, size: viewSize),
                    styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
                panel.level = NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.desktopWindow)))
                panel.collectionBehavior = [.stationary, .ignoresCycle, .canJoinAllSpaces]
                let view = RendererView.Surface()
                view.frame = CGRect(origin: .zero, size: viewSize)
                panel.contentView = view
                panel.orderFrontRegardless()
                view.update(model.configuration, layoutSize: size)

                var elapsed = 0.0
                for time in times {
                    try? await Task.sleep(for: .seconds(time - elapsed))
                    elapsed = time
                    let name = "\(layout.rawValue)-\(Int(size.width))x\(Int(size.height))-\(time.formatted()).png"
                    snapshot(panel, to: output.appending(component: name))
                }
                view.renderer.stop()
                panel.orderOut(nil)
            }
        }
    }

    /// The window server draws the panel exactly as it would on screen, 3D transforms included.
    private static func snapshot(_ window: NSWindow, to url: URL) {
        let process = Process()
        process.executableURL = URL(filePath: "/usr/sbin/screencapture")
        process.arguments = ["-x", "-o", "-l\(window.windowNumber)", url.path(percentEncoded: false)]
        try? process.run()
        process.waitUntilExit()
        print(url.lastPathComponent)
    }
}
