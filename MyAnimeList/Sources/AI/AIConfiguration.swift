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
