//
//  EntryDetailTrackingComponents.swift
//  MyAnimeList
//
//  Created by OpenAI Codex on behalf of Samuel He on 2026/5/21.
//

import DataProvider
import SwiftUI

struct EntryScoreCard: View {
    let score: EntryScore?
    let onSetScore: (EntryScore?) -> Void

    @State private var bouncingStar: Int?
    /// Frames of the five stars in the row's coordinate space, lowest first.
    @State private var starFrames: [CGRect] = Array(repeating: .zero, count: 5)
    /// The score under a touch drag, shown before it is saved. Resets on its own when
    /// the drag ends or the system cancels it.
    @GestureState private var dragHalves: Int?
    /// The score a drag just dropped, shown until `score` catches up. The drag's reset
    /// redraws this card before the parent passes the saved score back in, which would
    /// otherwise flash the old score for a frame.
    @State private var droppedHalves: Int?
    /// The score under the Mac pointer, shown before a click.
    @State private var hoverHalves: Int?
    @AppStorage(.entryScoreHalfHintSeen) private var halfHintSeen = false

    private let selectionAnimation = Animation.spring(response: 0.28, dampingFraction: 0.82)
    private let bounceInAnimation = Animation.spring(response: 0.18, dampingFraction: 0.42)
    private let bounceOutAnimation = Animation.spring(response: 0.28, dampingFraction: 0.72)
    private let starsSpace = "EntryScoreStars"

    /// Inline drops the title row and the Clear button for the Mac tracking row. There the
    /// pointer picks a whole or a half star, and a click on the current score clears it.
    var isInline = false

    var body: some View {
        if isInline {
            starRow(spacing: 2)
                .onContinuousHover(coordinateSpace: .named(starsSpace)) { phase in
                    switch phase {
                    case .active(let location): hoverHalves = halves(atX: location.x)
                    case .ended: hoverHalves = nil
                    }
                }
                .onTapGesture(coordinateSpace: .named(starsSpace)) { location in
                    guard let halves = halves(atX: location.x) else { return }
                    let tapped = EntryScore(halves: halves)
                    setScore(score == tapped ? nil : tapped, bounces: true)
                }
                // Keyboard navigation replaces the per-star buttons: arrows step by a
                // half star, Delete clears. Like a button, the row takes focus only from
                // keyboard navigation, so a click draws no focus ring.
                .focusable(interactions: .activate)
                .onKeyPress(keys: [.leftArrow, .rightArrow, .upArrow, .downArrow, .delete, .deleteForward]) {
                    press in
                    switch press.key {
                    case .rightArrow, .upArrow: adjustScore(by: 1)
                    case .leftArrow, .downArrow: adjustScore(by: -1)
                    default: setScore(nil)
                    }
                    return .handled
                }
                .contextMenu {
                    Button(EntryDetailL10n.clear) {
                        setScore(nil)
                    }
                    .disabled(score == nil)
                }
        } else {
            VStack(alignment: .leading, spacing: 12) {
                HStack(alignment: .center, spacing: 12) {
                    Label {
                        Text(EntryDetailL10n.score)
                            .font(.subheadline.weight(.semibold))
                    } icon: {
                        Image(systemName: "star")
                            .font(.subheadline.weight(.semibold))
                    }
                    .foregroundStyle(.secondary)

                    if let displayed = displayedScore {
                        Text(verbatim: displayed.formatted)
                            .font(.footnote)
                            .monospacedDigit()
                            .foregroundStyle(.secondary)
                            .contentTransition(.numericText())
                            // Drag previews change without a transaction animation.
                            .animation(selectionAnimation, value: displayed)
                    }

                    // The hint sits in the gap before Clear, so it adds no height to the card.
                    Spacer(minLength: 12)
                        .overlay(alignment: .trailing) {
                            if let hint = halfHint {
                                Text(EntryDetailL10n.scoreHalfHint(hint.formatted))
                                    .font(.caption)
                                    .foregroundStyle(.tertiary)
                                    .lineLimit(1)
                                    .minimumScaleFactor(0.8)
                                    .transition(.opacity)
                            }
                        }

                    Button {
                        setScore(nil)
                    } label: {
                        Text(EntryDetailL10n.clear)
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                    .disabled(score == nil)
                    .opacity(score == nil ? 0.42 : 1)
                }

                starRow(spacing: 10)
                    .onTapGesture(coordinateSpace: .named(starsSpace)) { location in
                        guard let halves = halves(atX: location.x) else { return }
                        tapped(star: (halves + 1) / 2)
                    }
                    .simultaneousGesture(dragGesture)
                    .sensoryFeedback(.selection, trigger: dragHalves) { _, new in new != nil }
                    .onChange(of: score) { droppedHalves = nil }
                    .frame(maxWidth: .infinity)
            }
        }
    }

    private var displayedScore: EntryScore? {
        if let halves = dragHalves ?? droppedHalves ?? hoverHalves { return EntryScore(halves: halves) }
        return score
    }

    /// The half score that a second tap on the top star gives, until the user sets one.
    private var halfHint: EntryScore? {
        guard !halfHintSeen, let score, !score.hasHalf else { return nil }
        return score.stepped(by: -1)
    }

    private func starRow(spacing: CGFloat) -> some View {
        HStack(spacing: spacing) {
            ForEach(1...5, id: \.self) { star in
                starImage(for: star)
                    .onGeometryChange(for: CGRect.self) { proxy in
                        proxy.frame(in: .named(starsSpace))
                    } action: { frame in
                        starFrames[star - 1] = frame
                    }
            }
        }
        .coordinateSpace(.named(starsSpace))
        .contentShape(Rectangle())
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(EntryDetailL10n.score))
        .accessibilityValue(
            score.map { Text(EntryDetailL10n.scoreValue($0.formatted)) } ?? Text(EntryDetailL10n.noScore)
        )
        .accessibilityAdjustableAction { direction in
            switch direction {
            case .increment:
                adjustScore(by: 1)
            case .decrement:
                adjustScore(by: -1)
            @unknown default:
                break
            }
        }
        .accessibilityAction(named: Text(EntryDetailL10n.clear)) {
            setScore(nil)
        }
    }

