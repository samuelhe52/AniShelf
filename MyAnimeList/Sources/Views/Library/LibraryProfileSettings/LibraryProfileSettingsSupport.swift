//
//  LibraryProfileSettingsSupport.swift
//  MyAnimeList
//
//  Created by OpenAI Codex on 2026/5/3.
//

import DataProvider
import SwiftUI

struct LibraryProfileStats: Equatable {
    let totalCount: Int
    let watchedCount: Int
    let watchingCount: Int
    let planToWatchCount: Int
    let droppedCount: Int
    let favoriteCount: Int
    let movieCount: Int
    let seriesCount: Int
    let seasonCount: Int
    let entriesWithNotesCount: Int
    let runtimeMinutes: Int

    init(entries: [AnimeEntry]) {
        totalCount = entries.count
        watchedCount = entries.count { $0.watchStatus == .watched }
        watchingCount = entries.count { $0.watchStatus == .watching }
        planToWatchCount = entries.count { $0.watchStatus == .planToWatch }
        droppedCount = entries.count { $0.watchStatus == .dropped }
        favoriteCount = entries.count { $0.favorite }
        movieCount = entries.count { $0.type == .movie }
        seriesCount = entries.count { $0.type == .series }
        seasonCount = entries.count {
            if case .season = $0.type {
                true
            } else {
                false
            }
        }
        entriesWithNotesCount = entries.count { !$0.notes.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
        runtimeMinutes = entries.reduce(0) { partialResult, entry in
            guard let runtime = entry.detail?.runtimeMinutes else {
                return partialResult
            }
            let multiplier = max(entry.detail?.episodeCount ?? 1, 1)
            return partialResult + runtime * multiplier
        }
    }
}

struct LibraryProfileBackdrop: View {
    @Environment(\.colorScheme) private var colorScheme

    let reduceMotion: Bool

