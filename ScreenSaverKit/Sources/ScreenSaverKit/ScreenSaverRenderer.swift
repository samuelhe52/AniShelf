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
    /// The flowing colour field some draft layouts draw over; see `makeWashView()`.
    public let wash = ScreenSaverWash()
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
    private var stage: (any ScreenSaverStage)?
    private var draft: ScreenSaverDraft?
    private var timeScale: Double { max(draft?.timeScale ?? 1, 0.05) }

    /// The layer is clear: hosts put `makeWashView()` under it, and scenes with a ground of their
    /// own cover the wash.
    public init(message: @escaping (Notice) -> String) {
        self.message = message
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

    /// - Parameters:
    ///   - build: the saver's own build ID, checked against the snapshot's.
    ///   - draft: playback overrides from the Screen Saver Demo; the saver passes none.
    public func start(in directory: URL, build: String? = nil, draft: ScreenSaverDraft? = nil) {
        self.build = build
        self.draft = draft
        shuffleSeed = draft?.seed ?? UInt64.random(in: .min ... .max)
        play(in: directory)
    }

    private func play(in directory: URL) {
        stop()
        self.directory = directory
        guard size.width >= 1, size.height >= 1 else { return }
        let token = session.start()
        let loader = ScreenSaverSceneLoader(directory: directory, build: build, seed: shuffleSeed, draft: draft)
        layer.speed = Float(timeScale)
        wash.start(timeScale: timeScale)
        playback = Task { [weak self, size, scale, timeScale] in
            var snapshot = await loader.read()
            var scene = await loader.prepare(snapshot, cursor: .init(), size: size, scale: scale)
            var animated = false

            while !Task.isCancelled, self?.present(scene, token: token, animated: animated) == true {
                let publication = snapshot
                let cursor = scene.next
                async let buffered = loader.prepare(publication, cursor: cursor, size: size, scale: scale)
                do {
                    try await Task.sleep(for: .seconds(scene.duration / timeScale))
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
        wash.start(timeScale: 1)
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
        case .poster(let entry, _, _), .backdrop(let entry, _, _), .fusion(let entry, _, _, _),
            .editorial(let entry, _, _, _):
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
        wash.stop()
        playback?.cancel()
        playback = nil
        wall = nil
        stage = nil
        currentLayer = nil
        currentNotice = nil
        withoutImplicitAnimations {
            layer.sublayers?.forEach { $0.removeFromSuperlayer() }
        }
    }

    private func present(_ scene: ScreenSaverScene, token: UUID, animated: Bool) -> Bool {
        guard session.contains(token) else { return false }
        wash.setFlow(scene.washFlows, speed: scene.washSpeed)

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
                stage = nil
                currentNotice = nil
                replaceScene(with: wall.layer, animated: animated, overWash: false)
                return
            case .poster(let entry, let image, let mesh):
                wash.show(mesh)
                next = layouts.posterFocus(entry, poster: image, details: scene.details)
                currentNotice = nil
            case .backdrop(let entry, let image, let logo):
                next = layouts.backdrop(entry, image: image, logo: logo, details: scene.details)
                currentNotice = nil
            case .stage(let step):
                if let opened = step.makeStage(size: size, scale: scale, wash: wash) {
                    stage = opened
                    wall = nil
                    currentNotice = nil
                    replaceScene(with: opened.layer, animated: animated, overWash: opened.usesWash)
                } else {
                    stage?.apply(step)
                }
                return
            case .fusion(let entry, let poster, let ratio, let mesh):
                wash.show(mesh)
                next = layouts.coverFusion(entry, poster: poster, posterRatio: ratio, details: scene.details)
                currentNotice = nil
            case .editorial(let entry, let poster, let accent, let mesh):
                wash.show(mesh)
                next = layouts.editorialCover(entry, poster: poster, accent: accent, details: scene.details)
                currentNotice = nil
            case .notice(let notice):
                guard notice != currentNotice else { return }
                next = layouts.notice(message(notice))
                currentNotice = notice
            }
            wall = nil
            stage = nil
            let overWash =
                switch scene.content {
                case .poster, .fusion, .editorial: true
                default: false
                }
            replaceScene(with: next, animated: animated, overWash: overWash)
        }
        return true
    }

    /// - Parameter overWash: the new scene is clear where the wash shows.
    private func replaceScene(with next: CALayer, animated: Bool, overWash: Bool) {
        wash.setActive(overWash)
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
        if overWash {
            // A clear scene cannot cover the old one, which would vanish only when removed; fade it out too.
            let out = CABasicAnimation(keyPath: "opacity")
            out.fromValue = 1
            out.toValue = 0
            out.duration = fade.duration
            out.timingFunction = fade.timingFunction
            outgoing.opacity = 0
            outgoing.add(out, forKey: "crossfade")
        }
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