    private func starImage(for star: Int) -> some View {
        let displayedHalves = displayedScore?.halves ?? 0
        let isFilled = displayedHalves >= star * 2
        let isHalf = displayedHalves == star * 2 - 1
        let isLit = isFilled || isHalf
        let isPreview = hoverHalves != nil && hoverHalves != score?.halves

        return Image(systemName: isFilled ? "star.fill" : isHalf ? "star.leadinghalf.filled" : "star")
            .font((isInline ? Font.body : .title3).weight(isLit ? .semibold : .regular))
            .symbolRenderingMode(.hierarchical)
            .foregroundStyle(isLit ? .yellow : Color.secondary)
            .opacity(isLit ? (isPreview ? 0.7 : 1) : 0.8)
            .scaleEffect(bouncingStar == star ? 1.34 : 1)
            .frame(width: isInline ? 22 : 36, height: isInline ? 22 : 36)
    }

    /// A drag across the stars snaps to halves and saves on release.
    private var dragGesture: some Gesture {
        DragGesture(minimumDistance: 10, coordinateSpace: .named(starsSpace))
            .updating($dragHalves) { drag, dragHalves, _ in
                dragHalves = halves(atX: drag.location.x)
            }
            .onEnded { drag in
                if let halves = halves(atX: drag.location.x) {
                    // An unchanged score never fires `onChange(of: score)` to clear this.
                    if halves != score?.halves {
                        droppedHalves = halves
                    }
                    setScore(EntryScore(halves: halves))
                }
            }
    }

    /// Moves the score by half stars, staying within 1…5. An unscored entry starts at 1.
    private func adjustScore(by steps: Int) {
        guard let score else {
            if steps > 0 { setScore(.lowest) }
            return
        }
        setScore(score.stepped(by: steps) ?? score)
    }

    /// A tap on star N sets N. A tap on the star at the top of the score takes off its
    /// half, or puts it back. Star 1 stays at 1.
    private func tapped(star: Int) {
        let whole = star * 2
        let next: EntryScore? =
            switch score?.halves {
            case whole: EntryScore(halves: whole - 1) ?? score
            default: EntryScore(halves: whole)
            }
        setScore(next, bounces: true)
    }

    /// Half-star units under `x`: each star's leading edge and center that `x` has
    /// passed adds one half. Nil until the stars have been laid out.
    private func halves(atX x: CGFloat) -> Int? {
        guard starFrames.allSatisfy({ $0.width > 0 }) else { return nil }
        let passed = starFrames.flatMap { [$0.minX, $0.midX] }.filter { x >= $0 }.count
        let range = EntryScore.validHalvesRange
        return min(max(passed, range.lowerBound), range.upperBound)
    }

    /// Saves `value`. Only taps and clicks bounce the top star.
    private func setScore(_ value: EntryScore?, bounces: Bool = false) {
        withAnimation(selectionAnimation) {
            onSetScore(value)
            if value?.hasHalf == true {
                halfHintSeen = true
            }
        }
        guard bounces, let value else { return }

        let star = (value.halves + 1) / 2
        withAnimation(bounceInAnimation) {
            bouncingStar = star
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.16) {
            guard bouncingStar == star else { return }
            withAnimation(bounceOutAnimation) {
                bouncingStar = nil
            }
        }
    }
}

