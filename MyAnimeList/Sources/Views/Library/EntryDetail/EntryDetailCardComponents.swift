//
//  EntryDetailCardComponents.swift
//  MyAnimeList
//
//  Created by OpenAI Codex on behalf of Samuel He on 2026/5/21.
//

import DataProvider
import Kingfisher
import SwiftUI

struct PersonCardView: View {
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.popupPanelStyle) private var panelStyle

    let card: EntryDetailPersonCard

    private let cardWidth: CGFloat = 146
    private let portraitHeight: CGFloat = 168

    private var cornerRadius: CGFloat {
        panelStyle == .grouped ? 12 : 22
    }

    private var backgroundStyle: AnyShapeStyle {
        // The portrait supplies the contrast; keep its caption surface quiet while a
        // hairline defines the card against the enclosing inspector section.
        if panelStyle == .grouped { return AnyShapeStyle(Color.primary.opacity(0.035)) }
        return colorScheme == .dark
            ? AnyShapeStyle(Color.platformQuaternarySystemFill)
            : AnyShapeStyle(.thinMaterial)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Group {
                if let profileImage = card.profileImage {
                    KFImageView(image: profileImage, diskCacheExpiration: .shortTerm)
                        .scaledToFill()
                } else {
                    Rectangle()
                        .fill(Color.secondary.opacity(0.15))
                        .overlay {
                            Image(systemName: "person.fill")
                                .font(.system(size: 34))
                                .foregroundStyle(.secondary)
                        }
                }
            }
            .frame(width: cardWidth, height: portraitHeight)
            .clipped()

            VStack(alignment: .leading, spacing: 8) {
                Text(card.primaryText)
                    .font(.subheadline.weight(.semibold))
                    .lineLimit(2)

                Text(card.secondaryText)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(12)
        }
        .frame(width: cardWidth, alignment: .leading)
        .background(backgroundStyle)
        .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
        .overlay {
            if panelStyle == .grouped {
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .strokeBorder(.separator, lineWidth: 0.5)
            }
        }
    }
}

struct EpisodeRowView: View {
    let card: EntryDetailEpisodeCard
    let previewContext: EpisodePreviewContext?
    let isWatched: Bool
    let entry: AnimeEntry?
    @State private var editingNote: EpisodeNoteAnchor?
    @State private var editAfterPreview = false
    @State private var showPreview = false
    @State private var previewHapticTrigger = false
    @State private var retainedNoteText: String?
    @State private var isNoteVisible = true
    @State private var isNoteEditorPresented = false

    init(
        card: EntryDetailEpisodeCard,
        previewContext: EpisodePreviewContext? = nil,
        isWatched: Bool = false,
        entry: AnimeEntry? = nil
    ) {
        self.card = card
        self.previewContext = previewContext
        self.isWatched = isWatched
        self.entry = entry
    }

