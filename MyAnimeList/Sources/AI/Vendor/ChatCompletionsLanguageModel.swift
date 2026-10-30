//===----------------------------------------------------------------------===//
//
// This source file is part of the Foundation Models open source project.
//
// Copyright © 2024-2027 Apple Inc. and the Foundation Models project authors.
//
// Licensed under the Apache License v2.0
//
// See LICENSE.txt for license information
//
// MODIFIED by OpenAI Codex on behalf of Samuel He on 2026/10/28.
// Source: apple/foundation-models-utilities, cc3820def1fe016bc6cd49d958cd2f2a29be76a8.
// Changes: OS 27 availability, app-compatible imports/formatting, and rejection
// of truncated provider responses and streams without a completion signal.
// MODIFIED by Claude Code on behalf of Samuel He on 2026/10/28.
// Changes: optional provider reasoning control (`reasoning_effort` or OpenRouter `reasoning`).
// MODIFIED by Claude Code on behalf of Samuel He on 2026/10/29.
// Changes: the response_format schema omits `x-order`, which Anthropic models reject;
// `tools` and `tool_choice` are sent only with tools, since Google rejects a bare choice.
//
//===----------------------------------------------------------------------===//
import Foundation
import FoundationModels

#if canImport(FoundationNetworking)
    import FoundationNetworking
#endif
#if canImport(CoreImage)
    import CoreImage
    import UniformTypeIdentifiers
#endif

/// A `LanguageModel` that talks to any OpenAI-compatible
/// `/chat/completions` endpoint, streaming results back through the
/// Foundation Models framework.
///
/// Use this model to drive a `LanguageModelSession` against any remote
/// service that implements the OpenAI Chat Completions API.
///
/// ```swift
/// let model = ChatCompletionsLanguageModel(
///     name: "your-model-name",
///     url: URL(string: "https://api.example.com")!,
///     additionalHeaders: ["Authorization": "Bearer \(apiKey)"]
/// )
///
/// let session = LanguageModelSession(model: model)
/// let response = try await session.respond(to: "Hello!")
/// ```
@available(iOS 27.0, macOS 27.0, *)
public struct ChatCompletionsLanguageModel: Sendable, LanguageModel {
    /// The name of the underlying model, sent in the `model` field of each
    /// chat completion request.
    public var name: String

    /// The base URL of the chat completions endpoint.
    ///
    /// The path
    /// `/v1/chat/completions` is appended automatically when the supplied
    /// URL does not already include a version segment matching `v<digits>`
    /// (for example `v1`, `v2`, or `v3`). When a version segment is
    /// present, only `/chat/completions` is appended.
    public var url: URL

    /// Headers added to every outgoing request, merged on top of the defaults.
    ///
    /// Use this to provide authorization tokens or other
    /// vendor-specific headers.
    public var additionalHeaders: [String: String]

    public var supportsGuidedGeneration: Bool

    /// Reasoning control for providers that accept it. `nil` sends nothing, so the provider default applies.
    public var reasoning: Reasoning?

    /// The two wire forms OpenAI-compatible endpoints use for reasoning control.
    public enum Reasoning: Hashable, Sendable {
        /// Top-level `reasoning_effort`, as OpenAI accepts it (for example `"none"` or `"low"`).
        case effort(String)
        /// OpenRouter's `reasoning` object.
        case openRouter(enabled: Bool, effort: String?)
    }

    // Overridden in tests to inject a URLSession with mock protocol handlers.
    var urlSession: URLSession?

    /// Creates a chat completions language model.
    ///
    /// - Parameters:
    ///   - name: The model identifier sent in the `model` field of each
    ///     request.
    ///   - url: The base URL of the chat completions endpoint.
    ///   - additionalHeaders: Headers to merge on top of the defaults
    ///     (for example, an `Authorization` header).
    ///   - supportsGuidedGeneration: Whether the endpoint supports the
    ///     `response_format` field for structured output. Defaults to `true`.
    ///   - reasoning: Reasoning control to send with each request. `nil` sends none.
    ///   - urlSessionConfiguration: An optional `URLSessionConfiguration` used
    ///     to build the `URLSession` that drives requests. Use this to tune
    ///     timeouts, proxies, or other transport settings. When `nil`, an
    ///     ephemeral configuration is used.
    public init(
        name: String,
        url: URL,
        additionalHeaders: [String: String] = [:],
        supportsGuidedGeneration: Bool = true,
        reasoning: Reasoning? = nil,
        urlSessionConfiguration: URLSessionConfiguration? = nil
    ) {
        self.name = name
        self.url = url
        self.additionalHeaders = additionalHeaders
        self.supportsGuidedGeneration = supportsGuidedGeneration
        self.reasoning = reasoning
        self.urlSession = urlSessionConfiguration.map { URLSession(configuration: $0) }
    }

