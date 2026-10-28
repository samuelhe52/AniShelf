//
//  AIDebugLaunch.swift
//  AniShelf
//
//  Created by OpenAI Codex on behalf of Samuel He on 2026/10/28.
//

#if DEBUG
    import Foundation
    import FoundationModels

    @MainActor
    enum AIDebugLaunch {
        /// No injection or provider traffic in fixture launches.
        ///
        /// Never print the environment.
        @discardableResult
        static func inject(
            environment: [String: String], configuration: AIConfiguration,
            keys: AIProviderKeyStorage, isFixture: Bool
        ) -> AIBackend? {
            guard !isFixture,
                let rawBackend = environment["ANISHELF_AI_BACKEND"],
                let backend = AIBackend(rawValue: rawBackend), backend != .apple,
                let key = environment["ANISHELF_AI_API_KEY"], keys.save(key, for: backend)
            else { return nil }
            configuration.selectedBackend = backend
            if let model = environment["ANISHELF_AI_MODEL"] { configuration.setModel(model, for: backend) }
            return backend
        }

        @Generable
        struct SmokeResponse {
            var value: Int
        }

        /// Explicit opt-in, one synthetic typed request, no library context or response logging.
        static func start(configuration: AIConfiguration, isFixture: Bool) {
            let environment = ProcessInfo.processInfo.environment
            let keys = AIProviderKeyStorage()
            let backend = inject(
                environment: environment, configuration: configuration, keys: keys, isFixture: isFixture
            )
            guard !isFixture, environment["ANISHELF_AI_SMOKE_TEST"] == "1" else { return }
            let resultURL = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
                .appendingPathComponent("ai-foundation-smoke-result.txt")
            try? FileManager.default.removeItem(at: resultURL)
            guard let backend else {
                try? "FAIL_CONFIGURATION".write(to: resultURL, atomically: true, encoding: .utf8)
                return
            }
            let reportedContextSize = SystemLanguageModel.default.contextSize
            Task {
                let status: String
                do {
                    let generator = AILanguageModelGenerator(
                        factory: AISessionFactory(configuration: configuration, keys: keys), backend: backend
                    )
                    let instructions = "Return the requested integer in the value field."
                    let budget = try await AIContextBudget.make(
                        backend: backend, instructions: instructions, generating: SmokeResponse.self
                    )
                    guard try await budget.fits("Return 7.") else { throw AIError.itemTooLarge }
                    let response = try await generator.generate(
                        SmokeResponse.self, instructions: instructions, prompt: "Return 7.",
                        maximumResponseTokens: budget.maximumResponseTokens
                    )
                    status = response.value == 7 ? "PASS" : "FAIL_VALUE"
                } catch {
                    // Never serialize an underlying provider error; it may echo request content.
                    switch error as? AIError {
                    case .providerHTTPStatus(let code): status = "FAIL_HTTP_\(code)"
                    case .network(let code): status = "FAIL_NETWORK_\(code)"
                    case .itemTooLarge: status = "FAIL_BUDGET"
                    case .unavailable: status = "FAIL_UNAVAILABLE"
                    case .contextSizeExceeded: status = "FAIL_CONTEXT"
                    case .decodingFailure: status = "FAIL_DECODING"
                    case .responseTruncated: status = "FAIL_TRUNCATED"
                    default: status = "FAIL_REQUEST"
                    }
                }
                let result = "\(status)\nreportedContextSize=\(reportedContextSize)\n"
                try? result.write(to: resultURL, atomically: true, encoding: .utf8)
            }
        }
    }
#endif
