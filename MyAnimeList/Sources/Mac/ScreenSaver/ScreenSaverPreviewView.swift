//
//  ScreenSaverPreviewView.swift
//  AniShelf
//
//  Created by OpenAI Codex on behalf of Samuel He on 2026/11/20.
//

#if os(macOS)
    import AppKit
    import ScreenSaverKit
    import SwiftUI

    struct ScreenSaverPreviewView: NSViewRepresentable {
        let directory: URL
        let generation: UUID?

        func makeNSView(context: Context) -> Surface {
            Surface()
        }

        func updateNSView(_ view: Surface, context: Context) {
            view.setSnapshot(directory: directory, generation: generation)
        }

        static func dismantleNSView(_ view: Surface, coordinator: ()) {
            view.setSnapshot(directory: nil, generation: nil)
        }

        final class Surface: NSView {
            private let renderer = ScreenSaverRenderer { notice in
                switch notice {
                case .empty: String(localized: "No artwork to preview.")
                case .requiresUpdate: String(localized: "This snapshot needs a newer version of AniShelf.")
                }
            }
            private var directory: URL?
            private var generation: UUID?

            init() {
                super.init(frame: .zero)
                layer = renderer.layer
                wantsLayer = true
            }

            @available(*, unavailable)
            required init?(coder: NSCoder) {
                fatalError("init(coder:) has not been implemented")
            }

            func setSnapshot(directory: URL?, generation: UUID?) {
                guard self.directory != directory || self.generation != generation else { return }
                self.directory = directory
                self.generation = generation
                updatePlayback()
            }

            override func viewDidMoveToWindow() {
                super.viewDidMoveToWindow()
                updatePlayback()
            }

            override func viewDidChangeBackingProperties() {
                super.viewDidChangeBackingProperties()
                updateViewport()
            }

            override func layout() {
                super.layout()
                updateViewport()
            }

            private func updatePlayback() {
                guard window != nil, let directory else {
                    renderer.stop()
                    return
                }
                updateViewport()
                renderer.start(in: directory)
            }

            private func updateViewport() {
                renderer.resize(to: bounds.size, scale: window?.backingScaleFactor ?? 1)
            }
        }
    }
#endif