    // Implementation of LanguageModel Protocol
    public var capabilities: LanguageModelCapabilities {
        if supportsGuidedGeneration {
            LanguageModelCapabilities([.vision, .toolCalling, .reasoning, .guidedGeneration])
        } else {
            LanguageModelCapabilities([.vision, .toolCalling, .reasoning])
        }
    }

    public var executorConfiguration: Executor.Configuration {
        Executor.Configuration(
            modelName: name,
            url: url,
            additionalHeaders: additionalHeaders,
            reasoning: reasoning,
            urlSession: urlSession
        )
    }

    /// An error returned by the chat completions endpoint in the body of a
    /// failed request or a streaming error event.
    ///
    /// Servers may populate any subset of the optional fields.
    public struct APIError: LocalizedError {
        /// A human-readable explanation of the error returned by the server.
        public var message: String

        /// The error category reported by the server (for example,
        /// `"invalid_request_error"`).
        public var type: String?

        /// The name of the request parameter associated with the error,
        /// when applicable.
        public var param: String?

        /// A short machine-readable error code provided by the server.
        public var code: String?

        /// Creates a new API error.
        ///
        /// - Parameters:
        ///   - message: A human-readable explanation of the error.
        ///   - type: The error category reported by the server.
        ///   - param: The request parameter associated with the error.
        ///   - code: A short machine-readable error code.
        public init(
            message: String,
            type: String? = nil,
            param: String? = nil,
            code: String? = nil
        ) {
            self.message = message
            self.type = type
            self.param = param
            self.code = code
        }
    }

    /// An error raised by ``ChatCompletionsLanguageModel`` when a request
    /// cannot be issued or its response cannot be parsed.
    public enum RequestError: LocalizedError {
        /// The request could not be constructed because of invalid input.
        /// The associated value contains a human-readable description.
        case invalidRequest(_ description: String)

        /// A streaming chunk could not be decoded as a chat completion event.
        case invalidStreamData

        /// The provider exhausted its completion budget; partial output must not be accepted.
        case truncatedResponse

        /// The stream ended without a successful finish reason or a [DONE] marker.
        case incompleteResponse

        /// The endpoint returned a non-200 HTTP status code. The associated
        /// values contain the status code and the raw response body.
        case httpError(statusCode: Int, data: Data)

        public var errorDescription: String? {
            switch self {
            case .invalidRequest(let description):
                "Invalid request: \(description)"
            case .invalidStreamData:
                "Invalid streaming data received"
            case .truncatedResponse:
                "Provider response exceeded its completion budget"
            case .incompleteResponse:
                "Provider stream ended without completion"
            case .httpError(let statusCode, let data):
                """
                HTTP error with status code \(statusCode):
                \(String(data: data, encoding: .utf8) ?? data.description)
                """
            }
        }
    }

    /// The wire format of an error envelope returned by the chat completions
    /// endpoint, used internally to decode error responses before raising
    /// them as ``APIError``.
    struct ErrorResponse: Codable, Sendable {
        var error: APIError

        struct APIError: Codable, Sendable {
            var message: String
            var type: String?
            var param: String?
            var code: String?

            enum CodingKeys: String, CodingKey {
                case message, type, param, code
            }

            init(from decoder: any Decoder) throws {
                let container = try decoder.container(keyedBy: CodingKeys.self)
                message = try container.decode(String.self, forKey: .message)
                type = try container.decodeIfPresent(String.self, forKey: .type)
                param = try container.decodeIfPresent(String.self, forKey: .param)
                // AniShelf modification: OpenRouter reports mid-stream failures with a numeric
                // HTTP-style code (`{"code":502}`), where OpenAI sends a string.
                if let number = try? container.decodeIfPresent(Int.self, forKey: .code) {
                    code = String(number)
                } else {
                    code = try container.decodeIfPresent(String.self, forKey: .code)
                }
            }
        }
    }

    public struct Executor: LanguageModelExecutor {
        public typealias Model = ChatCompletionsLanguageModel
        private let configuration: Configuration

        public init(configuration: Configuration) {
            self.configuration = configuration
        }

        public struct Configuration: Hashable, Sendable {
            fileprivate let modelName: String
            fileprivate let url: URL
            fileprivate let additionalHeaders: [String: String]
            fileprivate let reasoning: Reasoning?
            fileprivate let urlSession: URLSession?

