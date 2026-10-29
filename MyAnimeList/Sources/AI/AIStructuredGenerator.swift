//
//  AIStructuredGenerator.swift
//  AniShelf
//
//  Created by OpenAI Codex on behalf of Samuel He on 2026/10/28.
//

import Foundation
import FoundationModels

/// Deliberately carries no provider response body, request, or credentials.
enum AIError: Error, Equatable {
    case unavailable, contextSizeExceeded, decodingFailure, responseTruncated, requestFailed, itemTooLarge
    case providerHTTPStatus(Int)
    case network(Int)

    /// Whether the same request can succeed on a later attempt.
    var isTransient: Bool {
        switch self {
        case .providerHTTPStatus(let status): [408, 425, 429, 500, 502, 503, 504].contains(status)
        // Offline stays offline within a retry window.
        case .network(let code): code != URLError.notConnectedToInternet.rawValue
        default: false
        }
    }
}

/// Bounded retries for transient failures, with exponential backoff and jitter.
///
/// `Retry-After` is not honored: the vendored client surfaces only the status code.
struct AIRetryPolicy {
    var maximumRetries = 2
    var baseDelay: Duration = .seconds(1)
    var sleep: @MainActor (Duration) async throws -> Void = { try await Task.sleep(for: $0) }

    @MainActor
    func run<Value>(_ operation: () async throws -> Value) async throws -> Value {
        var attempt = 0
        while true {
            do {
                return try await operation()
            } catch let error as AIError where error.isTransient && attempt < maximumRetries {
                // 1 s, then 2 s, each stretched by up to half again so parallel batches spread out.
                try await sleep(baseDelay * (1 << attempt) * Double.random(in: 1...1.5))
                attempt += 1
            }
        }
    }
}

@MainActor
protocol AIStructuredGenerator {
    func generate<Value: Generable>(
        _ type: Value.Type, instructions: String, prompt: String, maximumResponseTokens: Int
    ) async throws -> Value
}

@MainActor
struct AISessionFactory {
    let configuration: AIConfiguration
    let keys: AIProviderKeyStorage
    /// Provider reasoning; the Apple system model ignores it.
    ///
    /// Callers that change it should size the budget to match.
    var reasoning: AIReasoning = .off

    func makeSession(backend: AIBackend, instructions: String) throws -> LanguageModelSession {
        guard AIAvailability(keys: keys).isUsable(backend) else { throw AIError.unavailable }
        if backend == .apple {
            return LanguageModelSession(model: SystemLanguageModel.default, instructions: instructions)
        }
        if #available(iOS 27.0, macOS 27.0, *), let key = keys.key(for: backend) {
            let model = ChatCompletionsLanguageModel(
                name: configuration.model(for: backend),
                url: URL(string: backend == .openAI ? "https://api.openai.com/v1" : "https://openrouter.ai/api/v1")!,
                additionalHeaders: ["Authorization": "Bearer \(key)"],
                supportsGuidedGeneration: true,
                reasoning: Self.wireReasoning(reasoning, for: backend)
            )
            return LanguageModelSession(model: model, instructions: instructions)
        }
        throw AIError.unavailable
    }

    /// OpenAI takes `reasoning_effort` (`none` turns it off); OpenRouter takes a `reasoning` object.
    @available(iOS 27.0, macOS 27.0, *)
    static func wireReasoning(_ reasoning: AIReasoning, for backend: AIBackend) -> ChatCompletionsLanguageModel
        .Reasoning?
    {
        switch backend {
        case .apple: nil
        case .openAI: .effort(reasoning == .off ? "none" : reasoning.rawValue)
        case .openRouter: .openRouter(enabled: reasoning != .off, effort: reasoning == .off ? nil : reasoning.rawValue)
        }
    }
}

@MainActor
struct AILanguageModelGenerator: AIStructuredGenerator {
    let factory: AISessionFactory
    let backend: AIBackend

    func generate<Value: Generable>(
        _ type: Value.Type, instructions: String, prompt: String, maximumResponseTokens: Int
    ) async throws -> Value {
        try Task.checkCancellation()
        let session = try factory.makeSession(backend: backend, instructions: instructions)
        do {
            let result = try await session.respond(
                to: prompt, generating: type,
                options: GenerationOptions(maximumResponseTokens: maximumResponseTokens)
            )
            try Task.checkCancellation()
            return result.content
        } catch {
            if Task.isCancelled || error is CancellationError { throw CancellationError() }
            throw Self.classify(error)
        }
    }

    static func classify(_ error: any Error) -> AIError {
        if let urlError = error as? URLError { return .network(urlError.code.rawValue) }
        if error is DecodingError { return .decodingFailure }
        if #available(iOS 27.0, macOS 27.0, *) {
            if error is GeneratedContent.ParsingError { return .decodingFailure }
            if case LanguageModelError.contextSizeExceeded = error { return .contextSizeExceeded }
            if let request = error as? ChatCompletionsLanguageModel.RequestError {
                switch request {
                case .invalidStreamData, .incompleteResponse: return .decodingFailure
                case .truncatedResponse: return .responseTruncated
                case .httpError(let status, let data):
                    // Inspect only a machine-readable code. Never retain or surface the response body.
                    if let envelope = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                        let details = envelope["error"] as? [String: Any],
                        details["code"] as? String == "context_length_exceeded"
                    {
                        return .contextSizeExceeded
                    }
                    return .providerHTTPStatus(status)
                default: break
                }
            }
            if let provider = error as? ChatCompletionsLanguageModel.APIError {
                if provider.code == "context_length_exceeded" { return .contextSizeExceeded }
                // An error event after HTTP 200 carries the status the provider would have sent.
                if let status = provider.code.flatMap(Int.init), (400..<600).contains(status) {
                    return .providerHTTPStatus(status)
                }
            }
        }
        if let legacy = error as? LanguageModelSession.GenerationError {
            switch legacy {
            case .exceededContextWindowSize: return .contextSizeExceeded
            case .decodingFailure: return .decodingFailure
            default: break
            }
        }
        return .requestFailed
    }
}
