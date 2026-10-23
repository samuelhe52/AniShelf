//
//  SupportAniShelfContent.swift
//  AniShelf
//
//  Created by Claude Code on behalf of Samuel He on 2026/10/17.
//

import StoreKit
import SwiftUI

/// Copy shared by the iOS Support sheet and the Mac Support window.
enum SupportAniShelfCopy {
    static let title: LocalizedStringResource = "Support AniShelf"
    static let heroTitle: LocalizedStringResource = "Buy me a coffee"
    static let heroBody: LocalizedStringResource =
        "Optional support for AniShelf if the app has been useful to you."
    static let disclosure: LocalizedStringResource =
        "These are optional tips that unlock no features, content, or services. All purchases are processed by the App Store."
    static let productsTitle: LocalizedStringResource = "Support Options"
    static let loading: LocalizedStringResource = "Loading support options from the App Store…"
    static let retry: LocalizedStringResource = "Try Again"
    static let purchaseProblem: LocalizedStringResource = "Purchase problem"
    static let thankYouTitle: LocalizedStringResource = "Thank you!"
    static let thankYouBody: LocalizedStringResource = "Thanks for supporting AniShelf."
    static let pending: LocalizedStringResource = "Purchase pending approval."

    static func message(for failure: SupportProductLoadFailure) -> LocalizedStringResource {
        switch failure {
        case .unavailable:
            "Support products are temporarily unavailable. Please try again in a moment."
        case .incompleteProductSet:
            "Some support options are not ready yet. Please try again after App Store Connect finishes syncing."
        }
    }

    static let heartGradient = LinearGradient(
        colors: [
            Color(red: 0.98, green: 0.64, blue: 0.28),
            Color(red: 0.95, green: 0.36, blue: 0.56)
        ],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )
}

/// One Support page's purchase state: the last purchase error and whether a tip succeeded.
@Observable
@MainActor
final class SupportPurchaseFlow {
    var errorMessage: String?
    private(set) var didSucceed = false

    func purchase(
        _ product: SupportCatalogProduct,
        store: SupportStore,
        purchaseAction: PurchaseAction,
        successAnimation: Animation
    ) {
        errorMessage = nil
        Task {
            let outcome = await store.purchase(id: product.id) { try await purchaseAction($0) }
            switch outcome {
            case .success:
                withAnimation(successAnimation) { didSucceed = true }
            case .pending:
                ToastCenter.global.completionState = .partialComplete(SupportAniShelfCopy.pending)
            case .userCancelled:
                break
            case .failed(let message):
                errorMessage = message
            }
        }
    }

    func retryLoading(store: SupportStore) {
        errorMessage = nil
        Task { await store.loadProducts(forceReload: true) }
    }
}

/// The thank-you state after a tip: a heart with a burst of particles, and the thanks.
struct SupportThankYouView: View {
    @State private var particles = SupportThankYouParticle.burst()
    @State private var birthDate = Date.now + 0.35

    var body: some View {
        VStack(spacing: 18) {
            ZStack {
                TimelineView(.animation) { timeline in
                    Canvas { ctx, size in
                        drawParticles(ctx: ctx, size: size, now: timeline.date)
                    }
                    .allowsHitTesting(false)
                    .accessibilityHidden(true)
                }

                Image(systemName: "heart.fill")
                    .font(.system(size: 60, weight: .bold))
                    .foregroundStyle(SupportAniShelfCopy.heartGradient)
                    .shadow(
                        color: Color(red: 0.95, green: 0.36, blue: 0.56).opacity(0.40),
                        radius: 20, y: 8
                    )
            }
            .frame(height: 120)

            VStack(spacing: 6) {
                Text(SupportAniShelfCopy.thankYouTitle)
                    .font(.title2.weight(.bold))
                    .foregroundStyle(
                        LinearGradient(
                            colors: [
                                Color(red: 0.98, green: 0.64, blue: 0.28),
                                Color(red: 0.95, green: 0.36, blue: 0.56)
                            ],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )

                Text(SupportAniShelfCopy.thankYouBody)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.bottom, 24)
            }
        }
    }

    private func drawParticles(ctx: GraphicsContext, size: CGSize, now: Date) {
        let center = CGPoint(x: size.width / 2, y: size.height * 0.58)
        for p in particles {
            let elapsed = max(0, now.timeIntervalSince(birthDate) - p.delay)
            guard elapsed > 0 else { continue }
            let progress = elapsed / p.lifetime
            guard progress < 1.0 else { continue }

            let x = center.x + p.vx * elapsed
            let y = center.y + p.vy * elapsed + 0.5 * 90.0 * elapsed * elapsed
            let fadeIn = progress < 0.12 ? progress / 0.12 : 1.0
            let fadeOut = 1.0 - progress
            let scale = max(0.2, 1.0 - progress * 0.4)
            let r = p.size * 0.5 * scale

            var c = ctx
            c.opacity = fadeIn * fadeOut
            c.fill(
                Path(ellipseIn: CGRect(x: x - r, y: y - r, width: r * 2, height: r * 2)),
                with: .color(p.color)
            )
        }
    }
}

fileprivate struct SupportThankYouParticle {
    let id: Int
    let vx: CGFloat
    let vy: CGFloat
    let size: CGFloat
    let color: Color
    let delay: Double
    let lifetime: Double

    static func burst(count: Int = 48) -> [SupportThankYouParticle] {
        let palette: [Color] = [
            Color(red: 0.98, green: 0.64, blue: 0.28),
            Color(red: 0.95, green: 0.36, blue: 0.56),
            Color(red: 1.00, green: 0.84, blue: 0.30),
            Color(red: 0.98, green: 0.52, blue: 0.38),
            Color(red: 0.88, green: 0.30, blue: 0.68)
        ]
        return (0..<count).map { i in
            let angle = Double(i) / Double(count) * .pi * 2
            let speed = CGFloat.random(in: 55...135)
            return SupportThankYouParticle(
                id: i,
                vx: CGFloat(cos(angle)) * speed,
                vy: CGFloat(sin(angle)) * speed - CGFloat.random(in: 25...55),
                size: CGFloat.random(in: 5...13),
                color: palette[i % palette.count],
                delay: Double(i % 5) * 0.025,
                lifetime: Double.random(in: 0.9...1.6)
            )
        }
    }
}
