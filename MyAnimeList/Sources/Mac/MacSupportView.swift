//
//  MacSupportView.swift
//  AniShelf
//
//  Created by Claude Code on behalf of Samuel He on 2026/10/17.
//

#if os(macOS)
    import StoreKit
    import SwiftUI

    /// The Support window (AniShelf ▸ Support AniShelf…): a grouped form with the tips as
    /// rows, each with a price button.
    ///
    /// Purchasing and the thank-you state are shared with the
    /// iOS sheet (`SupportPurchaseFlow`, `SupportThankYouView`).
    struct MacSupportView: View {
        @Environment(SupportStore.self) private var supportStore
        @Environment(\.purchase) private var purchaseAction
        @State private var purchaseFlow = SupportPurchaseFlow()

        private let contentAnimation = Animation.spring(response: 0.3, dampingFraction: 0.84)

        var body: some View {
            Form {
                Section {
                    HStack(alignment: .top, spacing: 14) {
                        Image(systemName: "heart.circle.fill")
                            .font(.system(size: 40, weight: .semibold))
                            .foregroundStyle(SupportAniShelfCopy.heartGradient)
                        VStack(alignment: .leading, spacing: 4) {
                            Text(SupportAniShelfCopy.heroTitle)
                                .font(.title2.weight(.bold))
                            Text(SupportAniShelfCopy.heroBody)
                                .foregroundStyle(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                    .padding(.vertical, 4)
                } footer: {
                    Text(SupportAniShelfCopy.disclosure)
                        .foregroundStyle(.secondary)
                }

                if let errorMessage = purchaseFlow.errorMessage {
                    Section {
                        Label {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(SupportAniShelfCopy.purchaseProblem)
                                Text(errorMessage)
                                    .font(.footnote)
                                    .foregroundStyle(.secondary)
                            }
                        } icon: {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .foregroundStyle(.red)
                        }
                    }
                }

                Section(SupportAniShelfCopy.productsTitle) {
                    products
                }
            }
            .formStyle(.grouped)
            .frame(width: 480)
            .fixedSize(horizontal: false, vertical: true)
            .animation(contentAnimation, value: supportStore.loadState)
            .task {
                await supportStore.loadProducts()
            }
        }

        @ViewBuilder
        private var products: some View {
            switch supportStore.loadState {
            case .idle, .loading:
                HStack(spacing: 10) {
                    ProgressView()
                        .controlSize(.small)
                    Text(SupportAniShelfCopy.loading)
                        .foregroundStyle(.secondary)
                }
            case .loaded:
                if purchaseFlow.didSucceed {
                    SupportThankYouView()
                        .frame(maxWidth: .infinity)
                } else {
                    ForEach(supportStore.catalog) { product in
                        productRow(product)
                    }
                }
            case .failed(let failure):
                LabeledContent {
                    Button(SupportAniShelfCopy.retry) {
                        purchaseFlow.retryLoading(store: supportStore)
                    }
                } label: {
                    Text(SupportAniShelfCopy.message(for: failure))
                        .foregroundStyle(.secondary)
                }
            }
        }

        private func productRow(_ product: SupportCatalogProduct) -> some View {
            LabeledContent {
                if supportStore.purchasingProductID == product.id {
                    ProgressView()
                        .controlSize(.small)
                } else {
                    Button(product.displayPrice) {
                        purchaseFlow.purchase(
                            product,
                            store: supportStore,
                            purchaseAction: purchaseAction,
                            successAnimation: contentAnimation
                        )
                    }
                    .disabled(supportStore.purchasingProductID != nil)
                }
            } label: {
                Label {
                    Text(product.displayName)
                    Text(product.tier.subtitleResource)
                } icon: {
                    Image(systemName: product.tier.symbolName)
                        .foregroundStyle(product.tier.tint)
                }
            }
        }
    }
#endif
