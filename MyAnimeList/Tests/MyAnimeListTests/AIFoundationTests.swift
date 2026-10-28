//
//  AIFoundationTests.swift
//  AniShelf
//
//  Created by OpenAI Codex on behalf of Samuel He on 2026/10/28.
//

import DataProvider
import Foundation
import FoundationModels
import Security
import Testing

@testable import MyAnimeList

@MainActor
struct AIFoundationTests {
    private func items(_ count: Int) -> [AIBatchItem<LibraryEntryIdentity>] {
        (0..<count).map {
            AIBatchItem(identity: LibraryEntryIdentity(entryType: .movie, tmdbID: $0), text: "card\($0)")
        }
    }

    @Test func availabilityHonorsOSKeysAndExplicitPreference() {
        let name = "ai-tests-\(UUID())"
        let defaults = UserDefaults(suiteName: name)!
        defer { defaults.removePersistentDomain(forName: name) }
        let config = AIConfiguration(defaults: defaults)
        let oldOS = AIAvailability(
            apple: .unavailable(.deviceNotEligible), supportsProviders: false, keyedProviders: [.openAI])
        #expect(config.resolvedBackend(availability: oldOS) == nil)
        #expect(oldOS.reason(for: .openAI) == .requiresOS27)
        let available = AIAvailability(apple: .available, supportsProviders: true, keyedProviders: [.openRouter])
        #expect(config.resolvedBackend(availability: available) == .apple)
        config.selectedBackend = .openRouter
        #expect(config.resolvedBackend(availability: available) == .openRouter)
        config.selectedBackend = .openAI
        #expect(config.resolvedBackend(availability: available) == .apple)
        #expect(available.reason(for: .openAI) == .missingKey)
        #expect(config.model(for: .openAI) == "gpt-6-luna")
        config.setModel(" custom-model ", for: .openRouter)
        #expect(AIConfiguration(defaults: defaults).model(for: .openRouter) == "custom-model")
    }