            public static func == (lhs: Configuration, rhs: Configuration) -> Bool {
                lhs.modelName == rhs.modelName
                    && lhs.url == rhs.url
                    && lhs.additionalHeaders == rhs.additionalHeaders
                    && lhs.reasoning == rhs.reasoning
            }

            public func hash(into hasher: inout Hasher) {
                hasher.combine(modelName)
                hasher.combine(url)
                hasher.combine(additionalHeaders)
                hasher.combine(reasoning)
            }
        }

        public func respond(
            to request: LanguageModelExecutorGenerationRequest,
            model: ChatCompletionsLanguageModel,
            streamingInto channel: LanguageModelExecutorGenerationChannel
        ) async throws {

            // Caller-supplied headers override the defaults on conflict.
            let headers = [
                "Content-Type": "application/json",
                "Accept": "text/event-stream",
                "User-Agent": Bundle.main.bundleIdentifier ?? "com.apple.FoundationModels"
            ].merging(
                configuration.additionalHeaders,
                uniquingKeysWith: { _, custom in custom }
            )

            // Tests inject a URLSession; production uses a fresh ephemeral one.
            let client = ChatCompletionsClient(
                baseURL: configuration.url,
                headers: headers,
                session: configuration.urlSession ?? URLSession(configuration: .ephemeral)
            )

            // Translate the framework's request into the OpenAI-compatible wire format.
            let chatRequest = ChatCompletionsClient.ChatCompletionRequest(
                model: configuration.modelName,
                messages: try convertedTranscript(request.transcript),
                temperature: request.generationOptions.temperature,
                topP: try request.generationOptions.samplingMode.map(topP),
                maxCompletionTokens: request.generationOptions.maximumResponseTokens,
                // AniShelf modification: Google rejects `tool_choice` without tool
                // declarations, so a request without tools sends neither field.
                tools: request.enabledToolDefinitions.isEmpty
                    ? nil
                    : request.enabledToolDefinitions.map { tool in
                        ChatCompletionsClient.Tool(
                            function: ChatCompletionsClient.Tool.Function(
                                name: tool.name,
                                description: tool.description,
                                parameters: tool.parameters
                            )
                        )
                    },
                toolChoice: request.enabledToolDefinitions.isEmpty
                    ? nil
                    : ChatCompletionsClient.ChatCompletionRequest.ToolChoice(
                        mode: {
                            switch request.generationOptions.toolCallingMode?.kind {
                            case .allowed, .none: .auto
                            case .required: .required
                            case .disallowed: .none
                            @unknown default: .auto
                            }
                        }()
                    ),
                responseFormat: request.schema.map { schema in
                    ChatCompletionsClient.ResponseFormat(
                        jsonSchema: ChatCompletionsClient.ResponseFormat.JSONSchemaWrapper(
                            name: schema.name,
                            schema: schema
                        )
                    )
                },
                reasoningEffort: {
                    if case .effort(let effort) = configuration.reasoning { effort } else { nil }
                }(),
                reasoning: {
                    if case .openRouter(let enabled, let effort) = configuration.reasoning {
                        ChatCompletionsClient.ChatCompletionRequest.ReasoningObject(enabled: enabled, effort: effort)
                    } else {
                        nil
                    }
                }()
            )

            // Stream the response back into the framework via `channel`.
            try await Self.processChunks(
                client.streamChatCompletions(request: chatRequest),
                into: channel
            )
        }

