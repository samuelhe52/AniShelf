//
//  SupportAniShelfSheet.swift
//  MyAnimeList
//
//  Created by OpenAI Codex on behalf of Samuel He on 2026/5/30.
//

import SwiftUI

struct SupportAniShelfSheet: View {
    @Environment(SupportStore.self) private var supportStore
    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @State private var purchaseErrorMessage: String?
    @State private var purchaseSucceeded = false
    @State private var celebrationParticles: [SupportThankYouParticle] = []
    @State private var celebrationBirthDate: Date = .distantPast

    private let contentTransitionAnimation = Animation.spring(response: 0.3, dampingFraction: 0.84)
    private let thankYouTransitionAnimation = Animation.spring(response: 0.55, dampingFraction: 0.92)

    var body: some View {
        ZStack {
            LibraryProfileBackdrop(reduceMotion: reduceMotion)

            ScrollView {
                VStack(spacing: 14) {
                    heroCard
                    if let purchaseErrorMessage {
                        purchaseErrorCard(message: purchaseErrorMessage)
                    }
                    contentCard
                }
                .padding(.horizontal, 20)
                .padding(.top, 16)
                .padding(.bottom, 32)
                .frame(maxWidth: 680)
                .frame(maxWidth: .infinity)
                .animation(reduceMotion ? nil : contentTransitionAnimation, value: supportStore.loadState)
                .animation(reduceMotion ? nil : thankYouTransitionAnimation, value: purchaseSucceeded)
            }
            .scrollBounceBehavior(.basedOnSize)
        }
        .navigationTitle(supportTitleResource)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button(doneTitleResource) { dismiss() }
            }
        }
        .sensoryFeedback(.success, trigger: purchaseSucceeded)
        .task {
            await supportStore.loadProducts()
        }
        .presentationSizing(.page)
    }

    private var heroCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 14) {
                Image(systemName: "heart.circle.fill")
                    .font(.system(size: 44, weight: .semibold))
                    .foregroundStyle(
                        LinearGradient(
                            colors: [
                                Color(red: 0.98, green: 0.64, blue: 0.28),
                                Color(red: 0.95, green: 0.36, blue: 0.56)
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )

                VStack(alignment: .leading, spacing: 5) {
                    Text(heroTitleResource)
                        .font(.title2.weight(.bold))

                    Text(heroBodyResource)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            Text(disclosureBodyResource)
                .font(.footnote)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(18)
        .popupGlassPanel(cornerRadius: 28, tint: .clear)
    }

    @ViewBuilder
    private var contentCard: some View {
        switch supportStore.loadState {
        case .idle, .loading:
            loadingCard
        case .loaded:
            if purchaseSucceeded {
                thankYouCard
            } else {
                productsCard
            }
        case .failed(let failure):
            retryCard(for: failure)
        }
    }

    private var loadingCard: some View {
        PopupSectionCard(
            productsTitleResource,
            systemImage: "ellipsis.circle"
        ) {
            HStack(spacing: 12) {
                ProgressView()
                    .controlSize(.regular)
                Text(loadingBodyResource)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.vertical, 6)
        }
        .transition(contentTransition)
    }

    private var productsCard: some View {
        PopupSectionCard(
            productsTitleResource,
            systemImage: "star.circle.fill"
        ) {
            VStack(spacing: 12) {
                ForEach(supportStore.catalog) { product in
                    SupportTipProductRow(
                        product: product,
                        isPurchasing: supportStore.purchasingProductID == product.id,
                        isInteractionDisabled: supportStore.purchasingProductID != nil,
                        onPurchase: { purchase(product) }
                    )
                }
            }
        }
        .transition(contentTransition)
    }

    private func retryCard(for failure: SupportProductLoadFailure) -> some View {
        PopupSectionCard(
            productsTitleResource,
            systemImage: "exclamationmark.triangle.fill",
            panelTint: Color.red.opacity(0.08)
        ) {
            VStack(alignment: .leading, spacing: 14) {
                Text(messageResource(for: failure))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                Button(retryTitleResource) {
                    purchaseErrorMessage = nil
                    Task {
                        await supportStore.loadProducts(forceReload: true)
                    }
                }
                .buttonStyle(LibraryProfileCommandButtonStyle(tint: .orange, filled: false))
            }
        }
        .transition(contentTransition)
    }

    private var thankYouCard: some View {
        VStack(spacing: 18) {
            ZStack {
                if !reduceMotion {
                    TimelineView(.animation) { timeline in
                        Canvas { ctx, size in
                            drawParticles(ctx: ctx, size: size, now: timeline.date)
                        }
                        .allowsHitTesting(false)
                        .accessibilityHidden(true)
                    }
                }

                Image(systemName: "heart.fill")
                    .font(.system(size: 60, weight: .bold))
                    .foregroundStyle(
                        LinearGradient(
                            colors: [
                                Color(red: 0.98, green: 0.64, blue: 0.28),
                                Color(red: 0.95, green: 0.36, blue: 0.56)
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .shadow(
                        color: Color(red: 0.95, green: 0.36, blue: 0.56).opacity(0.40),
                        radius: 20, y: 8
                    )
                    .symbolEffect(.bounce, value: purchaseSucceeded)
            }
            .frame(height: 120)

            VStack(spacing: 6) {
                Text(thankYouTitleResource)
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

                Text(thankYouBodyResource)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.bottom, 24)
            }
        }
        .padding(12)
        .popupGlassPanel(
            cornerRadius: 24,
            tint: Color(red: 0.98, green: 0.64, blue: 0.28).opacity(0.06)
        )
        .transition(thankYouTransition)
    }

    private func drawParticles(ctx: GraphicsContext, size: CGSize, now: Date) {
        let center = CGPoint(x: size.width / 2, y: size.height * 0.58)
        for p in celebrationParticles {
            let elapsed = max(0, now.timeIntervalSince(celebrationBirthDate) - p.delay)
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

    private func purchaseErrorCard(message: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(purchaseProblemTitleResource)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.red)

            Text(message)
                .font(.footnote)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .popupGlassPanel(cornerRadius: 24, tint: .red.opacity(0.06))
    }

    private func purchase(_ product: SupportCatalogProduct) {
        purchaseErrorMessage = nil

        Task { @MainActor in
            let outcome = await supportStore.purchase(id: product.id)
            handlePurchaseOutcome(outcome)
        }
    }

    private func handlePurchaseOutcome(_ outcome: SupportPurchaseOutcome) {
        switch outcome {
        case .success:
            celebrationParticles = SupportThankYouParticle.burst()
            celebrationBirthDate = .now + 0.35
            withAnimation(contentTransitionAnimation) {
                purchaseSucceeded = true
            }
        case .pending:
            ToastCenter.global.completionState = .partialComplete(pendingBodyResource)
        case .userCancelled:
            break
        case .failed(let message):
            purchaseErrorMessage = message
        }
    }

    private func messageResource(for failure: SupportProductLoadFailure) -> LocalizedStringResource {
        switch failure {
        case .unavailable:
            "Support products are temporarily unavailable. Please try again in a moment."
        case .incompleteProductSet:
            "Some support options are not ready yet. Please try again after App Store Connect finishes syncing."
        }
    }

    private var supportTitleResource: LocalizedStringResource {
        "Support AniShelf"
    }

    private var doneTitleResource: LocalizedStringResource {
        "Done"
    }

    private var heroTitleResource: LocalizedStringResource {
        "Buy me a coffee"
    }

    private var heroBodyResource: LocalizedStringResource {
        "Optional support for AniShelf if the app has been useful to you."
    }

    private var disclosureBodyResource: LocalizedStringResource {
        "These are optional tips that unlock no features, content, or services. All purchases are processed by the App Store."
    }

    private var productsTitleResource: LocalizedStringResource {
        "Support Options"
    }

    private var loadingBodyResource: LocalizedStringResource {
        "Loading support options from the App Store..."
    }

    private var retryTitleResource: LocalizedStringResource {
        "Try Again"
    }

    private var purchaseProblemTitleResource: LocalizedStringResource {
        "Purchase problem"
    }

    private var thankYouTitleResource: LocalizedStringResource {
        "Thank you!"
    }

    private var thankYouBodyResource: LocalizedStringResource {
        "Thanks for supporting AniShelf."
    }

    private var pendingBodyResource: LocalizedStringResource {
        "Purchase pending approval."
    }

    private var contentTransition: AnyTransition {
        reduceMotion
            ? .opacity
            : .asymmetric(
                insertion: .opacity.combined(with: .scale(scale: 0.98, anchor: .top)),
                removal: .opacity
            )
    }

    private var thankYouTransition: AnyTransition {
        reduceMotion ? .opacity : .opacityScale.animation(.spring(response: 1.55, dampingFraction: 0.92))
    }
}

fileprivate struct SupportTipProductRow: View {
    let product: SupportCatalogProduct
    let isPurchasing: Bool
    let isInteractionDisabled: Bool
    let onPurchase: () -> Void

    var body: some View {
        Button(action: onPurchase) {
            HStack(spacing: 14) {
                LibraryProfileSettingIcon(
                    systemImage: product.tier.symbolName,
                    tint: product.tier.tint
                )

                VStack(alignment: .leading, spacing: 4) {
                    Text(product.displayName)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.primary)

                    Text(product.tier.subtitleResource)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer(minLength: 12)

                if isPurchasing {
                    ProgressView()
                        .controlSize(.small)
                } else {
                    Text(product.displayPrice)
                        .font(.subheadline.weight(.bold))
                        .foregroundStyle(product.tier.tint)
                        .monospacedDigit()
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 13)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background {
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .fill(product.tier.tint.opacity(0.08))
            }
            .overlay {
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .stroke(product.tier.tint.opacity(0.18), lineWidth: 1)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(isInteractionDisabled)
        .opacity(isInteractionDisabled && !isPurchasing ? 0.65 : 1)
        .animation(.spring(response: 0.26, dampingFraction: 0.82), value: isPurchasing)
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