struct EntryDetailTrackingSection: View {
    @Environment(\.popupPanelStyle) private var panelStyle
    let entry: AnimeEntry
    var originalNotes: String? = nil
    var originalEpisodeNotes: [EpisodeNote] = []
    let scoringEnabled: Bool
    let episodeProgressTrackingEnabled: Bool
    let onWatchStatusSelected: (AnimeEntry.WatchStatus) -> Void
    let onEpisodeProgressCompletionSuggested: (AnimeEntryEpisodeProgressCompletionPrompt) -> Void
    @Binding var isEditingDetails: Bool

    var body: some View {
        #if os(macOS)
            // The Mac inspector keeps Tracking open, so there is no disclosure header; the
            // card uses the same label/value rows as the stat card above it.
            MacEntryTrackingEditor(
                entry: entry,
                originalNotes: originalNotes,
                originalEpisodeNotes: originalEpisodeNotes,
                scoringEnabled: scoringEnabled,
                episodeProgressTrackingEnabled: episodeProgressTrackingEnabled,
                onWatchStatusSelected: onWatchStatusSelected,
                onEpisodeProgressCompletionSuggested: onEpisodeProgressCompletionSuggested
            )
            .padding(.horizontal, 12)
            .padding(.vertical, 2)
            .popupGlassPanel(cornerRadius: 24)
        #else
            disclosureBody
        #endif
    }

    #if !os(macOS)
        private var disclosureBody: some View {
            Group {
                if scoringEnabled {
                    VStack(alignment: .leading, spacing: 16) {
                        EntryScoreCard(score: entry.entryScore) { entry.updateEntryScore($0) }
                        Divider()

                        PopupNestedDisclosureSection(
                            EntryDetailL10n.tracking,
                            systemImage: "checklist",
                            isExpanded: $isEditingDetails
                        ) {
                            EntryDetailTrackingEditor(
                                entry: entry,
                                originalNotes: originalNotes,
                                originalEpisodeNotes: originalEpisodeNotes,
                                episodeProgressTrackingEnabled: episodeProgressTrackingEnabled,
                                onWatchStatusSelected: onWatchStatusSelected,
                                onEpisodeProgressCompletionSuggested: onEpisodeProgressCompletionSuggested
                            )
                        }
                    }
                    .padding(panelStyle.contentPadding)
                    .popupGlassPanel(cornerRadius: 24)
                } else {
                    PopupDisclosureCard(
                        EntryDetailL10n.tracking,
                        systemImage: "checklist",
                        isExpanded: $isEditingDetails
                    ) {
                        EntryDetailTrackingEditor(
                            entry: entry,
                            originalNotes: originalNotes,
                            originalEpisodeNotes: originalEpisodeNotes,
                            episodeProgressTrackingEnabled: episodeProgressTrackingEnabled,
                            onWatchStatusSelected: onWatchStatusSelected,
                            onEpisodeProgressCompletionSuggested: onEpisodeProgressCompletionSuggested
                        )
                    }
                }
            }
        }
    #endif
}

extension AnimeEntry {
    /// Dropped entries keep their status and dates read-only.
    var isDateTrackingLocked: Bool {
        watchStatus == .dropped
    }

    var showsRewatchControls: Bool {
        watchStatus == .watching || watchStatus == .watched || rewatchCount > 0
    }

    /// The status picker's selection.
    ///
    /// A dropped entry shows Watching under the locked picker.
    @MainActor func activeWatchStatusBinding(onSelect: @escaping (WatchStatus) -> Void) -> Binding<WatchStatus> {
        Binding(
            get: {
                switch self.watchStatus {
                case .planToWatch, .watching, .watched:
                    return self.watchStatus
                case .dropped:
                    return .watching
                }
            },
            set: { onSelect($0) }
        )
    }
}

