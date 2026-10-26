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

/// A multiline editor that shows a placeholder while empty.
///
/// iOS bridges a `UITextView`, since SwiftUI's `TextEditor` destabilized scrolling of the
/// entry detail page around it; macOS uses `TextEditor`.
struct PlaceholderTextEditor: View {
    @Binding var text: String
    var placeholder: LocalizedStringResource
    /// Monospaced, without autocorrection or capitalization, for structured input such as IDs.
    var isLiteralInput = false
    /// Focuses the editor when it appears.
    var autofocus = false
    /// Optional touch navigation on iOS; leading is a left swipe, trailing a right swipe.
    var onHorizontalSwipe: ((HorizontalEdge) -> Void)? = nil

    var body: some View {
        #if os(macOS)
            ZStack(alignment: .topLeading) {
                if text.isEmpty {
                    Text(placeholder)
                        .foregroundStyle(.tertiary)
                        // Lines up with the caret: NSTextView has no top inset and 5pt line padding.
                        .padding(.leading, 5)
                        .allowsHitTesting(false)
                }
                TextEditor(text: $text)
                    .modifier(AutofocusModifier(isEnabled: autofocus))
            }
            .scrollContentBackground(.hidden)
            .font(isLiteralInput ? .body.monospaced() : .body)
            .autocorrectionDisabled(isLiteralInput)
        #else
            PlaceholderTextView(
                text: $text,
                placeholder: String(localized: placeholder),
                isLiteralInput: isLiteralInput,
                autofocus: autofocus,
                onHorizontalSwipe: onHorizontalSwipe
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        #endif
    }
}

#if os(macOS)
    fileprivate struct AutofocusModifier: ViewModifier {
        let isEnabled: Bool
        @FocusState private var isFocused: Bool

        @ViewBuilder
        func body(content: Content) -> some View {
            if isEnabled {
                content
                    .focused($isFocused)
                    .onAppear { isFocused = true }
            } else {
                content
            }
        }
    }
#else
    fileprivate struct PlaceholderTextView: UIViewRepresentable {
        @Binding var text: String
        let placeholder: String
        let isLiteralInput: Bool
        let autofocus: Bool
        let onHorizontalSwipe: ((HorizontalEdge) -> Void)?

        func makeCoordinator() -> Coordinator {
            Coordinator(text: $text)
        }

        func makeUIView(context: Context) -> PlaceholderUITextView {
            let textView = PlaceholderUITextView()
            textView.delegate = context.coordinator
            textView.backgroundColor = .clear
            textView.font =
                isLiteralInput
                ? UIFontMetrics(forTextStyle: .body).scaledFont(
                    for: .monospacedSystemFont(ofSize: 17, weight: .regular))
                : .preferredFont(forTextStyle: .body)
            textView.adjustsFontForContentSizeCategory = true
            textView.textColor = .label
            textView.textContainerInset = UIEdgeInsets(top: 8, left: 0, bottom: 8, right: 0)
            textView.textContainer.lineFragmentPadding = 4
            if isLiteralInput {
                textView.autocorrectionType = .no
                textView.autocapitalizationType = .none
                textView.spellCheckingType = .no
                textView.smartQuotesType = .no
                textView.smartDashesType = .no
            }
            textView.text = text
            textView.focusesOnWindow = autofocus
            if onHorizontalSwipe != nil {
                for direction: UISwipeGestureRecognizer.Direction in [.left, .right] {
                    let swipe = UISwipeGestureRecognizer(
                        target: context.coordinator, action: #selector(Coordinator.swipe(_:)))
                    swipe.direction = direction
                    swipe.delegate = context.coordinator
                    textView.addGestureRecognizer(swipe)
                }
            }
            context.coordinator.onHorizontalSwipe = onHorizontalSwipe
            context.coordinator.lastSyncedText = text
            return textView
        }

        func updateUIView(_ textView: PlaceholderUITextView, context: Context) {
            let coordinator = context.coordinator
            coordinator.text = $text
            coordinator.onHorizontalSwipe = onHorizontalSwipe
            textView.placeholder = placeholder
            // Apply only changes made outside the editor. The model can reject a keystroke (a
            // whitespace-only episode note stays empty), and echoing that back would erase it.
            guard text != coordinator.lastSyncedText, textView.markedTextRange == nil else { return }
            coordinator.lastSyncedText = text
            if textView.text != text {
                textView.text = text
            }
        }

        final class Coordinator: NSObject, UITextViewDelegate, UIGestureRecognizerDelegate {
            var text: Binding<String>
            var onHorizontalSwipe: ((HorizontalEdge) -> Void)?
            /// The binding's value as of the last update, to tell outside changes from typing.
            var lastSyncedText = ""

            init(text: Binding<String>) {
                self.text = text
            }

            func textViewDidChange(_ textView: UITextView) {
                (textView as? PlaceholderUITextView)?.updatePlaceholderVisibility()
                text.wrappedValue = textView.text
            }

            func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
                guard onHorizontalSwipe != nil, let textView = gestureRecognizer.view as? UITextView else {
                    return false
                }
                // Leave IME composition and selection-handle drags to the text editor.
                return textView.markedTextRange == nil && textView.selectedRange.length == 0
            }

            func gestureRecognizer(
                _ gestureRecognizer: UIGestureRecognizer,
                shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer
            ) -> Bool {
                // The text view's scrolling pan otherwise recognizes before a swipe can finish.
                otherGestureRecognizer === (gestureRecognizer.view as? UITextView)?.panGestureRecognizer
            }

            @objc func swipe(_ gesture: UISwipeGestureRecognizer) {
                guard gesture.state == .ended else { return }
                onHorizontalSwipe?(gesture.direction == .left ? .leading : .trailing)
            }
        }
    }

    fileprivate final class PlaceholderUITextView: UITextView {
        private let placeholderLabel = UILabel()
        var focusesOnWindow = false

        var placeholder = "" {
            didSet {
                guard placeholder != oldValue else { return }
                placeholderLabel.text = placeholder
                setNeedsLayout()
            }
        }

        override var font: UIFont? {
            didSet {
                placeholderLabel.font = font
                setNeedsLayout()
            }
        }

        override var text: String! {
            didSet { updatePlaceholderVisibility() }
        }

        init() {
            super.init(frame: .zero, textContainer: nil)
            placeholderLabel.numberOfLines = 0
            placeholderLabel.textColor = .tertiaryLabel
            placeholderLabel.adjustsFontForContentSizeCategory = true
            placeholderLabel.isAccessibilityElement = false
            addSubview(placeholderLabel)
        }

        required init?(coder: NSCoder) {
            fatalError("init(coder:) has not been implemented")
        }

        func updatePlaceholderVisibility() {
            placeholderLabel.isHidden = !text.isEmpty
        }

        override func didMoveToWindow() {
            super.didMoveToWindow()
            guard focusesOnWindow, window != nil else { return }
            focusesOnWindow = false
            becomeFirstResponder()
        }

        override func layoutSubviews() {
            super.layoutSubviews()
            // Lines up with the caret: the text container's inset plus its line padding.
            let padding = textContainer.lineFragmentPadding
            let x = textContainerInset.left + padding
            let width = max(bounds.width - x - textContainerInset.right - padding, 0)
            let height = placeholderLabel.sizeThatFits(CGSize(width: width, height: .greatestFiniteMagnitude)).height
            placeholderLabel.frame = CGRect(x: x, y: textContainerInset.top, width: width, height: height)
        }
    }
#endif