    @Test func keyStorageSeparatesProvidersAndPreservesKeyOnFailure() {
        let fake = AIKeychainFake()
        let keys = AIProviderKeyStorage(keychain: fake.client)
        #expect(keys.save(" first ", for: .openAI))
        #expect(keys.save("second", for: .openRouter))
        #expect(keys.key(for: .openAI) == "first")
        #expect(keys.key(for: .openRouter) == "second")
        #expect(fake.lastQuery?[kSecAttrSynchronizable as String] as? Bool == false)
        #expect(
            fake.lastAttributes?[kSecAttrAccessible as String] as? String
                == kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly as String)
        fake.updateStatus = errSecInteractionNotAllowed
        #expect(!keys.save("replacement", for: .openAI))
        #expect(keys.key(for: .openAI) == "first")
        #expect(!keys.save("  ", for: .openAI))
        #expect(!keys.save("ignored", for: .apple))
        #expect(keys.delete(for: .openRouter))
        #expect(keys.key(for: .openRouter) == nil)
        #expect(keys.key(for: .openAI) == "first")
    }

    @Test func budgetIncludesReservationsAndUsesConservativeUnicodeEstimate() async throws {
        let budget = AIContextBudget(
            contextSize: 100, reservedTokens: 20, maximumResponseTokens: 30, countPrompt: { $0.count })
        #expect(try await budget.fits(String(repeating: "x", count: 50)))
        #expect(try await !budget.fits(String(repeating: "x", count: 51)))
        #expect(AIContextBudget.estimateTokens("日本語") > AIContextBudget.estimateTokens("abc"))
        let cjkEstimate = AIContextBudget.estimateTokens(String(repeating: "文", count: 500))
        #expect(cjkEstimate >= 500 && cjkEstimate < 1000)
        #expect(AIContextBudget.estimateTokens(String(repeating: "a", count: 500)) < 250)
        let exhausted = AIContextBudget(contextSize: 10, reservedTokens: 20, maximumResponseTokens: 1)
        #expect(try await !exhausted.fits("x"))
    }

    @Test func providerBudgetFitsTinyRequestWithoutAppleInference() async throws {
        let budget = try await AIContextBudget.make(
            backend: .openRouter, instructions: "Select matching cards.", generating: AIBatchSelection.self,
            maximumResponseTokens: 128
        )
        #expect(budget.contextSize > 0)
        #expect(try await budget.fits("0: sample"))
        let defaultBudget = try await AIContextBudget.make(
            backend: .openAI, instructions: "Select matching cards.", generating: AIBatchSelection.self
        )
        #expect(defaultBudget.maximumResponseTokens == 512)
        let reasoningBudget = try await AIContextBudget.make(
            backend: .openAI, instructions: "Select matching cards.", generating: AIBatchSelection.self,
            reasoning: .low
        )
        #expect(reasoningBudget.maximumResponseTokens == 2048)
        #expect(try await reasoningBudget.fits("0: sample"))
    }

    @Test func packingCountsWholePromptAtBoundaryAndMapsOnlyLocalIndices() async throws {
        let fake = AIOutputFake<AIBatchSelection> { _, _ in AIBatchSelection(matchingIndices: [-1, 0, 1, 1, 2, 900]) }
        let input = items(3)
        // Derive the exact two-card prompt length from a first pass, using the public seam.
        let roomy = AIContextBudget(
            contextSize: 10000, reservedTokens: 0, maximumResponseTokens: 1, countPrompt: { $0.count })
        _ = try await AIBatchRunner(generator: fake, budget: roomy, instructions: "classify").run(
            Array(input.prefix(2)), generating: AIBatchSelection.self)
        let exact = try #require(fake.prompts.first).count
        fake.prompts = []
        let budget = AIContextBudget(
            contextSize: exact + 1, reservedTokens: 0, maximumResponseTokens: 1, countPrompt: { $0.count })
        var progress: [Int] = []
        let result = try await AIBatchRunner(generator: fake, budget: budget, instructions: "classify").run(
            input, generating: AIBatchSelection.self
        ) {
            done, _ in progress.append(done)
        }
        #expect(fake.prompts.count == 2)
        #expect(fake.prompts[0].count == exact)
        #expect(fake.prompts[1].contains("0: \"card2\""))
        #expect(result.values.map(\.identity) == input.map(\.identity))
        #expect(result.failures.isEmpty)
        #expect(progress.last == 3)
        #expect(!fake.prompts.joined().contains("movie:"))
    }

    @Test(arguments: [AIError.contextSizeExceeded, .decodingFailure, .responseTruncated])
    func retrySplitsOnlyOnceAndContinuesAfterFailedHalf(_ failure: AIError) async throws {
        let fake = AIOutputFake<AIBatchSelection> { call, _ in
            if call <= 2 { throw failure }
            return AIBatchSelection(matchingIndices: [0, 99])
        }
        let budget = AIContextBudget(contextSize: 10000, reservedTokens: 0, maximumResponseTokens: 10)
        let input = items(4)
        let result = try await AIBatchRunner(generator: fake, budget: budget, instructions: "classify").run(
            input, generating: AIBatchSelection.self)
        #expect(fake.prompts.count == 3)
        #expect(result.failures.count == 1)
        #expect(result.failures.first?.identities == Array(input.prefix(2)).map(\.identity))
        #expect(result.values.map(\.identity) == [input[2].identity])
    }

    @Test func nonRetryableFailureDoesNotBlockLaterBatchAndOversizeIsReported() async throws {
        let fake = AIOutputFake<AIBatchSelection> { call, _ in
            if call == 1 { throw AIError.requestFailed }
            return AIBatchSelection(matchingIndices: [0])
        }
        let budget = AIContextBudget(
            contextSize: 2, reservedTokens: 0, maximumResponseTokens: 1,
            countPrompt: { prompt in
                if prompt.contains("oversize") { return 100 }
                return prompt.components(separatedBy: "\n").count - 1
            })
        var input = items(2)
        input.append(AIBatchItem(identity: LibraryEntryIdentity(entryType: .series, tmdbID: 90), text: "oversize"))
        let result = try await AIBatchRunner(generator: fake, budget: budget, instructions: "classify").run(
            input, generating: AIBatchSelection.self)
        #expect(fake.prompts.count == 2)
        #expect(result.values.map(\.identity) == [input[1].identity])
        #expect(result.failures.map(\.reason).contains(.itemTooLarge))
        #expect(result.failures.map(\.reason).contains(.requestFailed))
    }

    @Test func cancellationStopsBeforeAnotherRequest() async throws {
        let fake = AIOutputFake<AIBatchSelection> { _, _ in throw CancellationError() }
        let budget = AIContextBudget(contextSize: 10000, reservedTokens: 0, maximumResponseTokens: 10)
        await #expect(throws: CancellationError.self) {
            _ = try await AIBatchRunner(generator: fake, budget: budget, instructions: "classify").run(
                items(3), generating: AIBatchSelection.self)
        }
        #expect(fake.prompts.count == 1)
    }

    @Test func proposalSelectionIsTransient() {
        var proposal = AIProposal(items: [AIProposal<Int>.Item(value: 1), .init(value: 2)])
        proposal.items[0].isAccepted = false
        #expect(proposal.acceptedValues == [2])
        proposal.items.removeAll()
        #expect(proposal.acceptedValues.isEmpty)
    }

    @Test func genericPayloadsAndLineIDsSurviveSplitAndIndexValidation() async throws {
        let fake = AIOutputFake<AITestAssignments> { call, _ in
            if call == 1 { throw AIError.responseTruncated }
            return AITestAssignments(assignments: [
                AITestAssignment(index: 0, anchor: "episode-\(call)"),
                AITestAssignment(index: 0, anchor: "duplicate"),
                AITestAssignment(index: 99, anchor: "invented")
            ])
        }
        let budget = AIContextBudget(contextSize: 10000, reservedTokens: 0, maximumResponseTokens: 256)
        let input = [
            AIBatchItem(identity: "line-A", text: "first line"), AIBatchItem(identity: "line-B", text: "second line")
        ]
        let result = try await AIBatchRunner(generator: fake, budget: budget, instructions: "Assign each line.")
            .run(input, generating: AITestAssignments.self)
        #expect(result.values.map(\.identity) == ["line-A", "line-B"])
        #expect(result.values.map(\.value) == ["episode-2", "episode-3"])
        #expect(result.failures.isEmpty)
        #expect(!fake.prompts.joined().contains("line-A"))
    }

    @Test func packingDoesNotCountEveryGrowingPrefix() async throws {
        var counterCalls = 0
        let budget = AIContextBudget(
            contextSize: 10000, reservedTokens: 0, maximumResponseTokens: 256,
            countPrompt: {
                counterCalls += 1
                return $0.count
            }
        )
        let fake = AIOutputFake<AIBatchSelection> { _, _ in AIBatchSelection(matchingIndices: [0]) }
        let result = try await AIBatchRunner(generator: fake, budget: budget, instructions: "Select.")
            .run(items(64), generating: AIBatchSelection.self)
        #expect(result.failures.isEmpty)
        #expect(fake.prompts.count == 1)
        #expect(counterCalls <= 4)
    }

    @Test(arguments: ["truncatedPartial", "truncatedValid", "missingPartial", "missingValid"])
    func adapterRejectsTruncatedAndUnterminatedStreams(_ scenario: String) async throws {
        guard #available(iOS 27.0, macOS 27.0, *) else { return }
        let model = mockProvider(scenario)
        do {
            _ = try await LanguageModelSession(model: model).respond(
                to: "Select.", generating: AIBatchSelection.self
            )
            Issue.record("Accepted a truncated or unterminated stream")
        } catch {
            let expected: AIError = scenario.hasPrefix("truncated") ? .responseTruncated : .decodingFailure
            #expect(AILanguageModelGenerator.classify(error) == expected)
        }
    }

    @Test(arguments: ["finishOnly", "doneOnly"])
    func adapterAcceptsExplicitCompletionSignals(_ scenario: String) async throws {
        guard #available(iOS 27.0, macOS 27.0, *) else { return }
        let response = try await LanguageModelSession(model: mockProvider(scenario)).respond(
            to: "Select.", generating: AIBatchSelection.self
        )
        #expect(response.content.matchingIndices == [0, 1])
    }

    @Test(arguments: [AIBackend.openAI, .openRouter])
    func reasoningIsOffByDefaultOnTheWire(_ backend: AIBackend) async throws {
        guard #available(iOS 27.0, macOS 27.0, *) else { return }
        let factory = AISessionFactory(
            configuration: AIConfiguration(defaults: .standard), keys: AIProviderKeyStorage())
        #expect(factory.reasoning == .off)
        // The mock answers [0, 1] only when the body carries exactly this backend's "off" form.
        let model = mockProvider(
            backend == .openAI ? "reasoningOffOpenAI" : "reasoningOffOpenRouter",
            reasoning: AISessionFactory.wireReasoning(factory.reasoning, for: backend)
        )
        let response = try await LanguageModelSession(model: model).respond(
            to: "Select.", generating: AIBatchSelection.self
        )
        #expect(response.content.matchingIndices == [0, 1])
    }

    @available(iOS 27.0, macOS 27.0, *)
    private func mockProvider(
        _ scenario: String, reasoning: ChatCompletionsLanguageModel.Reasoning? = nil
    ) -> ChatCompletionsLanguageModel {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [AIStreamURLProtocol.self]
        return ChatCompletionsLanguageModel(
            name: "mock", url: URL(string: "https://ai-foundation.invalid/\(scenario)/v1")!,
            reasoning: reasoning, urlSessionConfiguration: configuration
        )
    }

    @Test func providerErrorsAreReducedToSafeRetryCategories() throws {
        guard #available(iOS 27.0, macOS 27.0, *) else { return }
        let overflow = ChatCompletionsLanguageModel.RequestError.httpError(
            statusCode: 400,
            data: Data(#"{"error":{"code":"context_length_exceeded","message":"private response"}}"#.utf8)
        )
        #expect(AILanguageModelGenerator.classify(overflow) == .contextSizeExceeded)
        #expect(
            AILanguageModelGenerator.classify(ChatCompletionsLanguageModel.RequestError.invalidStreamData)
                == .decodingFailure)
        let denied = ChatCompletionsLanguageModel.RequestError.httpError(
            statusCode: 401, data: Data("private response".utf8)
        )
        #expect(AILanguageModelGenerator.classify(denied) == .providerHTTPStatus(401))
        #expect(AILanguageModelGenerator.classify(URLError(.notConnectedToInternet)) == .network(-1009))
    }

    #if DEBUG
        @Test func debugInjectionUsesNormalStorageAndSkipsFixtures() {
            let name = "ai-debug-tests-\(UUID())"
            let defaults = UserDefaults(suiteName: name)!
            defer { defaults.removePersistentDomain(forName: name) }
            let fake = AIKeychainFake()
            let keys = AIProviderKeyStorage(keychain: fake.client)
            let config = AIConfiguration(defaults: defaults)
            let environment = [
                "ANISHELF_AI_BACKEND": "openRouter", "ANISHELF_AI_API_KEY": "test-placeholder",
                "ANISHELF_AI_MODEL": "test-model"
            ]
            #expect(
                AIDebugLaunch.inject(environment: environment, configuration: config, keys: keys, isFixture: true)
                    == nil)
            #expect(fake.values.isEmpty)
            #expect(config.selectedBackend == nil)
            #expect(
                AIDebugLaunch.inject(environment: environment, configuration: config, keys: keys, isFixture: false)
                    == .openRouter)
            #expect(keys.key(for: .openRouter) == "test-placeholder")
            #expect(config.selectedBackend == .openRouter)
            #expect(config.model(for: .openRouter) == "test-model")
            #expect(!defaults.dictionaryRepresentation().values.contains { ($0 as? String) == "test-placeholder" })
        }
    #endif
}