#if !os(macOS)
    /// The iOS tracking editor; the Mac card uses `MacEntryTrackingEditor`.
    fileprivate struct EntryDetailTrackingEditor: View {
        @Bindable var entry: AnimeEntry
        let originalNotes: String?
        let originalEpisodeNotes: [EpisodeNote]
        let episodeProgressTrackingEnabled: Bool
        let onWatchStatusSelected: (AnimeEntry.WatchStatus) -> Void
        let onEpisodeProgressCompletionSuggested: (AnimeEntryEpisodeProgressCompletionPrompt) -> Void

        private var dateTrackingButtonLabel: LocalizedStringResource {
            entry.isDateTrackingEnabled ? EntryDetailL10n.hideDates : EntryDetailL10n.trackDates
        }

        var body: some View {
            VStack(alignment: .leading, spacing: 18) {
                VStack(alignment: .leading, spacing: 10) {
                    HStack(alignment: .center, spacing: 12) {
                        Text(EntryDetailL10n.watchStatus)
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.secondary)

                        if entry.showsRewatchControls {
                            EntryRewatchControls(entry: entry)
                        }

                        Spacer(minLength: 12)

                        Button {
                            withAnimation(.default) {
                                _ = entry.updateDateTrackingEnabled(!entry.isDateTrackingEnabled)
                            }
                        } label: {
                            Text(dateTrackingButtonLabel)
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(.secondary)
                        }
                        .buttonStyle(.plain)
                    }
                    AnimeEntryWatchedStatusPicker(
                        selection: entry.activeWatchStatusBinding(onSelect: onWatchStatusSelected),
                        isDisabled: entry.isDateTrackingLocked,
                        isRewatching: entry.isRewatching
                    )
                    .pickerStyle(.segmented)

                    if entry.isDateTrackingEnabled {
                        AnimeEntryDatePickers(
                            dateStarted: $entry.dateStarted.onSet { entry.markTrackingModified() },
                            dateFinished: $entry.dateFinished.onSet { entry.markTrackingModified() },
                            isLocked: entry.isDateTrackingLocked
                        )
                    }
                }

                if episodeProgressTrackingEnabled, entry.watchStatus == .watching {
                    EntryEpisodeProgressControl(
                        entry: entry,
                        onCompletionPromptRequested: onEpisodeProgressCompletionSuggested
                    )
                    .id(entry.libraryIdentity.rawID)
                }

                Divider()

                notesSection
            }
            .animation(.default, value: entry.watchStatus)
        }

        private var notesSection: some View {
            EntryNotesSection(entry: entry, originalNotes: originalNotes, originalEpisodeNotes: originalEpisodeNotes)
        }
    }

    fileprivate struct EntryRewatchControls: View {
        @Bindable var entry: AnimeEntry
        @State private var showingEditor = false

        private static let rewatchCountRange = 0...999

        private var badgeTint: Color {
            entry.isRewatching ? .accentColor : .secondary
        }

        var body: some View {
            Button {
                showingEditor = true
            } label: {
                badge
            }
            .buttonStyle(.plain)
            .accessibilityLabel(entry.isRewatching ? EntryDetailL10n.rewatching : EntryDetailL10n.timesRewatched)
            .accessibilityValue(accessibilityValue)
            .popover(isPresented: $showingEditor) {
                editor
                    .padding(16)
                    .presentationCompactAdaptation(.popover)
            }
        }

        private var badge: some View {
            HStack(spacing: 3) {
                Image(systemName: "repeat")
                if entry.isRewatching {
                    Text(EntryDetailL10n.watchNumber(entry.rewatchCount + 1))
                        .monospacedDigit()
                        .contentTransition(.numericText(value: Double(entry.rewatchCount + 1)))
                } else if entry.rewatchCount > 0 {
                    Text(verbatim: "×\(entry.rewatchCount.formatted())")
                        .monospacedDigit()
                        .contentTransition(.numericText(value: Double(entry.rewatchCount)))
                }
            }
            .font(.caption.weight(.semibold))
            .foregroundStyle(badgeTint)
            .lineLimit(1)
            .fixedSize()
            .padding(.horizontal, 7)
            .padding(.vertical, 3)
            .background {
                Capsule()
                    .fill(badgeTint.opacity(0.14))
            }
            .contentShape(Rectangle())
        }

        private var accessibilityValue: Text {
            entry.isRewatching
                ? Text(EntryDetailL10n.watchNumber(entry.rewatchCount + 1))
                : Text(entry.rewatchCount, format: .number)
        }

        private var editor: some View {
            VStack(alignment: .leading, spacing: 10) {
                if entry.watchStatus == .watching {
                    Toggle(isOn: rewatchingBinding) {
                        Text(EntryDetailL10n.rewatching)
                            .font(.subheadline)
                    }
                }

                Stepper(value: rewatchCountBinding, in: Self.rewatchCountRange) {
                    HStack(spacing: 12) {
                        Text(EntryDetailL10n.timesRewatched)
                            .font(.subheadline)
                        Spacer(minLength: 12)
                        Text(entry.rewatchCount, format: .number)
                            .font(.subheadline.weight(.semibold))
                            .monospacedDigit()
                            .foregroundStyle(.secondary)
                            .contentTransition(.numericText(value: Double(entry.rewatchCount)))
                    }
                }
            }
            .frame(idealWidth: 280, maxWidth: 320)
            .fixedSize(horizontal: false, vertical: true)
        }

        private var rewatchingBinding: Binding<Bool> {
            Binding(
                get: { entry.isRewatching },
                set: { isRewatching in
                    withAnimation(.default) {
                        _ = entry.updateRewatching(isRewatching)
                    }
                }
            )
        }

        private var rewatchCountBinding: Binding<Int> {
            Binding(
                get: { entry.rewatchCount },
                set: { count in
                    withAnimation(.default) {
                        _ = entry.updateRewatchCount(count)
                    }
                }
            )
        }
    }
#endif

struct EntryEpisodeProgressControl: View {
    private struct EpisodeProgressFeedbackTrigger: Equatable {
        enum Style: Equatable {
            case selection
            case success
        }

