//
//  AISettingsModel.swift
//  AniShelf
//
//  Created by Claude Code on behalf of Samuel He on 2026/10/29.
//

import Foundation
import FoundationModels
import Observation

/// One tiny typed request that proves a backend, key, and model work together.
@MainActor
enum AIConnectionCheck {
    @Generable
    struct Response {
        var value: Int
    }

    /// Sends no library data; the request and its expected answer are fixed.
    static func run(backend: AIBackend, configuration: AIConfiguration, keys: AIProviderKeyStorage) async throws {
        let generator = AILanguageModelGenerator(
            factory: AISessionFactory(configuration: configuration, keys: keys), backend: backend
        )
        let instructions = "Return the requested integer in the value field."
        let prompt = "Return 7."
        let budget = try await AIContextBudget.make(
            backend: backend, instructions: instructions, generating: Response.self, maximumResponseTokens: 128
        )
        guard try await budget.fits(prompt) else { throw AIError.itemTooLarge }
        let response = try await generator.generate(
            Response.self, instructions: instructions, prompt: prompt,
            maximumResponseTokens: budget.maximumResponseTokens
        )
        guard response.value == 7 else { throw AIError.decodingFailure }
    }
}

extension AIError {
    /// A message that names no provider response, request, or key.
    var message: LocalizedStringResource {
        switch self {
        case .unavailable:
            "This backend is not set up on this device."
        case .providerHTTPStatus(401):
            "The provider rejected the API key."
        case .providerHTTPStatus(403):
            "The provider refused the request. The key, the model, or your region may not be allowed."
        case .providerHTTPStatus(404), .providerHTTPStatus(400):
            "The provider rejected the request. Check the model ID."
        case .providerHTTPStatus(429):
            "The provider is limiting requests. Try again later."
        case .providerHTTPStatus(let status):
            "The provider returned an error (HTTP \(status))."
        case .network:
            "Could not reach the provider. Check your connection."
        case .decodingFailure, .responseTruncated:
            "The model did not return a valid answer. Try another model."
        case .contextSizeExceeded, .itemTooLarge:
            "The request was too large for the model."
        case .requestFailed:
            "The request failed. Try again."
        }
    }
}

/// State for the Smart Features settings page.
///
/// It caches what the page shows, so a redraw never reads the Keychain.
@Observable
@MainActor
final class AISettingsModel {
    enum TestState: Equatable {
        case idle, testing, succeeded
        case failed(AIError)
    }

    private let configuration: AIConfiguration
    private let keys: AIProviderKeyStorage
    private let supportsProvidersOverride: Bool?

    private(set) var availability: AIAvailability
    private(set) var activeBackend: AIBackend?
    private(set) var models: [AIBackend: String] = [:]
    /// The last 4 characters of each stored key, for display only.
    private(set) var keySuffixes: [AIBackend: String] = [:]
    private(set) var testStates: [AIBackend: TestState] = [:]
    /// The newest test of each backend; a configuration change clears it, so an older test
    /// cannot report on a model or key the page no longer shows.
    private var testTokens: [AIBackend: UUID] = [:]

    init(
        defaults: UserDefaults = AIConfiguration.appDefaults, keys: AIProviderKeyStorage = AIProviderKeyStorage(),
        availability: AIAvailability? = nil
    ) {
        self.configuration = AIConfiguration(defaults: defaults)
        self.keys = keys
        self.supportsProvidersOverride = availability?.supportsProviders
        self.availability = availability ?? AIAvailability(keys: keys)
        reload(availability: availability)
    }

    /// Rereads availability, keys, and models, for example when the page appears.
    func refresh() {
        reload(availability: nil)
    }

    var supportsProviders: Bool { availability.supportsProviders }

    /// Backends the page lists: Apple Intelligence always, providers only where they can run.
    var listedBackends: [AIBackend] {
        AIBackend.allCases.filter { !$0.isProvider || supportsProviders }
    }

    func select(_ backend: AIBackend) {
        guard availability.isUsable(backend) else { return }
        configuration.selectedBackend = backend
        activeBackend = backend
        notifyChange()
    }

    func model(for backend: AIBackend) -> String {
        models[backend] ?? backend.defaultModel
    }

    func usesCustomModel(for backend: AIBackend) -> Bool {
        backend.isProvider && !backend.suggestedModels.contains { $0.id == model(for: backend) }
    }

    /// Returns `false` for an empty ID.
    @discardableResult
    func setModel(_ id: String, for backend: AIBackend) -> Bool {
        let id = id.trimmingCharacters(in: .whitespacesAndNewlines)
        guard backend.isProvider, !id.isEmpty else { return false }
        configuration.setModel(id, for: backend)
        models[backend] = id
        invalidateTest(backend)
        notifyChange(backend)
        return true
    }

    @discardableResult
    func saveKey(_ key: String, for backend: AIBackend) -> Bool {
        guard keys.save(key, for: backend) else { return false }
        invalidateTest(backend)
        refresh()
        notifyChange(backend)
        return true
    }

    /// Returns `false` when the Keychain refuses; the key then stays.
    @discardableResult
    func removeKey(for backend: AIBackend) -> Bool {
        guard keys.delete(for: backend) else { return false }
        invalidateTest(backend)
        refresh()
        notifyChange(backend)
        return true
    }

    private func notifyChange(_ backend: AIBackend? = nil) {
        NotificationCenter.default.post(
            name: .aiConfigurationDidChange, object: self,
            userInfo: backend.map { [AIBackend.changedBackendKey: $0] }
        )
    }

    /// Applies a change made elsewhere, such as another window's settings page.
    ///
    /// A test of a backend whose key or model changed no longer reports on what it checked.
    func configurationDidChange(_ notification: Notification) {
        guard notification.object as AnyObject? !== self else { return }
        if let backend = notification.userInfo?[AIBackend.changedBackendKey] as? AIBackend {
            invalidateTest(backend)
        }
        refresh()
    }

    func testConnection(_ backend: AIBackend) async {
        guard testStates[backend] != .testing else { return }
        let token = UUID()
        testTokens[backend] = token
        testStates[backend] = .testing
        let result: TestState
        do {
            try await AIConnectionCheck.run(backend: backend, configuration: configuration, keys: keys)
            result = .succeeded
        } catch is CancellationError {
            result = .idle
        } catch {
            result = .failed(error as? AIError ?? .requestFailed)
        }
        guard testTokens[backend] == token else { return }
        testTokens[backend] = nil
        testStates[backend] = result
    }

    private func invalidateTest(_ backend: AIBackend) {
        testTokens[backend] = nil
        testStates[backend] = .idle
    }

    private func reload(availability override: AIAvailability?) {
        if let override {
            availability = override
        } else {
            let fresh = AIAvailability(keys: keys)
            availability = AIAvailability(
                apple: fresh.apple, supportsProviders: supportsProvidersOverride ?? fresh.supportsProviders,
                keyedProviders: fresh.keyedProviders
            )
        }
        activeBackend = configuration.resolvedBackend(availability: availability)
        var models: [AIBackend: String] = [:]
        var suffixes: [AIBackend: String] = [:]
        for backend in AIBackend.allCases where backend.isProvider {
            models[backend] = configuration.model(for: backend)
            if let key = keys.key(for: backend) { suffixes[backend] = String(key.suffix(4)) }
        }
        self.models = models
        keySuffixes = suffixes
    }
}
