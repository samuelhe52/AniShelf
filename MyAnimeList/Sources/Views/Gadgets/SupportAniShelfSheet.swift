//
//  SupportAniShelfSheet.swift
//  MyAnimeList
//
//  Created by OpenAI Codex on behalf of Samuel He on 2026/5/30.
//

import StoreKit
import SwiftUI

struct SupportAniShelfSheet: View {
    @Environment(SupportStore.self) private var supportStore
    @Environment(\.dismiss) private var dismiss
    @Environment(\.purchase) private var purchaseAction

    @State private var purchaseFlow = SupportPurchaseFlow()

    private let contentTransitionAnimation = Animation.spring(response: 0.3, dampingFraction: 0.84)
    private let thankYouTransitionAnimation = Animation.spring(response: 0.55, dampingFraction: 0.92)

    var body: some View {
        ZStack {
            LibraryProfileBackdrop()

            ScrollView {
                VStack(spacing: 14) {
                    heroCard
                    if let purchaseErrorMessage = purchaseFlow.errorMessage {
                        purchaseErrorCard(message: purchaseErrorMessage)
                    }
                    contentCard
                }
                .padding(.horizontal, 20)
                .padding(.top, 16)
                .padding(.bottom, 32)
                .frame(maxWidth: 680)
                .frame(maxWidth: .infinity)
                .animation(contentTransitionAnimation, value: supportStore.loadState)
                .animation(thankYouTransitionAnimation, value: purchaseFlow.didSucceed)
            }
            .scrollBounceBehavior(.basedOnSize)
            .preferredNavigationBarScrollEdgeEffect()
        }
        .navigationTitle(SupportAniShelfCopy.title)
        .inlineNavigationTitle()
        .toolbar {
            ToolbarItem(placement: .sheetTrailing) {
                Button("Done") { dismiss() }
            }
        }
        .sensoryFeedback(.success, trigger: purchaseFlow.didSucceed)
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
                    .foregroundStyle(SupportAniShelfCopy.heartGradient)

                VStack(alignment: .leading, spacing: 5) {
                    Text(SupportAniShelfCopy.heroTitle)
                        .font(.title2.weight(.bold))

                    Text(SupportAniShelfCopy.heroBody)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            Text(SupportAniShelfCopy.disclosure)
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
            if purchaseFlow.didSucceed {
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
            SupportAniShelfCopy.productsTitle,
            systemImage: "ellipsis.circle"
        ) {
            HStack(spacing: 12) {
                ProgressView()
                    .controlSize(.regular)
                Text(SupportAniShelfCopy.loading)
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
            SupportAniShelfCopy.productsTitle,
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
            SupportAniShelfCopy.productsTitle,
            systemImage: "exclamationmark.triangle.fill",
            panelTint: Color.red.opacity(0.08)
        ) {
            VStack(alignment: .leading, spacing: 14) {
                Text(SupportAniShelfCopy.message(for: failure))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                Button(SupportAniShelfCopy.retry) {
                    purchaseFlow.retryLoading(store: supportStore)
                }
                .libraryProfileCommandButtonStyle(tint: .orange)
            }
        }
        .transition(contentTransition)
    }

    private var thankYouCard: some View {
        SupportThankYouView()
            .padding(12)
            .popupGlassPanel(
                cornerRadius: 24,
                tint: Color(red: 0.98, green: 0.64, blue: 0.28).opacity(0.06)
            )
            .transition(thankYouTransition)
    }

    private func purchaseErrorCard(message: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(SupportAniShelfCopy.purchaseProblem)
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
        purchaseFlow.purchase(
            product,
            store: supportStore,
            purchaseAction: purchaseAction,
            successAnimation: contentTransitionAnimation
        )
    }

    private var contentTransition: AnyTransition {
        .asymmetric(
            insertion: .opacity.combined(with: .scale(scale: 0.98, anchor: .top)),
            removal: .opacity
        )
    }

    private var thankYouTransition: AnyTransition {
        .opacityScale.animation(.spring(response: 1.55, dampingFraction: 0.92))
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