        let seasonNumber: Int
        let episode: Int
        let style: Style
    }

    // The displayed episode count cannot be derived from persisted progress alone.
    // During a drag we need to show the in-flight slider value, and after release we
    // need to keep showing the committed value until `entry` catches up asynchronously.
    // Modeling that explicitly as a tiny state machine is simpler than trying to
    // reconcile a persisted value with several loosely-related transient flags.
    private enum EpisodeProgressInteractionState: Equatable {
        case idle
        case editing(Int)
        case committing(Int)
    }

    @Bindable var entry: AnimeEntry
    let onCompletionPromptRequested: (AnimeEntryEpisodeProgressCompletionPrompt) -> Void
    @State private var selectedSeasonNumber: Int?
    @State private var progressInteractionState: EpisodeProgressInteractionState = .idle
    @State private var progressFeedbackTrigger: EpisodeProgressFeedbackTrigger?

    init(
        entry: AnimeEntry,
        onCompletionPromptRequested: @escaping (AnimeEntryEpisodeProgressCompletionPrompt) -> Void
    ) {
        self.entry = entry
        self.onCompletionPromptRequested = onCompletionPromptRequested
    }

    private let accentColor = Color.blue
    // Keep text transitions and commit handoff on the same spring so the count does
    // not visually desynchronize from the slider interaction.
    private let progressAnimation = Animation.spring(response: 0.28, dampingFraction: 0.86)

    private var seasonOptions: [Int] {
        entry.episodeProgressSeasonOptions
    }

    private var preferredSelectedSeason: Int? {
        if let latestChangedSeason = entry.latestEpisodeProgressSummary?.seasonNumber,
            seasonOptions.contains(latestChangedSeason)
        {
            return latestChangedSeason
        }
        return seasonOptions.first
    }

    private var selectedSeason: Int? {
        if let selectedSeasonNumber, seasonOptions.contains(selectedSeasonNumber) {
            return selectedSeasonNumber
        }
        return preferredSelectedSeason
    }

    private var summary: AnimeEntryEpisodeProgressSummary? {
        selectedSeason.map { entry.episodeProgressSummary(forSeason: $0) }
    }

    var body: some View {
        if let selectedSeason, let summary {
            let displayedEpisode = displayedWatchedThroughEpisode(for: summary)

            VStack(alignment: .leading, spacing: progressSectionSpacing) {
                progressHeader(selectedSeason: selectedSeason, summary: summary, displayedEpisode: displayedEpisode)

                VStack(alignment: .leading, spacing: 4) {
                    #if !os(macOS)
                        progressStepper(
                            selectedSeason: selectedSeason,
                            summary: summary,
                            displayedEpisode: displayedEpisode
                        )
                    #endif

                    if let episodeCount = summary.episodeCount, episodeCount > 0 {
                        EntryEpisodeProgressSlider(
                            episode: sliderEpisodeBinding(
                                for: selectedSeason,
                                summary: summary
                            ),
                            episodeCount: episodeCount,
                            tint: accentColor,
                            onInteractionBegan: {
                                beginSliderInteraction(for: summary)
                            },
                            onInteractionEnded: {
                                commitSliderInteraction(for: selectedSeason, summary: summary)
                            }
                        )
                        #if !os(macOS)
                            .padding(.horizontal, 18)
                        #endif
                        .accessibilityLabel(Text(EntryDetailL10n.episodeProgress))
                        .accessibilityValue(
                            Text("Episode \(displayedEpisode) of \(episodeCount)")
                        )
                    }
                }
                .padding(.top, 2)
            }
            .onChange(of: summary.watchedThroughEpisode) { _, newValue in
                synchronizeInteractionState(with: newValue)
            }
            .onAppear {
                synchronizeSelectedSeasonWithLatestProgress()
            }
            .onChange(of: preferredSelectedSeason) { _, _ in
                synchronizeSelectedSeasonWithLatestProgress()
            }
            .sensoryFeedback(trigger: progressFeedbackTrigger) { _, newValue in
                switch newValue?.style {
                case .selection:
                    .selection
                case .success:
                    .success
                case nil:
                    nil
                }
            }
        }
    }

    private func seasonTitle(for seasonNumber: Int) -> String {
        seasonNumber == 0 ? String(localized: "Specials") : String(localized: "Season \(seasonNumber)")
    }

    private var progressSectionSpacing: CGFloat {
        #if os(macOS)
            6
        #else
            14
        #endif
    }

