//
//  AIConfiguration.swift
//  AniShelf
//
//  Created by OpenAI Codex on behalf of Samuel He on 2026/10/28.
//

import Foundation
import FoundationModels

enum AIBackend: String, CaseIterable, Sendable {
    case apple, openAI, openRouter

    var defaultModel: String {
        switch self {
        case .apple: ""
        case .openAI: "gpt-6-luna"
        case .openRouter: "openai/gpt-6-luna"
        }
    }

    /// Product names, shown as they are in every language.
    var displayName: String {
        switch self {
        case .apple: "Apple Intelligence"
        case .openAI: "OpenAI"
        case .openRouter: "OpenRouter"
        }
    }

    var isProvider: Bool { self != .apple }

    /// Check batches in flight at once: parallel requests save time, not tokens.
    ///
    /// The on-device model runs one response at a time, so Apple stays sequential.
    var maximumConcurrentBatches: Int { isProvider ? 8 : 1 }

    /// Models checked with reasoning off and strict structured output (docs-ai 034.003), and
    /// scored against a labeled library (docs-ai 034.004).
    ///
    /// Any other model ID is a custom choice the user makes at their own risk.
    var suggestedModels: [AISuggestedModel] {
        switch self {
        case .apple: []
        case .openAI: [AISuggestedModel(id: "gpt-6-luna", name: "GPT-6 Luna")]
        case .openRouter:
            [AISuggestedModel(id: "openai/gpt-6-luna", name: "GPT-6 Luna")]
        }
    }
}

extension Notification.Name {
    /// Posted on the main thread when the Smart Features backend, a key, or a model changes.
    ///
    /// The object is the posting ``AISettingsModel``. A key or model change puts its backend under
    /// ``AIBackend/changedBackendKey`` in the user info.
    static let aiConfigurationDidChange = Notification.Name("AIConfigurationDidChange")
}

extension AIBackend {
    static let changedBackendKey = "backend"
}

struct AISuggestedModel: Hashable, Sendable {
    let id: String
    let name: String
}

/// Provider reasoning effort.
///
/// Off by default: library tasks are simple classification, and reasoning tokens count
/// against the response cap. The other levels stay available for tasks that need them.
enum AIReasoning: String, CaseIterable, Sendable {
    case off, low, medium, high
}

/// Device-local choices.
///
/// Secrets never belong in these defaults.
struct AIConfiguration {
    let defaults: UserDefaults

    /// The app's defaults, or a fixture launch's own suite, so a fixture never changes real choices.
    @MainActor static var appDefaults: UserDefaults {
        #if DEBUG || LIBRARY_FIXTURES
            if let fixture = LibraryFixture.active { return fixture.defaults }
        #endif
        return .standard
    }

    func model(for backend: AIBackend) -> String {
        let value = defaults.string(forKey: "ai.model.\(backend.rawValue)")?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return value.flatMap { $0.isEmpty ? nil : $0 } ?? backend.defaultModel
    }

    func setModel(_ model: String, for backend: AIBackend) {
        defaults.set(model.trimmingCharacters(in: .whitespacesAndNewlines), forKey: "ai.model.\(backend.rawValue)")
    }

    var selectedBackend: AIBackend? {
        get { defaults.string(forKey: "ai.backend").flatMap(AIBackend.init(rawValue:)) }
        nonmutating set { defaults.set(newValue?.rawValue, forKey: "ai.backend") }
    }

    func resolvedBackend(availability: AIAvailability) -> AIBackend? {
        if let selectedBackend, availability.isUsable(selectedBackend) { return selectedBackend }
        return AIBackend.allCases.first(where: availability.isUsable)
    }

    /// The backend Smart Features use on this device now, or `nil` when none can work.
    @MainActor static func currentBackend(
        defaults: UserDefaults = appDefaults, keys: AIProviderKeyStorage = AIProviderKeyStorage()
    ) -> AIBackend? {
        AIConfiguration(defaults: defaults).resolvedBackend(availability: AIAvailability(keys: keys))
    }
}

struct AIAvailability {
    enum UnavailableReason: Equatable {
        case apple(SystemLanguageModel.Availability.UnavailableReason)
        case requiresOS27
        case missingKey
    }

    let apple: SystemLanguageModel.Availability
    let supportsProviders: Bool
    let keyedProviders: Set<AIBackend>

    init(keys: AIProviderKeyStorage) {
        apple = SystemLanguageModel.default.availability
        if #available(iOS 27.0, macOS 27.0, *) { supportsProviders = true } else { supportsProviders = false }
        keyedProviders = Set([AIBackend.openAI, .openRouter].filter { keys.key(for: $0) != nil })
    }

    init(apple: SystemLanguageModel.Availability, supportsProviders: Bool, keyedProviders: Set<AIBackend>) {
        self.apple = apple
        self.supportsProviders = supportsProviders
        self.keyedProviders = keyedProviders
    }

    func reason(for backend: AIBackend) -> UnavailableReason? {
        if backend == .apple {
            if case .unavailable(let reason) = apple { return .apple(reason) }
            return nil
        }
        if !supportsProviders { return .requiresOS27 }
        return keyedProviders.contains(backend) ? nil : .missingKey
    }

    func isUsable(_ backend: AIBackend) -> Bool { reason(for: backend) == nil }
}