        private static func processChunks<ChunkSequence: AsyncSequence>(
            _ chunks: ChunkSequence,
            into channel: LanguageModelExecutorGenerationChannel
        ) async throws where ChunkSequence.Element == ChatCompletionsClient.ChatCompletionChunk {
            // Per-index `id`/`name` for tool calls. The first delta for a given
            // index supplies them; later deltas at the same index typically carry
            // only argument fragments and are routed using these latched values.
            // Argument accumulation is the framework's job — we just forward each
            // delta via `.appendArguments`.
            var toolCallRouting: [Int: (id: String, name: String)] = [:]

            // Stable entryIDs per event type for the duration of this stream.
            // Without these, interleaved reasoning/response/toolCalls chunks would
            // split into multiple transcript entries — the framework only coalesces
            // consecutive events of the same type into the trailing entry.
            let responseEntryID = UUID().uuidString
            let reasoningEntryID = UUID().uuidString
            let toolCallsEntryID = UUID().uuidString

            for try await chunk in chunks {
                if let delta = chunk.choices.first?.delta {
                    if let reasoning = delta.reasoningContent {
                        await channel.send(
                            .reasoning(
                                entryID: reasoningEntryID,
                                action: .appendText(reasoning, tokenCount: 1)
                            )
                        )
                    }

                    if let toolCallDeltas = delta.toolCalls {
                        for toolCallDelta in toolCallDeltas {
                            let existing = toolCallRouting[toolCallDelta.index] ?? (id: "", name: "")
                            let routing = (
                                id: existing.id + (toolCallDelta.id ?? ""),
                                name: existing.name + (toolCallDelta.function?.name ?? "")
                            )
                            toolCallRouting[toolCallDelta.index] = routing

                            guard !routing.id.isEmpty, !routing.name.isEmpty else { continue }

                            await channel.send(
                                .toolCalls(
                                    entryID: toolCallsEntryID,
                                    action: .toolCall(
                                        id: routing.id,
                                        name: routing.name,
                                        action: .appendArguments(
                                            toolCallDelta.function?.arguments ?? "",
                                            tokenCount: 1
                                        )
                                    )
                                )
                            )
                        }
                    } else if let text = delta.content {
                        await channel.send(
                            .response(
                                entryID: responseEntryID,
                                action: .appendText(text, tokenCount: 1)
                            )
                        )
                    }
                }

                // Send usage AFTER content so the authoritative cumulative total
                // overwrites any tokens credited by `appendText` for this chunk.
                if let usage = chunk.usage {
                    await channel.send(
                        .response(
                            entryID: responseEntryID,
                            action: .updateUsage(
                                input: .init(
                                    totalTokenCount: usage.promptTokens,
                                    cachedTokenCount: usage.promptTokensDetails?.cachedTokens ?? 0
                                ),
                                output: .init(
                                    totalTokenCount: usage.completionTokens,
                                    reasoningTokenCount: usage.completionTokensDetails?.reasoningTokens ?? 0
                                )
                            )
                        )
                    )
                }
            }
        }

        private func topP(_ sampling: GenerationOptions.SamplingMode) throws -> Double {
            switch sampling.kind {
            case .greedy:
                return 0

            case .randomTopK:
                throw ChatCompletionsLanguageModel.RequestError.invalidRequest(
                    "Top K sampling is not supported"
                )
            case .randomProbabilityThreshold(let threshold, let seed):
                guard seed == nil else {
                    throw ChatCompletionsLanguageModel.RequestError.invalidRequest(
                        "Setting a random seed is not supported"
                    )
                }
                return threshold
            @unknown default:
                throw ChatCompletionsLanguageModel.RequestError.invalidRequest(
                    "Unknown sampling mode \(sampling.kind) is not supported"
                )
            }
        }

