//
//  SupportStore.swift
//  MyAnimeList
//
//  Created by OpenAI Codex on behalf of Samuel He on 2026/5/30.
//

import Foundation
import StoreKit
import SwiftUI

enum SupportTipTier: String, CaseIterable, Equatable, Identifiable {
    case small
    case medium
    case large

    var id: String { rawValue }

    var productID: String {
        switch self {
        case .small:
            "com.samuelhe.anishelf.tip.small"
        case .medium:
            "com.samuelhe.anishelf.tip.medium"
        case .large:
            "com.samuelhe.anishelf.tip.large"
        }
    }

    var subtitleResource: LocalizedStringResource {
        switch self {
        case .small:
            "A small thank-you"
        case .medium:
            "A generous coffee"
        case .large:
            "A big show of support"
        }
    }

    var symbolName: String {
        switch self {
        case .small:
            "cup.and.saucer.fill"
        case .medium:
            "mug.fill"
        case .large:
            "gift.fill"
        }
    }

    var tint: Color {
        switch self {
        case .small:
            Color(red: 0.95, green: 0.65, blue: 0.35)
        case .medium:
            Color(red: 0.94, green: 0.48, blue: 0.40)
        case .large:
            Color(red: 0.95, green: 0.36, blue: 0.56)
        }
    }
}

struct SupportCatalogProduct: Identifiable, Equatable {
    let tier: SupportTipTier
    let displayName: String
    let displayPrice: String

    var id: String { tier.productID }
}

enum SupportProductLoadFailure: Error, Equatable {
    case unavailable
    case incompleteProductSet
}

enum SupportPurchaseOutcome: Equatable {
    case success
    case userCancelled
    case pending
    case failed(String)
}

@MainActor
protocol SupportTransactionFinishing {
    func finish() async
}

/// Scene-bound StoreKit purchase, normally the SwiftUI `\.purchase` environment action.
///
/// Plain `Product.purchase()` lets StoreKit pick the window for its confirmation sheet, which can
/// be the wrong one when several AniShelf windows are open.
typealias SupportPurchaseAction = @MainActor (Product) async throws -> Product.PurchaseResult

@MainActor
protocol SupportStoreProduct {
    var id: String { get }
    var displayName: String { get }
    var displayPrice: String { get }

    func purchase(using action: SupportPurchaseAction) async throws -> SupportPurchaseResult
}

enum SupportPurchaseResult {
    case success(any SupportTransactionFinishing)
    case pending
    case userCancelled
}

@MainActor
protocol SupportStoreProviding {
    func fetchProducts(identifiers: [String]) async throws -> [any SupportStoreProduct]
}

@Observable @MainActor
final class SupportStore {
    enum LoadState: Equatable {
        case idle
        case loading
        case loaded
        case failed(SupportProductLoadFailure)
    }

    @ObservationIgnored private let provider: any SupportStoreProviding
    @ObservationIgnored private var productsByID: [String: any SupportStoreProduct] = [:]

    private(set) var catalog: [SupportCatalogProduct] = []
    private(set) var loadState: LoadState = .idle
    private(set) var purchasingProductID: String?

    init() {
        self.provider = AppStoreSupportProvider()
    }

    init(provider: any SupportStoreProviding) {
        self.provider = provider
    }

    var isLoadingProducts: Bool {
        loadState == .loading
    }

    func loadProducts(forceReload: Bool = false) async {
        if !forceReload, loadState == .loaded, !catalog.isEmpty {
            return
        }

        loadState = .loading

        do {
            let products = try await provider.fetchProducts(
                identifiers: SupportTipTier.allCases.map(\.productID)
            )
            let catalog = try Self.makeCatalog(from: products)
            productsByID = Dictionary(uniqueKeysWithValues: products.map { ($0.id, $0) })
            self.catalog = catalog
            loadState = .loaded
        } catch let error as SupportProductLoadFailure {
            catalog = []
            productsByID = [:]
            loadState = .failed(error)
        } catch {
            catalog = []
            productsByID = [:]
            loadState = .failed(.unavailable)
        }
    }

    func purchase(id: String, using action: SupportPurchaseAction) async -> SupportPurchaseOutcome {
        guard let product = productsByID[id] else {
            return .failed(String(localized: "Unable to find this support option right now."))
        }

        purchasingProductID = id
        defer { purchasingProductID = nil }

        do {
            let result = try await product.purchase(using: action)
            switch result {
            case .success(let transaction):
                await transaction.finish()
                return .success
            case .pending:
                return .pending
            case .userCancelled:
                return .userCancelled
            }
        } catch {
            let fallback = String(localized: "Unable to complete the purchase right now.")
            let message = error.localizedDescription.trimmingCharacters(in: .whitespacesAndNewlines)
            return .failed(message.isEmpty ? fallback : message)
        }
    }

    static func makeCatalog(from products: [any SupportStoreProduct]) throws -> [SupportCatalogProduct] {
        let productsByID = Dictionary(uniqueKeysWithValues: products.map { ($0.id, $0) })
        let catalog = SupportTipTier.allCases.compactMap { tier -> SupportCatalogProduct? in
            guard let product = productsByID[tier.productID] else { return nil }
            return SupportCatalogProduct(
                tier: tier,
                displayName: product.displayName,
                displayPrice: product.displayPrice
            )
        }

        guard catalog.count == SupportTipTier.allCases.count else {
            throw SupportProductLoadFailure.incompleteProductSet
        }

        return catalog
    }
}

fileprivate struct AppStoreSupportProvider: SupportStoreProviding {
    func fetchProducts(identifiers: [String]) async throws -> [any SupportStoreProduct] {
        try await Product.products(for: identifiers).map(AppStoreSupportProduct.init)
    }
}

fileprivate struct AppStoreSupportProduct: SupportStoreProduct {
    let product: Product

    var id: String { product.id }
    var displayName: String { product.displayName }
    var displayPrice: String { product.displayPrice }

    func purchase(using action: SupportPurchaseAction) async throws -> SupportPurchaseResult {
        let result = try await action(product)

        switch result {
        case .success(let verification):
            let transaction = try verified(verification)
            return .success(StoreKitSupportTransaction(transaction: transaction))
        case .pending:
            return .pending
        case .userCancelled:
            return .userCancelled
        @unknown default:
            throw SupportStorefrontError.unknownPurchaseState
        }
    }

    private func verified<T>(_ result: VerificationResult<T>) throws -> T {
        switch result {
        case .verified(let value):
            return value
        case .unverified:
            throw SupportStorefrontError.unverifiedTransaction
        }
    }
}

fileprivate struct StoreKitSupportTransaction: SupportTransactionFinishing {
    let transaction: StoreKit.Transaction

    func finish() async {
        await transaction.finish()
    }
}

fileprivate enum SupportStorefrontError: LocalizedError {
    case unverifiedTransaction
    case unknownPurchaseState

    var errorDescription: String? {
        switch self {
        case .unverifiedTransaction:
            String(localized: "The App Store could not verify the purchase.")
        case .unknownPurchaseState:
            String(localized: "The App Store returned an unknown purchase state.")
        }
    }
}