@Generable
fileprivate struct AITestAssignment {
    var index: Int
    var anchor: String
}

@Generable
fileprivate struct AITestAssignments: AIBatchOutput {
    var assignments: [AITestAssignment]
    var indexedValues: [AIIndexedValue<String>] {
        assignments.map { AIIndexedValue(index: $0.index, value: $0.anchor) }
    }
}

/// Immutable URL-selected fixtures; parallel tests share no mutable response handler.
fileprivate final class AIStreamURLProtocol: URLProtocol {
    override class func canInit(with request: URLRequest) -> Bool { request.url?.host == "ai-foundation.invalid" }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        let url = request.url!
        let scenario = url.pathComponents[1]
        var content = scenario.hasSuffix("Partial") ? #"{"matchingIndices":[0,1,"# : #"{"matchingIndices":[0,1]}"#
        if scenario.hasPrefix("reasoningOff") && !Self.carriesReasoningOff(request, scenario: scenario) {
            content = #"{"matchingIndices":[]}"#
        }
        let chunk: [String: Any] = ["id": "mock", "model": "mock", "choices": [["delta": ["content": content]]]]
        let data = try! JSONSerialization.data(withJSONObject: chunk)
        var body = "data: \(String(decoding: data, as: UTF8.self))\n\n"
        if scenario.hasPrefix("truncated") || scenario == "finishOnly" || scenario.hasPrefix("reasoningOff") {
            let reason = scenario.hasPrefix("truncated") ? "length" : "stop"
            body +=
                "data: {\"id\":\"mock\",\"model\":\"mock\",\"choices\":[{\"delta\":{},\"finish_reason\":\"\(reason)\"}]}\n\n"
        }
        if scenario.hasPrefix("truncated") || scenario == "doneOnly" { body += "data: [DONE]\n\n" }
        let response = HTTPURLResponse(
            url: url, statusCode: 200, httpVersion: nil, headerFields: ["Content-Type": "text/event-stream"])!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Data(body.utf8))
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}

    /// URLProtocol sees the body as a stream, not `httpBody`.
    private static func carriesReasoningOff(_ request: URLRequest, scenario: String) -> Bool {
        guard let stream = request.httpBodyStream else { return false }
        stream.open()
        defer { stream.close() }
        var data = Data()
        var buffer = [UInt8](repeating: 0, count: 4096)
        while stream.hasBytesAvailable {
            let count = stream.read(&buffer, maxLength: buffer.count)
            guard count > 0 else { break }
            data.append(buffer, count: count)
        }
        guard let body = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return false }
        if scenario == "reasoningOffOpenAI" {
            return body["reasoning_effort"] as? String == "none" && body["reasoning"] == nil
        }
        let reasoning = body["reasoning"] as? [String: Any]
        return reasoning?["enabled"] as? Bool == false && reasoning?["effort"] == nil
            && body["reasoning_effort"] == nil
    }
}

