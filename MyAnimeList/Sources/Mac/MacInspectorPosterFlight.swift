//
//  MacInspectorPosterFlight.swift
//  AniShelf
//
//  Created by Claude Code on behalf of samuelhe52 on 2026/10/17.
//

#if os(macOS)
    import SwiftUI

    /// Flies the entry detail's poster into the batch panel's stack when a single selection
    /// grows into a batch.
    ///
    /// The inspector swaps the two panes instantly; only this poster, drawn above them, moves.
    /// A cross-fade of the panes would draw their translucent fills flat dark, and a matched
    /// geometry effect does not reach across the detail's navigation stack and the panel's form.
    @Observable
    @MainActor
    final class MacInspectorPosterFlight {
        struct Flight: Identifiable {
            let id = UUID()
            let posterURL: URL?
            let source: CGRect
            let destination: CGRect
            let landed: () -> Void
        }

        /// The detail header's poster in global coordinates, while a detail shows.
        var sourceFrame: CGRect?
        /// The inspector in global coordinates.
        var bounds: CGRect = .zero
        private(set) var current: Flight?

        /// Flies a poster from the detail header to `destination`, in global coordinates, and
        /// calls `landed` when it arrives.
        ///
        /// Without a visible detail poster it lands at once.
        func fly(posterURL: URL?, to destination: CGRect, landed: @escaping () -> Void) {
            guard let source = sourceFrame, source.intersects(bounds) else {
                landed()
                return
            }
            sourceFrame = nil
            current = Flight(posterURL: posterURL, source: source, destination: destination, landed: landed)
        }

        /// Drops a flight whose batch ended before it landed.
        func cancel() {
            current = nil
        }

        fileprivate func finish(_ flight: Flight) {
            guard current?.id == flight.id else { return }
            current = nil
            flight.landed()
        }
    }

    extension EnvironmentValues {
        @Entry var macInspectorPosterFlight: MacInspectorPosterFlight?
    }

    /// Draws the poster in flight above the inspector's content.
    struct MacInspectorPosterFlightOverlay: View {
        let posterFlight: MacInspectorPosterFlight

        var body: some View {
            if let flight = posterFlight.current {
                FlyingPoster(flight: flight, origin: posterFlight.bounds.origin) {
                    posterFlight.finish(flight)
                }
                .id(flight.id)
                .allowsHitTesting(false)
            }
        }
    }

    fileprivate struct FlyingPoster: View {
        let flight: MacInspectorPosterFlight.Flight
        let origin: CGPoint
        let onLanded: () -> Void
        @State private var hasLanded = false

        var body: some View {
            let frame = hasLanded ? flight.destination : flight.source
            // Matches the stack's front poster, which the detail header's poster also matches.
            KFImageView(url: flight.posterURL, targetWidth: 360, diskCacheExpiration: .longTerm)
                .scaledToFill()
                .frame(width: frame.width, height: frame.height)
                .background(.fill.tertiary)
                .clipShape(.rect(cornerRadius: 8, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .stroke(.separator, lineWidth: 0.5)
                }
                .shadow(color: .black.opacity(0.24), radius: 6, y: 3)
                .position(x: frame.midX - origin.x, y: frame.midY - origin.y)
                .onAppear {
                    withAnimation(.snappy(duration: 0.35)) {
                        hasLanded = true
                    } completion: {
                        onLanded()
                    }
                }
        }
    }
#endif
