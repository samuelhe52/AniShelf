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

    init(entry: AnimeEntry, anchor: EpisodeNoteAnchor) {
        self.entry = entry
        self.anchor = anchor
        _text = State(initialValue: entry.episodeNote(at: anchor)?.text ?? "")
    }

    private var savedText: String { entry.episodeNote(at: anchor)?.text ?? "" }
    private var title: (primary: String, secondary: String?) { EntryNoteLabels.title(anchor, entry: entry) }

    var body: some View {
        #if os(macOS)
            macBody
        #else
            iOSBody
        #endif
    }

    private var field: some View {
        PlaceholderTextEditor(text: $text, placeholder: "Write an episode note…", autofocus: true)
            .accessibilityLabel(Text(verbatim: title.primary))
            .accessibilityIdentifier("episodeNote.editor")
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
    }

    private func save() {
        // An unchanged normalized draft (such as whitespace only) is a no-op save;
        // keep the draft only if the season lost its parent series mid-edit.
        if entry.updateEpisodeNote(at: anchor, text: text) || entry.supportsEpisodeNotes {
            dismiss()
        }
    }

    private func delete() {
        entry.updateEpisodeNote(at: anchor, text: "")
        dismiss()
    }

    #if os(macOS)
        /// Laid out like the app's other Mac sheets: heading, field, then one action row.
        private var macBody: some View {
            VStack(alignment: .leading, spacing: 16) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(verbatim: title.primary)
                        .font(.title2.weight(.semibold))
                    if let secondary = title.secondary {
                        Text(verbatim: secondary)
                            .font(.callout)
                            .foregroundStyle(.secondary)
                            .lineLimit(2)
                    }
                }

                field
                    .frame(minHeight: 180)
                    .background(.background, in: RoundedRectangle(cornerRadius: 10))
                    .overlay {
                        RoundedRectangle(cornerRadius: 10)
                            .strokeBorder(.quaternary, lineWidth: 0.5)
                    }

                HStack(spacing: 8) {
                    if !savedText.isEmpty {
                        Button("Delete Note", role: .destructive, action: delete)
                    }
                    Spacer()
                    Button("Cancel") { dismiss() }
                        .keyboardShortcut(.cancelAction)
                    // Return types a newline in the field, so Save takes Command-Return.
                    Button("Save", action: save)
                        .buttonStyle(.borderedProminent)
                        .keyboardShortcut(.return, modifiers: .command)
                        .disabled(text == savedText)
                }
                .buttonStyle(.bordered)
            }
            .padding(24)
            .frame(width: 460)
        }
    #else
        private var iOSBody: some View {
            NavigationStack {
                VStack(spacing: 16) {
                    field
                        .background(Self.fieldBackground, in: RoundedRectangle(cornerRadius: 14, style: .continuous))

                    if !savedText.isEmpty {
                        Button("Delete Note", role: .destructive, action: delete)
                            .font(.body.weight(.semibold))
                    }
                }
                .padding([.horizontal, .bottom])
                .padding(.top, 4)
                .background(Self.sheetBackground)
                .navigationTitle(Text(verbatim: title.primary))
                .navigationSubtitle(Text(verbatim: title.secondary ?? ""))
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
                        Button("Save", action: save)
                            .disabled(text == savedText)
                    }
                }
            }
            .presentationDetents([.medium, .large])
            .interactiveDismissDisabled(text != savedText)
        }
    #endif

    #if os(iOS)
        private static let fieldBackground = Color(uiColor: .secondarySystemGroupedBackground)
        private static let sheetBackground = Color(uiColor: .systemGroupedBackground)
    #endif
}