    @ViewBuilder
    private func seasonControl(selectedSeason: Int) -> some View {
        if seasonOptions.count > 1 {
            Menu {
                ForEach(seasonOptions, id: \.self) { seasonNumber in
                    Button {
                        withAnimation(progressAnimation) {
                            selectedSeasonNumber = seasonNumber
                            progressInteractionState = .idle
                        }
                    } label: {
                        if seasonNumber == selectedSeason {
                            Label(seasonTitle(for: seasonNumber), systemImage: "checkmark")
                        } else {
                            Text(seasonTitle(for: seasonNumber))
                        }
                    }
                }
            } label: {
                seasonPickerLabel(title: seasonTitle(for: selectedSeason))
            }
            .buttonStyle(.plain)
            .fixedSize()
        } else {
            Text(seasonTitle(for: selectedSeason))
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
        }
    }

    private func seasonPickerLabel(title: String) -> some View {
        HStack(spacing: 6) {
            Text(title)
                .font(.caption.weight(.semibold))
                .lineLimit(1)

            Image(systemName: "chevron.down")
                .font(.caption2.weight(.semibold))
        }
        .foregroundStyle(.secondary)
    }

    // MARK: - Platform Rows

    #if os(macOS)
        private func progressHeader(
            selectedSeason: Int,
            summary: AnimeEntryEpisodeProgressSummary,
            displayedEpisode: Int
        ) -> some View {
            // The tracking card's row style: label and season leading, count trailing.
            HStack(alignment: .center, spacing: 12) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(EntryDetailL10n.episodeProgress)
                        .lineLimit(1)
                    seasonControl(selectedSeason: selectedSeason)
                }
                Spacer(minLength: 12)
                macProgressRow(
                    seasonNumber: selectedSeason,
                    summary: summary,
                    displayedEpisode: displayedEpisode
                )
            }
        }

        /// An editable episode number with a stepper, plus the reset and complete actions
        /// that iOS hides behind long presses on its − and + buttons.
        private func macProgressRow(
            seasonNumber: Int,
            summary: AnimeEntryEpisodeProgressSummary,
            displayedEpisode: Int
        ) -> some View {
            let episode = Binding<Int>(
                get: { displayedEpisode },
                set: { setProgress(for: seasonNumber, to: $0) }
            )
            let accessibilityText = progressAccessibilityText(
                watchedThroughEpisode: displayedEpisode,
                episodeCount: summary.episodeCount
            )

            return HStack(spacing: 6) {
                TextField(value: episode, format: .number) {
                    Text(EntryDetailL10n.episodeProgress)
                }
                .labelsHidden()
                .multilineTextAlignment(.trailing)
                .monospacedDigit()
                .frame(width: 52)
                .accessibilityLabel(Text(EntryDetailL10n.episodeProgress))
                .accessibilityValue(Text(accessibilityText))

                if let episodeCount = summary.episodeCount {
                    Text(verbatim: "/ \(episodeCount)")
                        .monospacedDigit()
                        .foregroundStyle(.secondary)
                        .accessibilityHidden(true)
                }

                Stepper(
                    value: episode,
                    in: 0...(summary.episodeCount ?? Int.max)
                ) {
                    Text(EntryDetailL10n.episodeProgress)
                }
                .labelsHidden()

                Menu {
                    Button(EntryDetailL10n.markSeasonWatched, systemImage: "checkmark.circle") {
                        guard let episodeCount = summary.episodeCount else { return }
                        setProgress(for: seasonNumber, to: episodeCount)
                    }
                    .disabled(summary.episodeCount == nil || isAtLimit(summary))

                    Button(EntryDetailL10n.resetProgress, systemImage: "arrow.counterclockwise") {
                        setProgress(for: seasonNumber, to: 0)
                    }
                    .disabled(summary.watchedThroughEpisode == 0)
                } label: {
                    Image(systemName: "ellipsis.circle")
                }
                .menuStyle(.borderlessButton)
                .menuIndicator(.hidden)
                .fixedSize()
                .macHelp(Text("More"))
                .accessibilityLabel(Text("More"))
            }
            // The controls keep their ideal width in a narrow inspector; otherwise the
            // HStack compresses "/ 13" until it wraps. The leading label truncates instead.
            .fixedSize()
        }
    #else
        private func progressHeader(
            selectedSeason: Int,
            summary: AnimeEntryEpisodeProgressSummary,
            displayedEpisode: Int
        ) -> some View {
            HStack(alignment: .center, spacing: 12) {
                Text(EntryDetailL10n.episodeProgress)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)

                Spacer(minLength: 12)

                seasonControl(selectedSeason: selectedSeason)
            }
        }

        private func progressStepper(
            selectedSeason: Int,
            summary: AnimeEntryEpisodeProgressSummary,
            displayedEpisode: Int
        ) -> some View {
            HStack(spacing: 24) {
                progressButton(
                    systemImage: "minus",
                    disabled: summary.watchedThroughEpisode == 0
                ) {
                    adjustProgress(for: selectedSeason, by: -1)
                } longPressAction: {
                    guard summary.watchedThroughEpisode > 0 else { return }
                    adjustProgress(
                        for: selectedSeason,
                        by: -summary.watchedThroughEpisode
                    )
                }

                HStack(alignment: .lastTextBaseline, spacing: 4) {
                    Text("\(displayedEpisode)")
                        .font(.system(size: 30, weight: .bold, design: .rounded))
                        .monospacedDigit()
                        .contentTransition(.numericText(value: Double(displayedEpisode)))

                    if let episodeCount = summary.episodeCount {
                        Text(verbatim: "/\(episodeCount)")
                            .font(.title3.weight(.semibold))
                            .monospacedDigit()
                            .foregroundStyle(.secondary)
                            .contentTransition(.numericText())
                    }
                }
                .lineLimit(1)
                .minimumScaleFactor(0.75)
                .frame(minWidth: 132, minHeight: 54)
                .animation(progressAnimation, value: displayedEpisode)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(
                    progressAccessibilityText(
                        watchedThroughEpisode: displayedEpisode,
                        episodeCount: summary.episodeCount
                    )
                )

                progressButton(
                    systemImage: "plus",
                    disabled: isAtLimit(summary)
                ) {
                    adjustProgress(for: selectedSeason, by: 1)
                } longPressAction: {
                    guard !isAtLimit(summary) else { return }
                    guard let episodeCount = summary.episodeCount else { return }
                    adjustProgress(
                        for: selectedSeason,
                        by: episodeCount - summary.watchedThroughEpisode
                    )
                }
            }
            .frame(maxWidth: .infinity)
        }

        private func progressButton(
            systemImage: String,
            disabled: Bool,
            action: @escaping () -> Void,
            longPressAction: @escaping () -> Void = {}
        ) -> some View {
            Button(action: action) {
                Image(systemName: systemImage)
                    .font(.system(size: 18, weight: .semibold))
                    .frame(width: 38, height: 38)
            }
            .buttonStyle(EntryEpisodeProgressButtonStyle(tint: accentColor))
            .simultaneousGesture(progressButtonLongPressGesture(action: longPressAction))
            .disabled(disabled)
            .opacity(disabled ? 0.5 : 1)
        }

        private func progressButtonLongPressGesture(action: @escaping () -> Void) -> some Gesture {
            LongPressGesture(minimumDuration: 0.5)
                .onEnded { _ in action() }
        }
    #endif

    private func displayedWatchedThroughEpisode(for summary: AnimeEntryEpisodeProgressSummary) -> Int {
        switch progressInteractionState {
        case .idle:
            return summary.watchedThroughEpisode
        case .editing(let episode), .committing(let episode):
            return episode
        }
    }

    private func sliderEpisodeBinding(
        for seasonNumber: Int,
        summary: AnimeEntryEpisodeProgressSummary
    ) -> Binding<Double> {
        Binding(
            get: { Double(displayedWatchedThroughEpisode(for: summary)) },
            set: { newValue in
                let snappedValue = min(max(Int(newValue.rounded()), 0), summary.episodeCount ?? .max)
                let currentDisplayedEpisode = displayedWatchedThroughEpisode(for: summary)
                guard snappedValue != currentDisplayedEpisode else { return }

                triggerProgressFeedback(
                    for: seasonNumber,
                    episode: snappedValue,
                    summary: summary
                )

                withAnimation(progressAnimation) {
                    progressInteractionState = .editing(snappedValue)
                }
            }
        )
    }

    private func progressAccessibilityText(
        watchedThroughEpisode: Int,
        episodeCount: Int?
    ) -> String {
        if let episodeCount {
            return String(
                localized: "Watched through episode \(watchedThroughEpisode) of \(episodeCount)"
            )
        }
        return String(localized: "Watched through episode \(watchedThroughEpisode)")
    }

    private func isAtLimit(_ summary: AnimeEntryEpisodeProgressSummary) -> Bool {
        guard let episodeCount = summary.episodeCount else { return false }
        return summary.watchedThroughEpisode >= episodeCount
    }

    private func adjustProgress(for seasonNumber: Int, by amount: Int) {
        let currentSummary = entry.episodeProgressSummary(forSeason: seasonNumber)
        if amount > 0, isAtLimit(currentSummary) {
            return
        }
        if amount < 0, currentSummary.watchedThroughEpisode == 0 {
            return
        }

        setProgress(for: seasonNumber, to: currentSummary.watchedThroughEpisode + amount)
    }

    private func beginSliderInteraction(for summary: AnimeEntryEpisodeProgressSummary) {
        withAnimation(progressAnimation) {
            progressInteractionState = .editing(displayedWatchedThroughEpisode(for: summary))
        }
    }

    private func commitSliderInteraction(
        for seasonNumber: Int,
        summary: AnimeEntryEpisodeProgressSummary
    ) {
        guard case .editing(let episode) = progressInteractionState else { return }
        setProgress(for: seasonNumber, to: episode)
        if episode == summary.watchedThroughEpisode {
            withAnimation(progressAnimation) {
                progressInteractionState = .idle
            }
        }
    }

    private func setProgress(for seasonNumber: Int, to requestedEpisode: Int) {
        let currentSummary = entry.episodeProgressSummary(forSeason: seasonNumber)
        let sliderPreviewEpisode: Int?
        switch progressInteractionState {
        case .editing(let episode):
            sliderPreviewEpisode = episode
        case .idle, .committing:
            sliderPreviewEpisode = nil
        }
        let clampedEpisode: Int
        if let episodeCount = currentSummary.episodeCount {
            clampedEpisode = min(max(requestedEpisode, 0), episodeCount)
        } else {
            clampedEpisode = max(requestedEpisode, 0)
        }

        guard clampedEpisode != currentSummary.watchedThroughEpisode else {
            withAnimation(progressAnimation) {
                progressInteractionState = .idle
            }
            return
        }

        withAnimation(progressAnimation) {
            progressInteractionState = .committing(clampedEpisode)
        }

        if sliderPreviewEpisode == clampedEpisode {
            // Slider drags already emitted feedback when the snapped value changed.
        } else {
            triggerProgressFeedback(
                for: seasonNumber,
                episode: clampedEpisode,
                summary: currentSummary
            )
        }

        withAnimation(progressAnimation) {
            _ = entry.updateEpisodeProgress(
                seasonNumber: seasonNumber,
                watchedThroughEpisode: clampedEpisode
            )
        }

        if let prompt = entry.episodeProgressCompletionPrompt(
            forSeason: seasonNumber,
            previousWatchedThroughEpisode: currentSummary.watchedThroughEpisode
        ) {
            onCompletionPromptRequested(prompt)
        }
    }

    private func synchronizeInteractionState(with watchedThroughEpisode: Int) {
        guard case .committing(let episode) = progressInteractionState else { return }
        if episode == watchedThroughEpisode {
            withAnimation(progressAnimation) {
                progressInteractionState = .idle
            }
        }
    }

    private func synchronizeSelectedSeasonWithLatestProgress() {
        guard let preferredSelectedSeason else { return }
        guard selectedSeasonNumber != preferredSelectedSeason else { return }

        withAnimation(progressAnimation) {
            selectedSeasonNumber = preferredSelectedSeason
            progressInteractionState = .idle
        }
    }

    private func progressFeedbackStyle(
        for episode: Int,
        summary: AnimeEntryEpisodeProgressSummary
    ) -> EpisodeProgressFeedbackTrigger.Style {
        guard let episodeCount = summary.episodeCount, episodeCount > 0 else {
            return .selection
        }
        return episode >= episodeCount ? .success : .selection
    }

    private func triggerProgressFeedback(
        for seasonNumber: Int,
        episode: Int,
        summary: AnimeEntryEpisodeProgressSummary
    ) {
        progressFeedbackTrigger = EpisodeProgressFeedbackTrigger(
            seasonNumber: seasonNumber,
            episode: episode,
            style: progressFeedbackStyle(for: episode, summary: summary)
        )
    }
}

