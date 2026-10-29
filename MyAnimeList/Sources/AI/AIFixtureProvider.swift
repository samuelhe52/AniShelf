//
//  AIFixtureProvider.swift
//  AniShelf
//
//  Created by Claude Code on behalf of Samuel He on 2026/10/29.
//

#if DEBUG || LIBRARY_FIXTURES
    import Foundation
    import os

    /// A simulated chat-completions provider that fixture launches use instead of OpenAI and
    /// OpenRouter.
    ///
    /// A Smart Features run goes through the real client, streaming, batching, parallel
    /// requests, and retries, but costs nothing and never leaves the device. Each reply arrives
    /// after a latency similar to a real one.
    ///
    /// - Planning keeps every filter open and passes the whole description on as the criterion.
    /// - A check matches cards that contain a word of the criterion, such as a genre, and about
    ///   a fifth of the rest, so non-English descriptions find something too.
    /// - Markers in a description simulate failures: `#fail` fails planning with HTTP 500,
    ///   `#flaky` fails about a third of the check batches with HTTP 503 on every attempt, and
    ///   `#none` matches nothing.
    final class AIFixtureProvider: URLProtocol, @unchecked Sendable {
        /// A reserved host, so a request that escapes the protocol cannot reach a real server.
        static let baseURL = URL(string: "https://ai-fixture.invalid/v1")!

        static var sessionConfiguration: URLSessionConfiguration {
            let configuration = URLSessionConfiguration.ephemeral
            configuration.protocolClasses = [AIFixtureProvider.self]
            return configuration
        }

        private let isStopped = OSAllocatedUnfairLock(initialState: false)

        override class func canInit(with request: URLRequest) -> Bool { request.url?.host == baseURL.host }
        override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

        override func startLoading() {
            let reply = Self.reply(to: Self.body(of: request))
            DispatchQueue.global(qos: .userInitiated).asyncAfter(deadline: .now() + reply.latency) { [self] in
                deliver(reply)
            }
        }

        override func stopLoading() {
            isStopped.withLock { $0 = true }
        }

        private struct Reply {
            var status = 200
            var content = ""
            var latency: TimeInterval
        }

        private func deliver(_ reply: Reply) {
            guard !isStopped.withLock({ $0 }), let url = request.url else { return }
            let response = HTTPURLResponse(
                url: url, statusCode: reply.status, httpVersion: nil,
                headerFields: ["Content-Type": reply.status == 200 ? "text/event-stream" : "application/json"])!
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            guard reply.status == 200 else {
                let body = #"{"error":{"message":"Simulated provider failure","code":"\#(reply.status)"}}"#
                client?.urlProtocol(self, didLoad: Data(body.utf8))
                client?.urlProtocolDidFinishLoading(self)
                return
            }
            // Stream the answer in a few pieces, as a provider does.
            let content = Array(reply.content)
            let pieceLength = max(1, content.count / 3)
            var events = stride(from: 0, to: content.count, by: pieceLength).map { start in
                Self.event(["delta": ["content": String(content[start..<min(start + pieceLength, content.count)])]])
            }
            events.append(Self.event(["delta": [String: String](), "finish_reason": "stop"]))
            events.append("data: [DONE]\n\n")
            for event in events {
                guard !isStopped.withLock({ $0 }) else { return }
                client?.urlProtocol(self, didLoad: Data(event.utf8))
                Thread.sleep(forTimeInterval: 0.03)
            }
            client?.urlProtocolDidFinishLoading(self)
        }

        private static func event(_ choice: [String: Any]) -> String {
            let chunk: [String: Any] = ["id": "fixture", "model": "fixture", "choices": [choice]]
            let data = try! JSONSerialization.data(withJSONObject: chunk)
            return "data: \(String(decoding: data, as: UTF8.self))\n\n"
        }

        // MARK: - Answers

        private static func reply(to body: [String: Any]) -> Reply {
            let messages = body["messages"] as? [[String: Any]] ?? []
            let instructions = text(of: messages, role: "system")
            let prompt = text(of: messages, role: "user")
            let format = body["response_format"] as? [String: Any]
            let schema = (format?["json_schema"] as? [String: Any])?["schema"] as? [String: Any]
            let properties = Set((schema?["properties"] as? [String: Any] ?? [:]).keys)

            if properties.contains("semanticCriterion") {
                if prompt.contains("#fail") { return Reply(status: 500, latency: 0.8) }
                return Reply(content: json(plan(for: prompt)), latency: 1.2)
            }
            if properties.contains("matchingIndices") {
                let criterion =
                    instructions.firstRange(of: "Criterion: ").map {
                        String(instructions[$0.upperBound...].prefix { $0 != "\n" })
                    } ?? ""
                let seed = fnv1a(prompt)
                let latency = 0.6 + Double(seed % 1_000) / 1_000 * 1.4
                if criterion.contains("#flaky"), seed % 3 == 0 { return Reply(status: 503, latency: latency) }
                let indices =
                    criterion.contains("#none")
                    ? [] : cards(in: prompt).filter { matches($0.text, criterion: criterion) }.map(\.index)
                return Reply(content: json(["matchingIndices": indices]), latency: latency)
            }
            // The Smart Features connection check.
            if properties.contains("value") { return Reply(content: #"{"value":7}"#, latency: 0.5) }
            return Reply(status: 400, latency: 0.2)
        }

        private static func plan(for request: String) -> [String: Any] {
            let name = request.replacing(#/[#]\w+/#, with: "").trimmingCharacters(in: .whitespacesAndNewlines)
            return [
                "name": String(name.prefix(40)),
                "kinds": [String](), "watchStatuses": [String](), "favoritesOnly": false,
                "minimumScore": 0, "maximumScore": 0, "earliestYear": 0, "latestYear": 0,
                "earliestFinishYear": 0, "latestFinishYear": 0,
                "semanticCriterion": request, "unsupportedRequest": ""
            ]
        }

        private static let ignoredWords: Set<String> = [
            "anime", "with", "from", "that", "about", "movie", "movies", "series", "show", "shows",
            "finished", "watched", "favorite", "favorites", "flaky", "none"
        ]

        private static func matches(_ card: String, criterion: String) -> Bool {
            let card = card.lowercased()
            let words = criterion.lowercased().split { !$0.isLetter }.map(String.init)
                .filter { $0.count >= 4 && !ignoredWords.contains($0) }
            return words.contains { card.contains($0) } || fnv1a(card + criterion) % 5 == 0
        }

        /// The batch prompt's `index: "card"` lines.
        private static func cards(in prompt: String) -> [(index: Int, text: String)] {
            prompt.split(separator: "\n").compactMap { line in
                guard let match = line.wholeMatch(of: #/(\d+): (.*)/#), let index = Int(match.1),
                    let text = try? JSONDecoder().decode(String.self, from: Data(match.2.utf8))
                else { return nil }
                return (index, text)
            }
        }

        private static func text(of messages: [[String: Any]], role: String) -> String {
            messages.filter { $0["role"] as? String == role }.map { message in
                if let text = message["content"] as? String { return text }
                let parts = message["content"] as? [[String: Any]] ?? []
                return parts.compactMap { $0["text"] as? String }.joined()
            }
            .joined(separator: "\n")
        }

        private static func json(_ object: [String: Any]) -> String {
            String(decoding: try! JSONSerialization.data(withJSONObject: object), as: UTF8.self)
        }

        /// A stable hash; `Hasher` is seeded per launch.
        private static func fnv1a(_ text: String) -> UInt64 {
            text.utf8.reduce(14_695_981_039_346_656_037) { ($0 ^ UInt64($1)) &* 1_099_511_628_211 }
        }

        /// URLProtocol sees the body as a stream, not `httpBody`.
        private static func body(of request: URLRequest) -> [String: Any] {
            var data = request.httpBody ?? Data()
            if data.isEmpty, let stream = request.httpBodyStream {
                stream.open()
                defer { stream.close() }
                var buffer = [UInt8](repeating: 0, count: 16_384)
                while stream.hasBytesAvailable {
                    let count = stream.read(&buffer, maxLength: buffer.count)
                    guard count > 0 else { break }
                    data.append(buffer, count: count)
                }
            }
            return (try? JSONSerialization.jsonObject(with: data) as? [String: Any]) ?? [:]
        }
    }
#endif