        private func convertedTranscript(
            _ entries: some Collection<Transcript.Entry>
        ) throws -> [ChatCompletionsClient.ChatMessage] {

            // Converts a single transcript segment into chat-completion message content.
            func convertedSegment(
                _ segment: Transcript.Segment,
                in entry: Transcript.Entry
            ) throws -> [ChatCompletionsClient.MessageContent] {
                switch segment {
                case .text(let text):
                    return [
                        ChatCompletionsClient.MessageContent(
                            text: text.content
                        )
                    ]
                // Structured content is serialized to JSON text on the wire.
                case .structure(let structure):
                    return [
                        ChatCompletionsClient.MessageContent(
                            text: structure.content.jsonString
                        )
                    ]
                case .attachment(let attachment):
                    switch attachment.content {
                    case .image(let image):
                        #if canImport(CoreImage)
                            // Images are inlined as base64 data URLs (JPEG).
                            let base64String = image.cgImage.jpegData().base64EncodedString()
                            let dataURL = URL(string: "data:image/jpeg;base64,\(base64String)")!
                            let imageURL = ChatCompletionsClient.MessageContent.ImageURL(url: dataURL)
                            return [ChatCompletionsClient.MessageContent(imageURL: imageURL)]
                        #else
                            guard let url = image.url else {
                                throw LanguageModelError.unsupportedTranscriptContent(
                                    LanguageModelError.UnsupportedTranscriptContent(
                                        unsupportedContent: [entry],
                                        debugDescription:
                                            "Image attachment without a URL is not supported by \(Self.self) on this platform."
                                    )
                                )
                            }
                            let dataURL: URL
                            if url.scheme == "data" {
                                dataURL = url
                            } else {
                                let data = try Data(contentsOf: url)
                                let base64String = data.base64EncodedString()
                                dataURL = URL(string: "data:image/jpeg;base64,\(base64String)")!
                            }
                            let imageURL = ChatCompletionsClient.MessageContent.ImageURL(url: dataURL)
                            return [ChatCompletionsClient.MessageContent(imageURL: imageURL)]
                        #endif
                    // Plain `default`: `.data` attachments are 27.2 SDK cases that this 27.0 target can't name.
                    default:
                        throw LanguageModelError.unsupportedTranscriptContent(
                            LanguageModelError.UnsupportedTranscriptContent(
                                unsupportedContent: [entry],
                                debugDescription: "Attachment type not supported by \(Self.self)."
                            )
                        )
                    }
                @unknown default:
                    throw LanguageModelError.unsupportedTranscriptContent(
                        LanguageModelError.UnsupportedTranscriptContent(
                            unsupportedContent: [entry],
                            debugDescription: "Unknown segment type not supported by \(Self.self)"
                        )
                    )
                }
            }

            var messages: [ChatCompletionsClient.ChatMessage] = []
            // Reasoning entries are buffered and attached to the next assistant
            // message (response or toolCalls) via `reasoning_content`. If a turn
            // has only reasoning with no following assistant entry, it's emitted
            // as a standalone assistant message.
            var pendingReasoning: String? = nil

            func consumePendingReasoning() -> String? {
                defer { pendingReasoning = nil }
                return pendingReasoning
            }

            // Translate each transcript entry into one chat-completion message.
            for entry in entries {
                switch entry {
                case .instructions(let instructions):
                    // Instructions become system-role messages.
                    messages.append(
                        ChatCompletionsClient.ChatMessage(
                            role: .system,
                            content: try instructions.segments.flatMap { try convertedSegment($0, in: entry) }
                        )
                    )

                case .prompt(let prompt):
                    // User prompts; flush any orphaned reasoning as a message first.
                    if let reasoning = consumePendingReasoning() {
                        messages.append(
                            ChatCompletionsClient.ChatMessage(
                                role: .assistant,
                                reasoningContent: reasoning
                            )
                        )
                    }
                    messages.append(
                        ChatCompletionsClient.ChatMessage(
                            role: .user,
                            content: try prompt.segments.flatMap { try convertedSegment($0, in: entry) }
                        )
                    )

                case .toolCalls(let toolCalls):
                    // Tool calls ride along on an assistant message, with any buffered reasoning attached.
                    messages.append(
                        ChatCompletionsClient.ChatMessage(
                            role: .assistant,
                            toolCalls: toolCalls.map { call in
                                ChatCompletionsClient.ToolCall(
                                    id: call.id,
                                    function: ChatCompletionsClient.ToolCall.FunctionCall(
                                        name: call.toolName,
                                        arguments: call.arguments.jsonString
                                    )
                                )
                            },
                            reasoningContent: consumePendingReasoning()
                        )
                    )

                case .toolOutput(let toolOutput):
                    // Tool outputs become tool-role messages keyed by the originating call ID.
                    messages.append(
                        ChatCompletionsClient.ChatMessage(
                            role: .tool,
                            content: try toolOutput.segments.flatMap { try convertedSegment($0, in: entry) },
                            toolCallID: toolOutput.id
                        )
                    )

                case .response(let response):
                    // Assistant responses; attach any buffered reasoning to this message.
                    messages.append(
                        ChatCompletionsClient.ChatMessage(
                            role: .assistant,
                            content: try response.segments.flatMap { try convertedSegment($0, in: entry) },
                            reasoningContent: consumePendingReasoning()
                        )
                    )

                case .reasoning(let reasoning):
                    // Buffer reasoning text; it will attach to the next assistant entry.
                    let text = reasoning.segments.compactMap { segment -> String? in
                        if case .text(let textSegment) = segment { return textSegment.content }
                        return nil
                    }.joined()
                    pendingReasoning = (pendingReasoning ?? "") + text

                // Plain `default`: `.data` entries are 27.2 SDK cases that this 27.0 target can't name.
                default:
                    continue
                }
            }

            // Trailing reasoning with no following assistant entry — emit it solo.
            if let reasoning = consumePendingReasoning() {
                messages.append(
                    ChatCompletionsClient.ChatMessage(
                        role: .assistant,
                        reasoningContent: reasoning
                    )
                )
            }

            return messages
        }
    }
}

