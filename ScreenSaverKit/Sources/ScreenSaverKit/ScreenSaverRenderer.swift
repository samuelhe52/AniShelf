//
//  ScreenSaverRenderer.swift
//  AniShelf
//
//  Created by OpenAI Codex on behalf of Samuel He on 2026/11/20.
//

import Foundation
import QuartzCore

/// Renders the snapshot into a host view's Core Animation layer.
///
/// The owner supplies viewport changes and the view's start and stop events.
@MainActor
public final class ScreenSaverRenderer {
    public enum Notice: Equatable, Sendable { case empty, requiresUpdate }

    public struct Preview: Sendable {
        public let settings: ScreenSaverManifest.Settings
        public let entries: [ScreenSaverManifest.Entry]
        public let images: [String: CGImage]

        public init(
            settings: ScreenSaverManifest.Settings, entries: [ScreenSaverManifest.Entry], images: [String: CGImage]
        ) {
            self.settings = settings
            self.entries = entries
            self.images = images
        }
    }

    public let layer = CALayer()
    private let message: (Notice) -> String
    private var directory: URL?
    private var build: String?
    private var preview: Preview?
    private var previewEntryID: String?
    private var viewport = CGSize.zero
    private var size = CGSize.zero
    private var scale: CGFloat = 1
    private var sceneFit: CGFloat = 1
    private var session = ScreenSaverSession()
    private var playback: Task<Void, Never>?
    private var shuffleSeed: UInt64 = 0
    private var currentLayer: CALayer?
    private var currentNotice: Notice?
    private var wall: CoverWall?

    public init(message: @escaping (Notice) -> String) {
        self.message = message
        layer.backgroundColor = CGColor(gray: 0.025, alpha: 1)
        layer.masksToBounds = true
    }

    deinit {
        playback?.cancel()
    }

    /// Compose at the host size, or fit a larger layout into the host for a miniature preview.
    public func resize(to viewport: CGSize, scale backingScale: CGFloat, layoutSize: CGSize? = nil) {
        let size = layoutSize ?? viewport
        guard viewport.width.isFinite, viewport.height.isFinite, viewport.width >= 0, viewport.height >= 0,
            size.width.isFinite, size.height.isFinite, size.width >= 0, size.height >= 0,
            backingScale.isFinite, backingScale > 0
        else { return }
        let fit =
            if size.width > 0, size.height > 0, viewport.width > 0, viewport.height > 0 {
                min(viewport.width / size.width, viewport.height / size.height)
            } else {
                CGFloat(1)
            }
        let scale = backingScale * fit
        guard self.size != size || self.scale != scale || self.viewport != viewport else { return }
        self.viewport = viewport
        self.size = size
        self.scale = scale
        sceneFit = fit
        currentNotice = nil
        withoutImplicitAnimations {
            layer.frame = CGRect(origin: .zero, size: viewport)
            layer.contentsScale = backingScale
        }
        if let directory { play(in: directory) }
        if let preview { play(preview) }
    }

    /// - Parameter build: the saver's own build ID, checked against the snapshot's.
    public func start(in directory: URL, build: String? = nil) {
        self.build = build
        shuffleSeed = UInt64.random(in: .min ... .max)
        play(in: directory)
    }

    private func play(in directory: URL) {
        stop()
        self.directory = directory
        guard size.width >= 1, size.height >= 1 else { return }
        let token = session.start()
        let loader = ScreenSaverSceneLoader(directory: directory, build: build, seed: shuffleSeed)
        playback = Task { [weak self, size, scale] in
            var snapshot = await loader.read()
            var scene = await loader.prepare(snapshot, cursor: .init(), size: size, scale: scale)
            var animated = false

            while !Task.isCancelled, self?.present(scene, token: token, animated: animated) == true {
                let publication = snapshot
                let cursor = scene.next
                async let buffered = loader.prepare(publication, cursor: cursor, size: size, scale: scale)
                do {
                    try await Task.sleep(for: .seconds(scene.duration))
                } catch {
                    return
                }
                let latest = await loader.read()
                guard !Task.isCancelled else { return }

                animated = snapshot.isSamePublication(as: latest)
                if animated {
                    scene = await buffered
                } else {
                    scene = await loader.prepare(latest, cursor: .init(), size: size, scale: scale)
                }
                snapshot = latest
            }
        }
    }