struct EntryEpisodeProgressSlider: View {
    @Binding var episode: Double
    let episodeCount: Int
    let tint: Color
    let onInteractionBegan: () -> Void
    let onInteractionEnded: () -> Void

    var body: some View {
        Slider(
            value: $episode,
            in: 0...Double(episodeCount),
            step: 1
        )
        // `Slider`'s built-in editing state is unreliable on iOS 26 for this control.
        // We track drag begin/end with an explicit gesture so the parent state machine
        // can deterministically move between `editing` and `committing`.
        .simultaneousGesture(
            DragGesture(minimumDistance: 0)
                .onChanged { _ in
                    onInteractionBegan()
                }
                .onEnded { _ in
                    onInteractionEnded()
                }
        )
        .tint(tint)
        .controlSize(.mini)
    }
}

struct EntryEpisodeProgressButtonStyle: ButtonStyle {
    @Environment(\.colorScheme) private var colorScheme

    let tint: Color

    func makeBody(configuration: Configuration) -> some View {
        let isPressed = configuration.isPressed

        configuration.label
            .foregroundStyle(tint.opacity(isPressed ? 0.9 : 0.76))
            .background {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(backgroundColor(pressed: isPressed))
            }
            .overlay {
                if colorScheme == .dark {
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .stroke(.white.opacity(isPressed ? 0.14 : 0.08))
                }
            }
            .scaleEffect(isPressed ? 0.96 : 1)
            .animation(
                .spring(response: 0.22, dampingFraction: 0.82),
                value: isPressed
            )
    }

    private func backgroundColor(pressed: Bool) -> Color {
        if colorScheme == .dark {
            return .white.opacity(pressed ? 0.12 : 0.07)
        }

        return .primary.opacity(pressed ? 0.10 : 0.06)
    }
}