@available(iOS 27.0, macOS 27.0, *)
fileprivate struct ChatCompletionsClient {
    let baseURL: URL
    let headers: [String: String]
    let session: URLSession

    func streamChatCompletions(
        request: ChatCompletionRequest
    ) -> AsyncThrowingStream<ChatCompletionChunk, Swift.Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    let urlRequest = try buildURLRequest(for: request)
                    var didComplete = false
                    #if canImport(Darwin)
                        let (stream, response) = try await session.bytes(for: urlRequest)
                        let httpResponse = response as! HTTPURLResponse

                        guard httpResponse.statusCode == 200 else {
                            throw ChatCompletionsLanguageModel.RequestError.httpError(
                                statusCode: httpResponse.statusCode,
                                data: try await stream.reduce(Data(), { $0 + [$1] })
                            )
                        }

                        for try await line in stream.lines {
                            if isDoneLine(line) {
                                didComplete = true
                                break
                            }
                            if let chunk = try parseStreamLine(line) {
                                try observeCompletion(chunk, didComplete: &didComplete)
                                continuation.yield(chunk)
                            }
                        }

                        guard didComplete else { throw ChatCompletionsLanguageModel.RequestError.incompleteResponse }
                        continuation.finish()
                    #else
                        let (data, response) = try await session.data(for: urlRequest)
                        let httpResponse = response as! HTTPURLResponse

                        guard httpResponse.statusCode == 200 else {
                            throw ChatCompletionsLanguageModel.RequestError.httpError(
                                statusCode: httpResponse.statusCode,
                                data: data
                            )
                        }

                        let body = String(data: data, encoding: .utf8) ?? ""
                        for line in body.split(separator: "\n", omittingEmptySubsequences: false) {
                            if isDoneLine(String(line)) {
                                didComplete = true
                                break
                            }
                            if let chunk = try parseStreamLine(String(line)) {
                                try observeCompletion(chunk, didComplete: &didComplete)
                                continuation.yield(chunk)
                            }
                        }

                        guard didComplete else { throw ChatCompletionsLanguageModel.RequestError.incompleteResponse }
                        continuation.finish()
                    #endif

                } catch {
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    private func buildURLRequest(for request: ChatCompletionRequest) throws -> URLRequest {
        let isVersioned = baseURL.pathComponents.contains { component in
            component.wholeMatch(of: #/v\d+/#) != nil
        }
        let endpoint = isVersioned ? "/chat/completions" : "/v1/chat/completions"
        let url = baseURL.appendingPathComponent(endpoint)
        var urlRequest = URLRequest(url: url)
        urlRequest.httpMethod = "POST"
        for (header, value) in headers {
            urlRequest.setValue(value, forHTTPHeaderField: header)
        }

        let encoder = JSONEncoder()
        urlRequest.httpBody = try encoder.encode(request)

        return urlRequest
    }

    private func isDoneLine(_ line: String) -> Bool {
        let line = line.trimmingCharacters(in: .whitespaces)
        return line.hasPrefix("data:") && line.dropFirst(5).trimmingCharacters(in: .whitespaces) == "[DONE]"
    }

    private func observeCompletion(_ chunk: ChatCompletionChunk, didComplete: inout Bool) throws {
        guard let reason = chunk.choices.first?.finishReason else { return }
        switch reason {
        case "length": throw ChatCompletionsLanguageModel.RequestError.truncatedResponse
        case "stop", "tool_calls", "function_call": didComplete = true
        default: throw ChatCompletionsLanguageModel.RequestError.incompleteResponse
        }
    }

    func parseStreamLine(_ line: String) throws -> ChatCompletionChunk? {
        let trimmedLine = line.trimmingCharacters(in: .whitespaces)

        // Skip empty lines and comments
        guard !trimmedLine.isEmpty, !trimmedLine.hasPrefix(":") else {
            return nil
        }

        if trimmedLine.hasPrefix("data:") {
            let jsonString = String(trimmedLine.dropFirst(5)).trimmingCharacters(in: .whitespaces)

            if jsonString.trimmingCharacters(in: .whitespaces) == "[DONE]" {
                return nil
            }

            guard let jsonData = jsonString.data(using: .utf8) else {
                throw ChatCompletionsLanguageModel.RequestError.invalidStreamData
            }

            let decoder = JSONDecoder()
            // AniShelf modification: check for an error first. OpenRouter's mid-stream error event
            // also carries `id`, `model`, and `choices`, so it decodes as an ordinary chunk.
            if let response = try? decoder.decode(
                ChatCompletionsLanguageModel.ErrorResponse.self,
                from: jsonData
            ) {
                throw ChatCompletionsLanguageModel.APIError(
                    message: response.error.message,
                    type: response.error.type,
                    param: response.error.param,
                    code: response.error.code
                )
            }
            return try decoder.decode(ChatCompletionChunk.self, from: jsonData)
        }

        return nil
    }

    struct ChatCompletionRequest: Encodable {
        enum ToolChoiceMode: String, Encodable {
            case auto
            case required
            case none
        }

        struct ToolChoice: Encodable {
            let mode: ToolChoiceMode

            func encode(to encoder: any Encoder) throws {
                var container = encoder.singleValueContainer()
                try container.encode(mode)
            }
        }

        var model: String
        var messages: [ChatMessage]
        var temperature: Double?
        var topP: Double?
        var maxCompletionTokens: Int?
        var tools: [Tool]?
        var toolChoice: ChatCompletionRequest.ToolChoice?
        var responseFormat: ResponseFormat?
        var reasoningEffort: String?
        var reasoning: ReasoningObject?
        var stream = true
        var streamOptions = StreamOptions(includeUsage: true)

        struct ReasoningObject: Encodable {
            var enabled: Bool
            var effort: String?
        }

        struct StreamOptions: Encodable {
            var includeUsage: Bool

            private enum CodingKeys: String, CodingKey {
                case includeUsage = "include_usage"
            }
        }

        private enum CodingKeys: String, CodingKey {
            case model
            case messages
            case temperature
            case topP = "top_p"
            case maxCompletionTokens = "max_completion_tokens"
            case tools
            case responseFormat = "response_format"
            case reasoningEffort = "reasoning_effort"
            case reasoning
            case stream
            case streamOptions = "stream_options"
            case toolChoice = "tool_choice"
        }
    }

    struct ChatMessage: Encodable {
        var role: Role
        var content: [MessageContent]
        var toolCalls: [ToolCall]?
        var toolCallID: String?
        var reasoningContent: String?

        private enum CodingKeys: String, CodingKey {
            case role
            case content
            case toolCalls = "tool_calls"
            case toolCallID = "tool_call_id"
            case reasoningContent = "reasoning_content"
        }

        enum Role: String, Encodable {
            case system
            case user
            case assistant
            case tool
        }

        init(
            role: Role,
            content: [MessageContent] = [],
            toolCalls: [ToolCall]? = nil,
            toolCallID: String? = nil,
            reasoningContent: String? = nil
        ) {
            self.role = role
            self.content = content
            self.toolCalls = toolCalls
            self.toolCallID = toolCallID
            self.reasoningContent = reasoningContent
        }

        func encode(to encoder: Encoder) throws {
            var container = encoder.container(keyedBy: CodingKeys.self)

            try container.encode(role, forKey: .role)

            let hasToolCalls = toolCalls?.isEmpty == false
            let compactText = content.count == 1 ? content.first?.text : nil

            if let compactText {
                try container.encode(compactText, forKey: .content)
            } else if !hasToolCalls && !content.isEmpty {
                try container.encode(content, forKey: .content)
            }

            try container.encodeIfPresent(toolCalls, forKey: .toolCalls)
            try container.encodeIfPresent(toolCallID, forKey: .toolCallID)
            try container.encodeIfPresent(reasoningContent, forKey: .reasoningContent)
        }
    }

    struct Tool: Encodable {
        var type: String = "function"
        var function: Function

        struct Function: Encodable {
            let name: String
            let description: String
            let parameters: GenerationSchema
        }
    }

    struct ToolCall: Codable {
        var id: String
        var type = "function"
        var function: FunctionCall

        struct FunctionCall: Codable {
            var name: String
            var arguments: String
        }
    }

    struct ResponseFormat: Encodable {
        var type = "json_schema"
        var jsonSchema: JSONSchemaWrapper

        private enum CodingKeys: String, CodingKey {
            case type
            case jsonSchema = "json_schema"
        }

        struct JSONSchemaWrapper: Encodable {
            var name: String
            var description: String?
            var schema: GenerationSchema
            var strict = true

            private enum CodingKeys: String, CodingKey {
                case name, description, schema, strict
            }

            // AniShelf modification: Anthropic models reject the `x-order` keyword that
            // GenerationSchema adds to every object, so the provider gets a copy without it.
            func encode(to encoder: any Encoder) throws {
                var container = encoder.container(keyedBy: CodingKeys.self)
                try container.encode(name, forKey: .name)
                try container.encodeIfPresent(description, forKey: .description)
                try container.encode(strict, forKey: .strict)
                let object = try JSONSerialization.jsonObject(with: JSONEncoder().encode(schema))
                try container.encode(SchemaJSON(Self.removingKey("x-order", from: object)), forKey: .schema)
            }

            static func removingKey(_ key: String, from value: Any) -> Any {
                if let object = value as? [String: Any] {
                    return object.filter { $0.key != key }.mapValues { removingKey(key, from: $0) }
                }
                if let array = value as? [Any] {
                    return array.map { removingKey(key, from: $0) }
                }
                return value
            }
        }

        /// A `JSONSerialization` value, encoded back as the same JSON.
        struct SchemaJSON: Encodable {
            let value: Any

            init(_ value: Any) { self.value = value }

            private struct Key: CodingKey {
                var stringValue: String
                var intValue: Int? { nil }
                init(stringValue: String) { self.stringValue = stringValue }
                init?(intValue: Int) { nil }
            }

            func encode(to encoder: any Encoder) throws {
                switch value {
                case let object as [String: Any]:
                    var container = encoder.container(keyedBy: Key.self)
                    for (key, nested) in object {
                        try container.encode(SchemaJSON(nested), forKey: Key(stringValue: key))
                    }
                case let array as [Any]:
                    var container = encoder.unkeyedContainer()
                    for nested in array { try container.encode(SchemaJSON(nested)) }
                case let number as NSNumber where CFGetTypeID(number) == CFBooleanGetTypeID():
                    var container = encoder.singleValueContainer()
                    try container.encode(number.boolValue)
                case let number as NSNumber:
                    var container = encoder.singleValueContainer()
                    if CFNumberIsFloatType(number) {
                        try container.encode(number.doubleValue)
                    } else {
                        try container.encode(number.int64Value)
                    }
                case let string as String:
                    var container = encoder.singleValueContainer()
                    try container.encode(string)
                default:
                    var container = encoder.singleValueContainer()
                    try container.encodeNil()
                }
            }
        }
    }

    struct ChatCompletionChunk: Decodable {
        let id: String
        let model: String
        let choices: [Choice]
        let usage: Usage?

        struct Choice: Decodable {
            let delta: Delta?
            let finishReason: String?

            enum CodingKeys: String, CodingKey {
                case delta
                case finishReason = "finish_reason"
            }

            struct Delta: Decodable {
                var role: String?
                var content: String?
                var reasoningContent: String?
                var toolCalls: [ToolCallDelta]?

                enum CodingKeys: String, CodingKey {
                    case role
                    case content
                    case reasoningContent = "reasoning_content"
                    case toolCalls = "tool_calls"
                }
            }
        }

        struct ToolCallDelta: Decodable {
            let index: Int
            let id: String?
            let type: String?
            let function: FunctionCallDelta?

            struct FunctionCallDelta: Decodable {
                let name: String?
                let arguments: String?
            }
        }

        fileprivate struct Usage: Decodable {
            let promptTokens: Int
            let completionTokens: Int
            let promptTokensDetails: PromptTokensDetails?
            let completionTokensDetails: CompletionTokensDetails?

            fileprivate struct PromptTokensDetails: Decodable {
                let cachedTokens: Int?

                private enum CodingKeys: String, CodingKey {
                    case cachedTokens = "cached_tokens"
                }
            }

            fileprivate struct CompletionTokensDetails: Decodable {
                let reasoningTokens: Int?

                private enum CodingKeys: String, CodingKey {
                    case reasoningTokens = "reasoning_tokens"
                }
            }

            private enum CodingKeys: String, CodingKey {
                case promptTokens = "prompt_tokens"
                case completionTokens = "completion_tokens"
                case promptTokensDetails = "prompt_tokens_details"
                case completionTokensDetails = "completion_tokens_details"
            }
        }
    }

    struct MessageContent: Codable {
        var type: ContentType
        var text: String?
        var imageURL: ImageURL?

        enum CodingKeys: String, CodingKey {
            case type
            case text
            case imageURL = "image_url"
        }

        enum ContentType: String, Codable {
            case text
            case imageURL = "image_url"
        }

        struct ImageURL: Codable {
            var url: URL
            var detail: String? = "auto"
        }

        init(text: String) {
            self.type = .text
            self.text = text
            self.imageURL = nil
        }

        init(imageURL: ImageURL) {
            self.type = .imageURL
            self.text = nil
            self.imageURL = imageURL
        }
    }
}

#if canImport(CoreImage)
    extension CGImage {
        fileprivate func jpegData() -> Data {
            let imageData = NSMutableData()
            let destination = CGImageDestinationCreateWithData(
                /* data */ imageData,
                /* format */ UTType.jpeg.identifier as CFString,
                /* count */ 1,
                /* options */ nil
            )!
            CGImageDestinationAddImage(destination, self, nil)
            CGImageDestinationFinalize(destination)
            return Data(referencing: imageData)
        }
    }
#endif
