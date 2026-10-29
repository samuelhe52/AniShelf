//
//  PromptEditorStep.swift
//  AniShelf
//
//  Created by Claude Code on behalf of Samuel He on 2026/10/29.
//

import SwiftUI

/// The input step of a sheet flow: a note above one editor that fills the remaining space,
/// with an optional footer such as a validation message.
///
/// iOS shows one rounded editor surface with no enclosing panel; the Mac shows a bordered
/// editor. The caller places the step's actions (the iOS bottom bar or the Mac toolbar).
///
/// On iOS, call `PlaceholderTextEditor.dismissKeyboard()` before replacing this step, so the
/// keyboard animates away instead of waiting for the step's removal transition.
struct PromptEditorStep<Note: View, Footer: View>: View {
    @Binding var text: String
    let placeholder: LocalizedStringResource
    var isLiteralInput = false
    var autofocus = false
    @ViewBuilder let note: Note
    @ViewBuilder let footer: Footer

    init(
        text: Binding<String>,
        placeholder: LocalizedStringResource,
        isLiteralInput: Bool = false,
        autofocus: Bool = false,
        @ViewBuilder note: () -> Note,
        @ViewBuilder footer: () -> Footer = { EmptyView() }
    ) {
        _text = text
        self.placeholder = placeholder
        self.isLiteralInput = isLiteralInput
        self.autofocus = autofocus
        self.note = note()
        self.footer = footer()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            note
                .foregroundStyle(.secondary)
                #if !os(macOS)
                    .font(.subheadline)
                    .padding(.horizontal, 4)
                #endif

            editor

            footer
                #if !os(macOS)
                    .font(.footnote)
                    .padding(.horizontal, 4)
                #endif
        }
        #if os(macOS)
            .padding(20)
        #else
            .padding(.horizontal, 20)
            .padding(.top, 16)
            .padding(.bottom, 12)
        #endif
    }

    private var editor: some View {
        PlaceholderTextEditor(
            text: $text,
            placeholder: placeholder,
            isLiteralInput: isLiteralInput,
            autofocus: autofocus
        )
        #if os(macOS)
            .padding(8)
            .background(Color(nsColor: .textBackgroundColor), in: .rect(cornerRadius: 6))
            .overlay {
                RoundedRectangle(cornerRadius: 6)
                .stroke(.separator, lineWidth: 1)
            }
        #else
            .padding(12)
            .background(
                Color.platformSecondarySystemBackground,
                in: RoundedRectangle(cornerRadius: 18, style: .continuous)
            )
        #endif
    }
}
