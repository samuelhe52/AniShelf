//
//  SupportStoreTests.swift
//  AniShelf
//
//  Created by OpenAI Codex on behalf of Samuel He on 2026/6/12.
//

import Foundation
import Testing

@testable import MyAnimeList

struct SupportStoreTests {
    @Test @MainActor func testSupportStoreOrdersProductsByCanonicalTierOrder() throws {
        let products: [any SupportStoreProduct] = [
            MockSupportProduct(id: SupportTipTier.large.productID, displayName: "Tip Large", displayPrice: "$6.99"),
            MockSupportProduct(id: SupportTipTier.small.productID, displayName: "Tip Small", displayPrice: "$0.99"),
            MockSupportProduct(
                id: SupportTipTier.medium.productID, displayName: "Tip Medium", displayPrice: "$2.99")
        ]

        let catalog = try SupportStore.makeCatalog(from: products)

        #expect(catalog.map(\.id) == SupportTipTier.allCases.map(\.productID))
    }

    @Test @MainActor func testSupportStorePurchaseMapsSuccessAndFinishesTransaction() async {
        let transaction = MockSupportTransaction()
        let store = SupportStore(
            provider: MockSupportProvider(
                products: [
                    MockSupportProduct(
                        id: SupportTipTier.small.productID, displayName: "Tip Small", displayPrice: "$0.99",
                        purchaseResult: .success(transaction)),
                    MockSupportProduct(
                        id: SupportTipTier.medium.productID, displayName: "Tip Medium", displayPrice: "$2.99"),
                    MockSupportProduct(
                        id: SupportTipTier.large.productID, displayName: "Tip Large", displayPrice: "$6.99")
                ]
            )
        )

        await store.loadProducts()
        let outcome = await store.purchase(id: SupportTipTier.small.productID)

        #expect(outcome == .success)
        #expect(transaction.finishCallCount == 1)
    }

    @Test @MainActor func testSupportStorePurchaseMapsUserCancelledPendingAndFailure() async {
        let cancelledStore = SupportStore(
            provider: MockSupportProvider(
                products: [
                    MockSupportProduct(
                        id: SupportTipTier.small.productID, displayName: "Tip Small", displayPrice: "$0.99",
                        purchaseResult: .userCancelled),
                    MockSupportProduct(
                        id: SupportTipTier.medium.productID, displayName: "Tip Medium", displayPrice: "$2.99"),
                    MockSupportProduct(
                        id: SupportTipTier.large.productID, displayName: "Tip Large", displayPrice: "$6.99")
                ]
            )
        )
        await cancelledStore.loadProducts()
        #expect(await cancelledStore.purchase(id: SupportTipTier.small.productID) == .userCancelled)

        let pendingStore = SupportStore(
            provider: MockSupportProvider(
                products: [
                    MockSupportProduct(
                        id: SupportTipTier.small.productID, displayName: "Tip Small", displayPrice: "$0.99",
                        purchaseResult: .pending),
                    MockSupportProduct(
                        id: SupportTipTier.medium.productID, displayName: "Tip Medium", displayPrice: "$2.99"),
                    MockSupportProduct(
                        id: SupportTipTier.large.productID, displayName: "Tip Large", displayPrice: "$6.99")
                ]
            )
        )
        await pendingStore.loadProducts()
        #expect(await pendingStore.purchase(id: SupportTipTier.small.productID) == .pending)

        let failingStore = SupportStore(
            provider: MockSupportProvider(
                products: [
                    MockSupportProduct(
                        id: SupportTipTier.small.productID, displayName: "Tip Small", displayPrice: "$0.99",
                        error: MockSupportError.purchaseFailed),
                    MockSupportProduct(
                        id: SupportTipTier.medium.productID, displayName: "Tip Medium", displayPrice: "$2.99"),
                    MockSupportProduct(
                        id: SupportTipTier.large.productID, displayName: "Tip Large", displayPrice: "$6.99")
                ]
            )
        )
        await failingStore.loadProducts()
        #expect(
            await failingStore.purchase(id: SupportTipTier.small.productID)
                == .failed(MockSupportError.purchaseFailed.localizedDescription)
        )
    }

}


fileprivate struct MockSupportProvider: SupportStoreProviding {
    let products: [MockSupportProduct]
    var fetchError: Error?

    func fetchProducts(identifiers: [String]) async throws -> [any SupportStoreProduct] {
        if let fetchError {
            throw fetchError
        }

        return products.map { $0 as any SupportStoreProduct }
    }
}

fileprivate struct MockSupportProduct: SupportStoreProduct {
    let id: String
    let displayName: String
    let displayPrice: String
    var purchaseResult: SupportPurchaseResult = .pending
    var error: Error?

    func purchase() async throws -> SupportPurchaseResult {
        if let error {
            throw error
        }

        return purchaseResult
    }
}

fileprivate final class MockSupportTransaction: SupportTransactionFinishing {
    private(set) var finishCallCount = 0

    func finish() async {
        finishCallCount += 1
    }
}

fileprivate enum MockSupportError: LocalizedError {
    case purchaseFailed

    var errorDescription: String? {
        switch self {
        case .purchaseFailed:
            "Mock purchase failed."
        }
    }
}