@MainActor
fileprivate final class AIOutputFake<Output: Generable>: AIStructuredGenerator {
    var prompts: [String] = []
    let respond: (Int, String) throws -> Output

    init(respond: @escaping (Int, String) throws -> Output) { self.respond = respond }

    func generate<Value: Generable>(
        _ type: Value.Type, instructions: String, prompt: String, maximumResponseTokens: Int
    ) async throws -> Value {
        prompts.append(prompt)
        return try Value(respond(prompts.count, prompt).generatedContent)
    }
}

fileprivate final class AIKeychainFake {
    var values: [String: Data] = [:]
    var updateStatus: OSStatus?
    var lastQuery: [String: Any]?
    var lastAttributes: [String: Any]?

    var client: TMDbAPIKeyStorageKeychainClient {
        TMDbAPIKeyStorageKeychainClient(
            add: { query in
                self.lastQuery = query
                self.lastAttributes = query
                self.values[query[kSecAttrAccount as String] as! String] = query[kSecValueData as String] as? Data
                return errSecSuccess
            },
            update: { query, attributes in
                self.lastQuery = query
                self.lastAttributes = attributes
                if let status = self.updateStatus { return status }
                let account = query[kSecAttrAccount as String] as! String
                guard self.values[account] != nil else { return errSecItemNotFound }
                self.values[account] = attributes[kSecValueData as String] as? Data
                return errSecSuccess
            },
            delete: { query in
                self.values.removeValue(forKey: query[kSecAttrAccount as String] as! String)
                return errSecSuccess
            },
            copyMatching: { query in
                self.lastQuery = query
                if let value = self.values[query[kSecAttrAccount as String] as! String] {
                    return (errSecSuccess, value as AnyObject)
                }
                return (errSecItemNotFound, nil)
            }
        )
    }
}
