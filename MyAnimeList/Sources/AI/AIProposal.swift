//
//  AIProposal.swift
//  AniShelf
//
//  Created by OpenAI Codex on behalf of Samuel He on 2026/10/28.
//

import Foundation

/// A transient review value.
///
/// Only the feature's explicit Apply action may persist accepted items.
struct AIProposal<Value> {
    struct Item: Identifiable {
        let id: UUID
        let value: Value
        var isAccepted: Bool

        init(id: UUID = UUID(), value: Value, isAccepted: Bool = true) {
            self.id = id
            self.value = value
            self.isAccepted = isAccepted
        }
    }

    var items: [Item]
    var acceptedValues: [Value] { items.filter(\.isAccepted).map(\.value) }
}
