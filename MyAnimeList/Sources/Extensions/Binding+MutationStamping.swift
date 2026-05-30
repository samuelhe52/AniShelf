//
//  Binding+MutationStamping.swift
//  AniShelf
//
//  Created by OpenAI Codex on behalf of Samuel He on 2026/5/30.
//

import SwiftUI

extension Binding {
    @MainActor
    func onSet(_ action: @escaping @MainActor () -> Void) -> Binding<Value> {
        Binding(
            get: { wrappedValue },
            set: { newValue in
                wrappedValue = newValue
                action()
            }
        )
    }
}
