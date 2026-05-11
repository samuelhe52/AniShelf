//
//  PlaceholderTextEditor.swift
//  MyAnimeList
//
//  Created by Samuel He on 2025/6/16.
//

import SwiftUI

struct PlaceholderTextEditor: View {
    @Binding var text: String
    var placeholder: LocalizedStringResource

    var body: some View {
        ZStack(alignment: .topLeading) {
            if text.isEmpty {
                Text(placeholder)
                    .foregroundStyle(.tertiary)
                    .padding(.top, 8)
                    .padding(.leading, 4)
            }
            TextEditor(text: $text)
        }
        .scrollContentBackground(.hidden)
    }
}