    /// The preview owner supplies a stable entry order for the lifetime of its view.
    public func updatePreview(_ preview: Preview) {
        if directory != nil { stop() }
        self.preview = preview
        play(preview)
    }

    private func play(_ preview: Preview) {
        playback?.cancel()
        guard viewport.width >= 1, viewport.height >= 1, size.width >= 1, size.height >= 1 else { return }
        let token = session.start()
        let index = preview.entries.firstIndex { $0.id == previewEntryID } ?? 0
        playback = Task.detached { [weak self, size, scale] in
            var cursor = ScreenSaverScene.Cursor(startIndex: index)
            var animated = false
            while !Task.isCancelled {
                let scene = ScreenSaverSceneLoader.prepare(
                    entries: preview.entries, settings: preview.settings, cursor: cursor, size: size, scale: scale
                ) { path, _ in preview.images[path] }
                guard !Task.isCancelled,
                    await self?.presentPreview(scene, token: token, animated: animated) == true
                else { return }
                cursor = scene.next
                animated = true
                do {
                    try await Task.sleep(for: .seconds(scene.duration))
                } catch {
                    return
                }
            }
        }
    }

    private func presentPreview(_ scene: ScreenSaverScene, token: UUID, animated: Bool) -> Bool {
        guard present(scene, token: token, animated: animated) else { return false }
        switch scene.content {
        case .poster(let entry, _, _), .backdrop(let entry, _, _):
            previewEntryID = entry.id
        default:
            break
        }
        return true
    }

    public func stop() {
        directory = nil
        preview = nil
        previewEntryID = nil
        session.stop()
        playback?.cancel()
        playback = nil
        wall = nil
        currentLayer = nil
        currentNotice = nil
        withoutImplicitAnimations {
            layer.sublayers?.forEach { $0.removeFromSuperlayer() }
        }
    }

    private func present(_ scene: ScreenSaverScene, token: UUID, animated: Bool) -> Bool {
        guard session.contains(token) else { return false }

        withoutImplicitAnimations {
            let layouts = ScreenSaverLayouts(size: size, scale: scale)
            let next: CALayer
            switch scene.content {
            case .wallColumn(let images):
                wall?.advance(with: images)
                return
            case .wall(let grid, let images):
                let wall = CoverWall(grid: grid, images: images)
                self.wall = wall
                currentNotice = nil
                replaceScene(with: wall.layer, animated: animated)
                return
            case .poster(let entry, let image, let background):
                next = layouts.posterFocus(entry, poster: image, background: background, details: scene.details)
                currentNotice = nil
            case .backdrop(let entry, let image, let logo):
                next = layouts.backdrop(entry, image: image, logo: logo, details: scene.details)
                currentNotice = nil
            case .notice(let notice):
                guard notice != currentNotice else { return }
                next = layouts.notice(message(notice))
                currentNotice = notice
            }
            wall = nil
            replaceScene(with: next, animated: animated)
        }
        return true
    }

    private func replaceScene(with next: CALayer, animated: Bool) {
        let outgoing = currentLayer
        currentLayer = next
        next.position = CGPoint(x: layer.bounds.midX, y: layer.bounds.midY)
        next.setAffineTransform(CGAffineTransform(scaleX: sceneFit, y: sceneFit))
        layer.addSublayer(next)
        guard let outgoing else { return }
        guard animated else {
            outgoing.removeFromSuperlayer()
            return
        }

        let fade = CABasicAnimation(keyPath: "opacity")
        fade.fromValue = 0
        fade.toValue = 1
        fade.duration = 0.85
        fade.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
        CATransaction.setCompletionBlock {
            // This layer belongs only to the outgoing scene, even if the view has since restarted.
            outgoing.removeFromSuperlayer()
        }
        next.add(fade, forKey: "crossfade")
    }

    private func withoutImplicitAnimations(_ updates: () -> Void) {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        updates()
        CATransaction.commit()
    }
}
