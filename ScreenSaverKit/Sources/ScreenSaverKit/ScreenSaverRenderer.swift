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

    public let layer = CALayer()
    private let message: (Notice) -> String
    private var directory: URL?
    private var size = CGSize.zero
    private var scale: CGFloat = 1
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

    public func resize(to size: CGSize, scale: CGFloat) {
        guard size.width.isFinite, size.height.isFinite, size.width >= 0, size.height >= 0,
            scale.isFinite, scale > 0, self.size != size || self.scale != scale
        else { return }
        self.size = size
        self.scale = scale
        withoutImplicitAnimations {
            layer.frame = CGRect(origin: .zero, size: size)
            layer.contentsScale = scale
        }
        if let directory { play(in: directory) }
    }

    public func start(in directory: URL) {
        shuffleSeed = UInt64.random(in: .min ... .max)
        play(in: directory)
    }

    private func play(in directory: URL) {
        stop()
        self.directory = directory
        guard size.width >= 1, size.height >= 1 else { return }
        let token = session.start()
        let loader = ScreenSaverSceneLoader(directory: directory, seed: shuffleSeed)
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

    public func stop() {
        directory = nil
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
            case .poster(let entry, let image, let wash):
                next = layouts.posterFocus(entry, poster: image, wash: wash, showsTitles: scene.showsTitles)
                currentNotice = nil
            case .hero(let entry, let backdrop, let logo):
                next = layouts.heroStill(entry, backdrop: backdrop, logo: logo, showsTitles: scene.showsTitles)
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
