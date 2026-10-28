//
//  AIContextBudget.swift
//  AniShelf
//
//  Created by OpenAI Codex on behalf of Samuel He on 2026/10/28.
//

import Foundation
import FoundationModels

@MainActor
struct AIContextBudget {
    let contextSize: Int
    let reservedTokens: Int
    let maximumResponseTokens: Int
    private let countPrompt: @MainActor (String) async throws -> Int

    init(
        contextSize: Int, reservedTokens: Int, maximumResponseTokens: Int,
        countPrompt: @escaping @MainActor (String) async throws -> Int = { estimateTokens($0) }
    ) {
        self.contextSize = max(0, contextSize)
        self.reservedTokens = max(0, reservedTokens)
        self.maximumResponseTokens = max(1, maximumResponseTokens)
        self.countPrompt = countPrompt
    }

    var inputTokens: Int { max(0, contextSize - reservedTokens - maximumResponseTokens) }

    func fits(_ prompt: String) async throws -> Bool {
        guard reservedTokens + maximumResponseTokens <= contextSize else { return false }
        return try await countPrompt(prompt) <= inputTokens
    }

    /// Reserves instructions, schema, response, and framing.
    ///
    /// All providers use Apple's cap.
    static func make<Value: Generable>(
        backend: AIBackend, instructions: String, generating: Value.Type,
        maximumResponseTokens: Int? = nil
    ) async throws -> Self {
        let model = SystemLanguageModel.default
        // Ineligible systems (including Simulator) can report zero. Providers still use
        // the 26-era Apple limit until a positive runtime limit is available.
        let reportedLimit = model.contextSize
        let limit = reportedLimit > 0 ? reportedLimit : 4096
        // OpenAI's completion cap includes hidden reasoning. Reserve it from the same
        // shared context budget, rather than assuming 512 tokens can cover both.
        let maximumResponseTokens = maximumResponseTokens ?? (backend == .openAI ? 2048 : 512)
        let framingMargin = 256
        if backend == .apple, #available(iOS 26.4, macOS 26.4, *), model.isAvailable {
            let instructionCost = try await model.tokenCount(for: Instructions(instructions))
            let schemaCost = try await model.tokenCount(for: Value.generationSchema)
            return Self(
                contextSize: limit, reservedTokens: instructionCost + schemaCost + framingMargin,
                maximumResponseTokens: maximumResponseTokens,
                countPrompt: { try await model.tokenCount(for: Prompt($0)) }
            )
        }
        let schema = try String(decoding: JSONEncoder().encode(Value.generationSchema), as: UTF8.self)
        return Self(
            contextSize: limit,
            reservedTokens: estimateTokens(instructions) + estimateTokens(schema) + framingMargin,
            maximumResponseTokens: maximumResponseTokens
        )
    }

    /// A mixed-script estimate with a 20% margin; exact Apple counting remains authoritative.
    nonisolated static func estimateTokens(_ text: String) -> Int {
        let weighted = text.unicodeScalars.reduce(0.0) { cost, scalar in
            let unit: Double
            switch scalar.value {
            case 0...127: unit = 0.25
            case 0x2E80...0x9FFF, 0xAC00...0xD7AF, 0xF900...0xFAFF, 0x20000...0x323AF: unit = 1
            default: unit = Double(scalar.utf8.count) / 2
            }
            return cost + unit
        }
        return Int(ceil(weighted * 1.2))
    }
}
