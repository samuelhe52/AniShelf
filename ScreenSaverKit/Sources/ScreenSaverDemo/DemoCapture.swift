//
//  DemoCapture.swift
//  AniShelf
//
//  Created by Claude Code on behalf of Samuel He on 2026/11/21.
//

import AppKit
import CoreText
import ImageIO
import ScreenSaverArtworkAnalysis
import ScreenSaverKit
import UniformTypeIdentifiers

/// Writes still frames of each layout, for reviewing layouts without watching them.
///
/// Frames are
/// drawn by Core Animation at the given times, so they catch motion mid-flight.
///
/// Options: `--layouts deckFan,flipWall`, `--screens 0,3,5` (preset indices), `--times 1.5,4`
/// (seconds after start), `--speed 4`, `--entries 3`, `--seed 7`, `--dates watch` for Timeline's
/// watch dates, and `--snapshot <folder>` to use a particular snapshot.
/// `--backdrop-sides` reports placements or, with `--entry-ids <id,id>`, writes stills and
/// diagnostic variants. `--analyze-missing` runs the export detector in memory for older snapshots.
@MainActor
enum DemoCapture {
    static func run(output: URL) throws {
        if CommandLine.arguments.contains("--backdrop-sides") {
            try captureBackdropSides(into: output)
            return
        }
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

    private static var snapshotDirectory: URL? {
        argument("snapshot").map { URL(filePath: $0, directoryHint: .isDirectory) }
    }

    private static var screenSizes: [CGSize] {
        (option("screens")?.compactMap(Int.init) ?? [0, 3, 5]).compactMap {
            ScreenPreset.all.indices.contains($0) ? ScreenPreset.all[$0].size : nil
        }
    }

    private static func capture(into output: URL) async {
        try? FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
        let names = option("layouts")
        let layouts = ScreenSaverManifest.Layout.allCases.filter { names?.contains($0.rawValue) ?? true }
        let times = option("times")?.compactMap(Double.init) ?? [1.5, 4]
        let speed = option("speed")?.first.flatMap(Double.init) ?? 4

        for layout in layouts {
            for size in screenSizes {
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

    private enum CaptureError: Error {
        case snapshotUnavailable
        case noScreenPreset
        case backdropUnavailable(String)
        case cannotWrite(URL)
    }

    private static func captureBackdropSides(into output: URL) throws {
        let directory =
            snapshotDirectory
            ?? ScreenSaverSnapshotReader.snapshotDirectory(
                in: FileManager.default.homeDirectoryForCurrentUser)
        let reader = ScreenSaverSnapshotReader(directory: directory)
        guard case .ready(let manifest) = reader.read() else { throw CaptureError.snapshotUnavailable }
        let sizes = screenSizes
        guard !sizes.isEmpty else { throw CaptureError.noScreenPreset }
        let ids = option("entry-ids")
        let entries =
            try ids?.map { id in
                guard let entry = manifest.entries.first(where: { $0.id == id }) else {
                    throw CaptureError.backdropUnavailable(id)
                }
                return entry
            } ?? manifest.entries
        if ids != nil {
            try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
        }
        let analyzeMissing = CommandLine.arguments.contains("--analyze-missing")
        let details = Set(manifest.settings.details).intersection(ScreenSaverManifest.Detail.available(for: .backdrop))
        for entry in entries {
            guard let path = entry.backdrop else {
                if ids != nil { throw CaptureError.backdropUnavailable(entry.id) }
                continue
            }
            let logo = entry.logo.flatMap { reader.image(at: $0, maximumPixelSize: 1_024) }
            let regions =
                analyzeMissing && entry.backdropRegions == nil
                ? BackdropSaliency.regions(in: directory, backdrop: path) : nil
            for size in sizes {
                let pixelLimit = Int(ceil(min(max(size.width, size.height), 2_560)))
                guard let image = reader.image(at: path, maximumPixelSize: pixelLimit) else {
                    if ids != nil { throw CaptureError.backdropUnavailable(entry.id) }
                    continue
                }
                let layout = ScreenSaverLayouts(size: size, scale: 1)
                let result = layout.backdrop(
                    entry, image: image, logo: logo, details: details,
                    subjectAwareText: manifest.settings.backdropSubjectAwareText, regionsOverride: regions)
                let dimensions = "\(Int(size.width))x\(Int(size.height))"
                let placement = result.placement
                let confidence = placement.regions.map { String(format: "%.2f", $0.confidence) }.joined(separator: ",")
                print(
                    [
                        entry.id, dimensions, placement.side.rawValue,
                        String(format: "%.3f", placement.leftCoverage), String(format: "%.3f", placement.rightCoverage),
                        confidence, entry.title ?? ""
                    ].joined(separator: "\t"))
                guard ids != nil else { continue }
                let stem = entry.id.replacingOccurrences(of: ":", with: "-").replacingOccurrences(of: "/", with: "-")
                if placement.side == .right {
                    let before = layout.backdrop(
                        entry, image: image, logo: logo, details: details, regionsOverride: regions, forceLeft: true)
                    try writeBackdrop(
                        before.scene, placement: placement, drawnSide: .left, size: size,
                        output: output, stem: "\(stem)-\(dimensions)-before-left")
                }
                let suffix = placement.side == .right ? "after-right" : "stays-left"
                try writeBackdrop(
                    result.scene, placement: placement, drawnSide: placement.side, size: size,
                    output: output, stem: "\(stem)-\(dimensions)-\(suffix)")
            }
        }
    }

    private static func writeBackdrop(
        _ scene: CALayer, placement: BackdropPlacement, drawnSide: BackdropPlacement.Side,
        size: CGSize, output: URL, stem: String
    ) throws {
        func save(_ context: CGContext, suffix: String) throws {
            let url = output.appending(component: stem + suffix + ".png")
            guard let image = context.makeImage(),
                let destination = CGImageDestinationCreateWithURL(
                    url as CFURL, UTType.png.identifier as CFString, 1, nil)
            else { throw CaptureError.cannotWrite(url) }
            CGImageDestinationAddImage(destination, image, nil)
            guard CGImageDestinationFinalize(destination) else { throw CaptureError.cannotWrite(url) }
        }

        guard
            let context = CGContext(
                data: nil, width: Int(size.width), height: Int(size.height), bitsPerComponent: 8, bytesPerRow: 0,
                space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
        else { throw CaptureError.cannotWrite(output) }
        scene.render(in: context)
        try save(context, suffix: "")
        drawPlacement(placement, drawnSide: drawnSide, size: size, in: context)
        try save(context, suffix: "-debug")
    }

    private static func drawPlacement(
        _ placement: BackdropPlacement, drawnSide: BackdropPlacement.Side, size: CGSize, in context: CGContext
    ) {
        let cyan = CGColor(red: 0.26, green: 0.94, blue: 1, alpha: 1)
        let yellow = CGColor(red: 1, green: 0.86, blue: 0.23, alpha: 1)
        let pink = CGColor(red: 1, green: 0.45, blue: 0.7, alpha: 1)
        let fontSize = min(size.width, size.height) * 0.018

        func label(_ text: String, at point: CGPoint, color: CGColor) {
            let attributed = NSAttributedString(
                string: text,
                attributes: [
                    .font: NSFont.monospacedSystemFont(ofSize: fontSize, weight: .medium),
                    NSAttributedString.Key(kCTForegroundColorAttributeName as String): color
                ])
            let line = CTLineCreateWithAttributedString(attributed)
            let width = CTLineGetTypographicBounds(line, nil, nil, nil)
            let x = min(point.x, size.width - width - 16)
            context.setFillColor(CGColor(gray: 0, alpha: 0.85))
            context.fill(CGRect(x: x - 4, y: point.y - 5, width: width + 8, height: fontSize + 9))
            context.textPosition = CGPoint(x: x, y: point.y)
            CTLineDraw(line, context)
        }

        func outline(_ frame: CGRect, color: CGColor, lineWidth: CGFloat) {
            context.setStrokeColor(color)
            context.setLineWidth(lineWidth)
            context.stroke(frame)
        }

        for region in placement.regions {
            outline(region.frame.insetBy(dx: 1.5, dy: 1.5), color: cyan, lineWidth: 3)
            label(
                String(format: "%.2f", region.confidence),
                at: CGPoint(x: region.frame.minX + 7, y: region.frame.maxY - fontSize - 9), color: cyan)
        }
        if !placement.leftFrame.isEmpty {
            outline(placement.leftFrame, color: yellow, lineWidth: drawnSide == .left ? 5 : 3)
            outline(placement.rightFrame, color: pink, lineWidth: drawnSide == .right ? 5 : 3)
            label(
                "LEFT TEXT", at: CGPoint(x: placement.leftFrame.minX + 5, y: placement.leftFrame.minY - fontSize - 8),
                color: yellow)
            label(
                "RIGHT TEXT",
                at: CGPoint(x: placement.rightFrame.minX + 5, y: placement.rightFrame.minY - fontSize - 8),
                color: pink)
        }
        label(
            String(
                format: "Drawn: %@  |  Decision: %@  |  Left: %.0f%%  Right: %.0f%%",
                drawnSide.rawValue, placement.side.rawValue, placement.leftCoverage * 100, placement.rightCoverage * 100
            ),
            at: CGPoint(x: 16, y: size.height - fontSize - 14), color: CGColor(gray: 1, alpha: 1))
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
