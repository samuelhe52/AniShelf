//
//  ScreenSaverPreviewView.swift
//  AniShelf
//
//  Created by OpenAI Codex on behalf of Samuel He on 2026/11/20.
//

#if os(macOS)
    import AppKit
    import Kingfisher
    import ScreenSaverKit
    import SwiftUI

    struct ScreenSaverPreviewView: NSViewRepresentable {
        let draft: ScreenSaverSnapshotDraft
        let layoutSize: CGSize

        func makeNSView(context: Context) -> Surface {
            Surface(layoutSize: layoutSize)
        }

        func updateNSView(_ view: Surface, context: Context) {
            view.setLayoutSize(layoutSize)
            view.setDraft(draft)
        }

        static func dismantleNSView(_ view: Surface, coordinator: ()) {
            view.stop()
        }

        final class Surface: NSView {
            private struct Artwork: Equatable {
                var posters: [TMDbImage] = []
                var backdrops: [TMDbImage] = []
                var logos: [TMDbImage] = []
            }

            private let renderer = ScreenSaverRenderer { _ in String(localized: "No artwork to preview.") }
            private let shuffleSeed = UInt64.random(in: .min ... .max)
            private var draft: ScreenSaverSnapshotDraft?
            private var entries: [ScreenSaverSnapshotDraft.Entry] = []
            private var artwork = Artwork()
            private var images: [TMDbImage: CGImage] = [:]
            private var loading: Task<Void, Never>?
            private var layoutSize: CGSize

            init(layoutSize: CGSize) {
                self.layoutSize = layoutSize
                super.init(frame: .zero)
                renderer.install(in: self)
            }

            @available(*, unavailable)
            required init?(coder: NSCoder) {
                fatalError("init(coder:) has not been implemented")
            }

            func setLayoutSize(_ size: CGSize) {
                guard layoutSize != size else { return }
                layoutSize = size
                updateViewport()
            }

            func setDraft(_ draft: ScreenSaverSnapshotDraft) {
                guard self.draft != draft else { return }
                let entriesChanged = self.draft?.entries != draft.entries
                self.draft = draft
                if entriesChanged {
                    // Rank by identity so scope changes retain the relative order of surviving entries.
                    entries = Array(
                        draft.entries.filter { $0.previewPoster != nil }
                            .map { (entry: $0, rank: rank($0.id)) }
                            .sorted { ($0.rank, $0.entry.id) < ($1.rank, $1.entry.id) }
                            .prefix(24)
                            .map { $0.entry }
                    )
                }
                refresh()
            }

            func stop() {
                loading?.cancel()
                loading = nil
                artwork = Artwork()
                renderer.stop()
            }

            override func viewDidMoveToWindow() {
                super.viewDidMoveToWindow()
                guard window != nil else {
                    stop()
                    return
                }
                updateViewport()
                refresh()
            }

            override func viewDidChangeBackingProperties() {
                super.viewDidChangeBackingProperties()
                updateViewport()
            }

            override func layout() {
                super.layout()
                updateViewport()
            }

            private func updateViewport() {
                renderer.resize(to: bounds.size, scale: window?.backingScaleFactor ?? 1, layoutSize: layoutSize)
            }

            private func refresh() {
                guard window != nil else { return }
                render()
                let next = Artwork(
                    posters: unique(entries.compactMap(\.previewPoster)),
                    backdrops: unique(entries.compactMap(\.previewBackdrop)),
                    logos: unique(entries.compactMap { $0.previewBackdrop == nil ? nil : $0.logo })
                )
                guard next != artwork else { return }
                artwork = next
                loading?.cancel()
                let wanted = Set(next.posters + next.backdrops + next.logos)
                images = images.filter { wanted.contains($0.key) }
                loading = Task { [weak self] in
                    await self?.load(next.posters)
                    await self?.load(next.backdrops + next.logos)
                }
            }

            private func load(_ artwork: [TMDbImage]) async {
                let clock = ContinuousClock()
                var renderedAt: ContinuousClock.Instant?
                var remaining = artwork.filter { images[$0] == nil }.makeIterator()
                await withTaskGroup(of: (TMDbImage, CGImage?).self) { group in
                    func enqueue(_ image: TMDbImage) {
                        group.addTask {
                            // Match the library's display cache. Only the small preview sample may fetch uncached art.
                            let result = try? await KingfisherManager.shared.retrieveImage(
                                with: image.url, options: [.processor(image.processor), .scaleFactor(1)]
                            )
                            return (image, result?.image.exportCGImage)
                        }
                    }
                    for _ in 0..<4 {
                        guard !Task.isCancelled, let image = remaining.next() else { break }
                        enqueue(image)
                    }
                    while let (image, bitmap) = await group.next() {
                        guard !Task.isCancelled else { break }
                        if let bitmap {
                            images[image] = bitmap
                            let now = clock.now
                            if renderedAt.map({ $0.duration(to: now) >= .milliseconds(120) }) ?? true {
                                renderedAt = now
                                render()
                            }
                        }
                        if let image = remaining.next() { enqueue(image) }
                    }
                }
                if !Task.isCancelled, renderedAt != nil { render() }
            }

            private func render() {
                guard let draft else { return }
                var bitmaps: [String: CGImage] = [:]
                func add(_ image: TMDbImage?) -> String? {
                    guard let image, let bitmap = images[image] else { return nil }
                    let key = image.url.absoluteString
                    bitmaps[key] = bitmap
                    return key
                }
                let ready: [ScreenSaverManifest.Entry] = entries.compactMap { entry in
                    guard let poster = add(entry.previewPoster), let bitmap = bitmaps[poster] else { return nil }
                    return entry.manifestEntry(
                        poster: poster, posterPixelSize: .init(width: bitmap.width, height: bitmap.height),
                        backdrop: add(entry.previewBackdrop), logo: add(entry.logo))
                }
                renderer.updatePreview(.init(settings: draft.settings, entries: ready, images: bitmaps))
            }

            private func unique(_ sources: [TMDbImage]) -> [TMDbImage] {
                var seen: Set<TMDbImage> = []
                return sources.filter { seen.insert($0).inserted }
            }

            private func rank(_ id: String) -> UInt64 {
                var hasher = Hasher()
                hasher.combine(shuffleSeed)
                hasher.combine(id)
                return UInt64(bitPattern: Int64(hasher.finalize()))
            }
        }
    }
#endif
