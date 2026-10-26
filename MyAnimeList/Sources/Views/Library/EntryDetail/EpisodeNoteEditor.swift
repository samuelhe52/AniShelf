//
//  EpisodeNoteEditor.swift
//  AniShelf
//
//  Created by OpenAI Codex on behalf of Samuel He on 2026/10/26.
//

import DataProvider
import SwiftUI

/// The episode-list shortcut edits a draft; Cancel never touches the saved note.
struct EpisodeNoteEditor: View {
    @Environment(\.dismiss) private var dismiss
    let entry: AnimeEntry
    let anchor: EpisodeNoteAnchor
    @State private var text: String
    @FocusState private var isFocused: Bool

    init(entry: AnimeEntry, anchor: EpisodeNoteAnchor) {
        self.entry = entry
        self.anchor = anchor
        _text = State(initialValue: entry.episodeNote(at: anchor)?.text ?? "")
    }

    private var savedText: String { entry.episodeNote(at: anchor)?.text ?? "" }
    private var title: (primary: String, secondary: String?) { EntryNoteLabels.title(anchor, entry: entry) }

    var body: some View {
        NavigationStack {
            VStack(spacing: 16) {
                ZStack(alignment: .topLeading) {
                    if text.isEmpty {
                        Text("Write an episode note…")
                            .foregroundStyle(.tertiary)
                            .padding(.horizontal, 5)
                            .padding(.vertical, 8)
                            .allowsHitTesting(false)
                    }
                    TextEditor(text: $text)
                        .focused($isFocused)
                        .scrollContentBackground(.hidden)
                        .accessibilityLabel(Text(verbatim: title.primary))
                        .accessibilityIdentifier("episodeNote.editor")
                }
                .font(.body)
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(Self.fieldBackground, in: RoundedRectangle(cornerRadius: 14, style: .continuous))

                if !savedText.isEmpty {
                    Button("Delete Note", role: .destructive) {
                        entry.updateEpisodeNote(at: anchor, text: "")
                        dismiss()
                    }
                    .font(.body.weight(.semibold))
                }
            }
            .padding([.horizontal, .bottom])
            .padding(.top, 4)
            .background(Self.sheetBackground)
            .navigationTitle(Text(verbatim: title.primary))
            #if os(iOS)
                .navigationSubtitle(Text(verbatim: title.secondary ?? ""))
            #endif
            .inlineNavigationTitle()
            .preferredNavigationBarScrollEdgeEffect()
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(action: dismiss.callAsFunction) {
                        SheetCloseLabel(title: "Cancel")
                    }
                    .accessibilityLabel(Text("Cancel"))
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        // An unchanged normalized draft (such as whitespace only) is a no-op save;
                        // keep the draft only if the season lost its parent series mid-edit.
                        if entry.updateEpisodeNote(at: anchor, text: text) || entry.supportsEpisodeNotes {
                            dismiss()
                        }
                    }
                    .disabled(text == savedText)
                }
            }
        }
        .presentationDetents([.medium, .large])
        .interactiveDismissDisabled(text != savedText)
        .onAppear { isFocused = true }
        #if os(macOS)
            .frame(minWidth: 400, minHeight: 320)
        #endif
    }

    #if os(iOS)
        private static let fieldBackground = Color(uiColor: .secondarySystemGroupedBackground)
        private static let sheetBackground = Color(uiColor: .systemGroupedBackground)
    #else
        private static let fieldBackground = Color(nsColor: .textBackgroundColor)
        private static let sheetBackground = Color.clear
    #endif
}
