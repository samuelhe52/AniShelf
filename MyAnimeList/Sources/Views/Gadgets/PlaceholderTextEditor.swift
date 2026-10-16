//
//  PlaceholderTextEditor.swift
//  MyAnimeList
//
//  Created by Samuel He on 2025/6/16.
//

import SwiftUI

#if os(macOS)
    import AppKit
#else
    import UIKit
#endif

/// Where the placeholder sits so it lines up with the editor's caret. UITextView here has an
/// 8pt top inset and 4pt line padding; NSTextView has none on top and 5pt line padding.
fileprivate enum PlaceholderTextEditorMetrics {
    #if os(macOS)
        static let top: CGFloat = 0
        static let leading: CGFloat = 5
    #else
        static let top: CGFloat = 8
        static let leading: CGFloat = 4
    #endif
}

struct PlaceholderTextEditor: View {
    @Binding var text: String
    var placeholder: LocalizedStringResource

    var body: some View {
        ZStack(alignment: .topLeading) {
            if text.isEmpty {
                Text(placeholder)
                    .foregroundStyle(.tertiary)
                    .padding(.top, PlaceholderTextEditorMetrics.top)
                    .padding(.leading, PlaceholderTextEditorMetrics.leading)
                    .allowsHitTesting(false)
            }
            TextEditor(text: $text)
        }
        .scrollContentBackground(.hidden)
    }
}

struct ScrollIsolatedPlaceholderTextEditor: View {
    @Binding var text: String
    var placeholder: LocalizedStringResource

    var body: some View {
        ZStack(alignment: .topLeading) {
            if text.isEmpty {
                Text(placeholder)
                    .foregroundStyle(.tertiary)
                    .padding(.top, PlaceholderTextEditorMetrics.top)
                    .padding(.leading, PlaceholderTextEditorMetrics.leading)
                    .allowsHitTesting(false)
            }
            ScrollIsolatedTextView(text: $text)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }
}

#if os(macOS)
    fileprivate struct ScrollIsolatedTextView: View {
        @Binding var text: String
        var body: some View { TextEditor(text: $text).scrollContentBackground(.hidden) }
    }
#else
    fileprivate struct ScrollIsolatedTextView: UIViewRepresentable {
        @Binding var text: String

        func makeCoordinator() -> Coordinator {
            Coordinator(text: $text)
        }

        func makeUIView(context: Context) -> UITextView {
            let textView = UITextView()
            textView.delegate = context.coordinator
            textView.backgroundColor = .clear
            textView.font = .preferredFont(forTextStyle: .body)
            textView.adjustsFontForContentSizeCategory = true
            textView.textColor = .label
            textView.textContainerInset = UIEdgeInsets(top: 8, left: 0, bottom: 8, right: 0)
            textView.textContainer.lineFragmentPadding = 4
            textView.text = text
            return textView
        }

        func updateUIView(_ textView: UITextView, context: Context) {
            guard textView.text != text else { return }
            textView.text = text
        }

        final class Coordinator: NSObject, UITextViewDelegate {
            let text: Binding<String>

            init(text: Binding<String>) {
                self.text = text
            }

            func textViewDidChange(_ textView: UITextView) {
                text.wrappedValue = textView.text
            }
        }
    }

#endif