    var body: some View {
        let displayedNoteText = noteText ?? retainedNoteText

        HStack(spacing: 0) {
            Group {
                if let stillImage = card.stillImage {
                    KFImageView(image: stillImage, diskCacheExpiration: .transient)
                        .scaledToFill()
                        .frame(width: 126, height: 74)
                        .clipped()
                } else {
                    Rectangle()
                        .fill(Color.secondary.opacity(0.15))
                        .overlay {
                            Image(systemName: "tv")
                                .foregroundStyle(.secondary)
                        }
                }
            }
            .frame(width: 126, height: 74)
            .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
            .accessibilityHidden(true)
            .padding(.trailing, 12)

            VStack(alignment: .leading, spacing: 6) {
                // A note line takes the title's second line so the text stays level with the thumbnail.
                Text(card.title)
                    .font(.subheadline.weight(.semibold))
                    .lineLimit(displayedNoteText == nil ? 2 : 1)
                Text(card.subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(displayedNoteText == nil ? 2 : 1)
                if let displayedNoteText {
                    Text("\(Image(systemName: "note.text")) \(displayedNoteText)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .opacity(isNoteVisible ? 1 : 0)
                        .transition(.identity)
                        .accessibilityHidden(noteText == nil)
                }
            }
            .animation(.snappy, value: displayedNoteText != nil)

            Spacer(minLength: 4)

            statusAccessory
        }
        .padding(.vertical, 4)
        .accessibilityElement(children: .combine)
        .accessibilityValue(Text(verbatim: isWatched ? String(localized: EntryDetailL10n.watched) : ""))
        .previewTrigger(isEnabled: previewContext != nil) {
            previewHapticTrigger.toggle()
            showPreview = true
        }
        .swipeActions(edge: .trailing) {
            if let noteAnchor {
                Button(noteText == nil ? "Add Note" : "Edit Note", systemImage: "note.text") {
                    editingNote = noteAnchor
                }
                .tint(.blue)
            }
        }
        .sensoryFeedback(.impact(flexibility: .solid), trigger: previewHapticTrigger)
        .onChange(of: noteText, initial: true) { _, newValue in
            updateNotePresentation(newValue)
        }
        #if os(macOS)
            .contextMenu {
                if previewContext != nil {
                    Button("Preview", systemImage: "eye") { showPreview = true }
                }
                if noteAnchor != nil {
                    Button(noteText == nil ? "Add Note" : "Edit Note", systemImage: "note.text") {
                        editingNote = noteAnchor
                    }
                }
            }
        #endif
        // Long press stays the iOS preview gesture; the preview offers the note.
        .accessibilityActions {
            if noteAnchor != nil {
                Button(noteText == nil ? "Add Note" : "Edit Note") { editingNote = noteAnchor }
            }
        }
        .sheet(
            item: $editingNote,
            onDismiss: {
                isNoteEditorPresented = false
                updateNotePresentation(noteText)
            }
        ) { anchor in
            if let entry {
                EpisodeNoteEditor(entry: entry, anchor: anchor)
                    .modifier(EntryNotesPresentationLifecycle())
                    .onAppear { isNoteEditorPresented = true }
            }
        }
        .popover(isPresented: $showPreview) {
            if let previewContext {
                EpisodePreviewCard(card: card, context: previewContext, entry: entry) {
                    editAfterPreview = true
                    showPreview = false
                }
                .onDisappear {
                    if editAfterPreview {
                        editAfterPreview = false
                        editingNote = noteAnchor
                    }
                }
                .presentationCompactAdaptation(.popover)
            }
        }
    }

    private func updateNotePresentation(_ text: String?) {
        if let text {
            retainedNoteText = text
            withAnimation(.easeOut(duration: 0.2)) {
                isNoteVisible = true
            }
        } else if retainedNoteText != nil, !isNoteEditorPresented {
            // Fade after the editor dismisses, keeping the note's space until it is invisible.
            withAnimation(.easeOut(duration: 0.2), completionCriteria: .removed) {
                isNoteVisible = false
            } completion: {
                guard noteText == nil else { return }
                retainedNoteText = nil
            }
        }
    }

    private var noteText: String? {
        guard let entry, let noteAnchor, let note = entry.episodeNote(at: noteAnchor), !note.isEmpty else {
            return nil
        }
        return note.text.split(whereSeparator: \.isNewline).first.map(String.init)
    }

    private var noteAnchor: EpisodeNoteAnchor? {
        guard let previewContext, entry?.supportsEpisodeNotes == true else { return nil }
        return .init(seasonNumber: previewContext.seasonNumber, episodeNumber: card.episodeNumber)
    }

    @ViewBuilder
    private var statusAccessory: some View {
        if isWatched {
            Image(systemName: "checkmark.circle.fill")
                .font(.subheadline.weight(.semibold))
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(.blue)
                .accessibilityHidden(true)
        } else {
            EmptyView()
        }
    }
}

extension View {
    /// Opens an episode preview: a long press on iOS; on the Mac, where a held click is
    /// undiscoverable, a click or the row's context menu.
    @ViewBuilder
    fileprivate func previewTrigger(isEnabled: Bool, action: @escaping () -> Void) -> some View {
        #if os(macOS)
            if isEnabled {
                contentShape(Rectangle())
                    .onTapGesture(perform: action)
                    .accessibilityAction(named: Text("Preview"), action)
            } else {
                self
            }
        #else
            onLongPressGesture {
                guard isEnabled else { return }
                action()
            }
        #endif
    }
}