    var body: some View {
        ZStack {
            backdropGradient
                .ignoresSafeArea()

            Circle()
                .fill(primaryOrbColor)
                .frame(width: 360, height: 360)
                .blur(radius: colorScheme == .dark ? 58 : 72)
                .offset(x: -145, y: -230)
                .blendMode(orbBlendMode)
                .opacity(reduceMotion ? primaryOrbReducedOpacity : primaryOrbOpacity)

            Circle()
                .fill(secondaryOrbColor)
                .frame(width: 330, height: 330)
                .blur(radius: colorScheme == .dark ? 62 : 74)
                .offset(x: 155, y: 35)
                .blendMode(orbBlendMode)
                .opacity(reduceMotion ? secondaryOrbReducedOpacity : secondaryOrbOpacity)

            Circle()
                .fill(tertiaryOrbColor)
                .frame(width: 380, height: 380)
                .blur(radius: colorScheme == .dark ? 66 : 78)
                .offset(x: -125, y: 320)
                .blendMode(orbBlendMode)
                .opacity(reduceMotion ? tertiaryOrbReducedOpacity : tertiaryOrbOpacity)

            Rectangle()
                .fill(backdropVeilColor)
                .ignoresSafeArea()
        }
        .compositingGroup()
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    private var backdropGradient: LinearGradient {
        if colorScheme == .dark {
            LinearGradient(
                colors: [
                    Color(red: 0.09, green: 0.10, blue: 0.16),
                    Color(red: 0.17, green: 0.11, blue: 0.08),
                    Color(red: 0.06, green: 0.08, blue: 0.12)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        } else {
            LinearGradient(
                colors: [
                    Color(red: 0.97, green: 0.98, blue: 1.00),
                    Color(red: 1.00, green: 0.97, blue: 0.95),
                    Color(red: 0.96, green: 0.98, blue: 1.00)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        }
    }

    private var primaryOrbColor: Color {
        if colorScheme == .dark {
            .orange.opacity(0.58)
        } else {
            Color(red: 1.00, green: 0.71, blue: 0.47).opacity(0.36)
        }
    }

    private var secondaryOrbColor: Color {
        if colorScheme == .dark {
            .pink.opacity(0.48)
        } else {
            Color(red: 0.98, green: 0.60, blue: 0.76).opacity(0.30)
        }
    }

    private var tertiaryOrbColor: Color {
        if colorScheme == .dark {
            .cyan.opacity(0.40)
        } else {
            Color(red: 0.48, green: 0.82, blue: 1.00).opacity(0.26)
        }
    }

    private var primaryOrbOpacity: Double {
        colorScheme == .dark ? 0.90 : 0.84
    }

    private var secondaryOrbOpacity: Double {
        colorScheme == .dark ? 0.86 : 0.82
    }

    private var tertiaryOrbOpacity: Double {
        colorScheme == .dark ? 0.80 : 0.78
    }

    private var primaryOrbReducedOpacity: Double {
        colorScheme == .dark ? 0.58 : 0.56
    }

    private var secondaryOrbReducedOpacity: Double {
        colorScheme == .dark ? 0.54 : 0.52
    }

    private var tertiaryOrbReducedOpacity: Double {
        colorScheme == .dark ? 0.48 : 0.46
    }

    private var orbBlendMode: BlendMode {
        colorScheme == .dark ? .screen : .normal
    }

    private var backdropVeilColor: Color {
        colorScheme == .dark ? .black.opacity(0.16) : .white.opacity(0.18)
    }
}

struct LibraryProfileRevealModifier: ViewModifier {
    let index: Int
    let appeared: Bool
    let reduceMotion: Bool

    func body(content: Content) -> some View {
        content
            .opacity(appeared ? 1 : 0)
            .scaleEffect(reduceMotion || appeared ? 1 : 0.965)
            .offset(y: reduceMotion || appeared ? 0 : 18)
            .blur(radius: reduceMotion || appeared ? 0 : 10)
            .animation(
                reduceMotion
                    ? nil
                    : .spring(response: 0.44, dampingFraction: 0.86).delay(Double(index) * 0.055),
                value: appeared
            )
    }
}

extension View {
    func profileReveal(index: Int, appeared: Bool, reduceMotion: Bool) -> some View {
        modifier(
            LibraryProfileRevealModifier(
                index: index,
                appeared: appeared,
                reduceMotion: reduceMotion
            )
        )
    }

    func libraryProfileMetricPanel(cornerRadius: CGFloat, tint: Color) -> some View {
        modifier(LibraryProfileMetricPanelModifier(cornerRadius: cornerRadius, tint: tint))
    }

    func libraryProfileInsetPanel(cornerRadius: CGFloat, tint: Color) -> some View {
        modifier(LibraryProfileInsetPanelModifier(cornerRadius: cornerRadius, tint: tint))
    }
}

struct LibraryProfileMetricPanelModifier: ViewModifier {
    @Environment(\.colorScheme) private var colorScheme

    let cornerRadius: CGFloat
    let tint: Color

    @ViewBuilder
    func body(content: Content) -> some View {
        let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)

        if colorScheme == .dark {
            content
                .background {
                    shape.fill(
                        LinearGradient(
                            colors: [
                                tint.opacity(0.12),
                                tint.opacity(0.06)
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                }
                .glassEffect(.regular, in: .rect(cornerRadius: cornerRadius))
                .overlay {
                    shape.stroke(.white.opacity(0.22), lineWidth: 1)
                }
        } else {
            content
                .background {
                    shape.fill(
                        LinearGradient(
                            colors: [
                                tint.opacity(0.20),
                                tint.opacity(0.11)
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                }
                .glassEffect(.regular, in: .rect(cornerRadius: cornerRadius))
                .overlay {
                    shape.stroke(tint.opacity(0.14), lineWidth: 1)
                }
        }
    }
}

struct LibraryProfileInsetPanelModifier: ViewModifier {
    @Environment(\.colorScheme) private var colorScheme

    let cornerRadius: CGFloat
    let tint: Color

    func body(content: Content) -> some View {
        let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)

        content
            .background {
                shape.fill(
                    LinearGradient(
                        colors: [
                            tint.opacity(colorScheme == .dark ? 0.11 : 0.08),
                            .white.opacity(colorScheme == .dark ? 0.045 : 0.18)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
            }
            .overlay {
                shape.stroke(.white.opacity(colorScheme == .dark ? 0.18 : 0.38), lineWidth: 1)
            }
    }
}
