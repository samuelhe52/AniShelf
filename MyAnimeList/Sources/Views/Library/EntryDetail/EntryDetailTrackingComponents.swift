//
//  EntryDetailTrackingComponents.swift
//  MyAnimeList
//
//  Created by OpenAI Codex on 2026/5/21.
//

import DataProvider
import SwiftUI

struct EntryScoreCard: View {
    let entry: AnimeEntry

    @State private var bouncingScore: Int?

    private let selectionAnimation = Animation.spring(response: 0.28, dampingFraction: 0.82)
    private let bounceInAnimation = Animation.spring(response: 0.18, dampingFraction: 0.42)
    private let bounceOutAnimation = Animation.spring(response: 0.28, dampingFraction: 0.72)

    var body: some View {
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

                Spacer(minLength: 12)

                Button {
                    withAnimation(selectionAnimation) {
                        entry.setScore(nil)
                    }
                } label: {
                    Text(EntryDetailL10n.clear)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .disabled(entry.score == nil)
                .opacity(entry.score == nil ? 0.42 : 1)
            }

            HStack(spacing: 10) {
                ForEach(Array(AnimeEntry.validScoreRange), id: \.self) { value in
                    scoreButton(for: value)
                }
            }
            .frame(maxWidth: .infinity)
        }
    }

    private func scoreButton(for value: Int) -> some View {
        let isFilled = (entry.score ?? 0) >= value
        let isBouncing = bouncingScore == value

        return Button {
            setScore(value)
        } label: {
            Image(systemName: isFilled ? "star.fill" : "star")
                .font(.title3.weight(.semibold))
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(isFilled ? .yellow : .secondary)
                .scaleEffect(isBouncing ? 1.34 : 1)
                .frame(width: 36, height: 36)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(value)/5")
    }

    private func setScore(_ value: Int) {
        withAnimation(selectionAnimation) {
            entry.setScore(value)
        }
        withAnimation(bounceInAnimation) {
            bouncingScore = value
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.16) {
            guard bouncingScore == value else { return }
            withAnimation(bounceOutAnimation) {
                bouncingScore = nil
            }
        }
    }
}

struct EntryDetailTrackingSection: View {
    let entry: AnimeEntry
    let scoringEnabled: Bool
    let episodeProgressTrackingEnabled: Bool
    let onWatchStatusSelected: (AnimeEntry.WatchStatus) -> Void
    let onEpisodeProgressCompletionSuggested: (AnimeEntryEpisodeProgressCompletionPrompt) -> Void
    @Binding var isEditingDetails: Bool

    var body: some View {
        Group {
            if scoringEnabled {
                VStack(alignment: .leading, spacing: 16) {
                    EntryScoreCard(entry: entry)
                    Divider()

                    PopupNestedDisclosureSection(
                        EntryDetailL10n.tracking,
                        systemImage: "checklist",
                        isExpanded: $isEditingDetails
                    ) {
                        EntryDetailTrackingEditor(
                            entry: entry,
                            episodeProgressTrackingEnabled: episodeProgressTrackingEnabled,
                            onWatchStatusSelected: onWatchStatusSelected,
                            onEpisodeProgressCompletionSuggested: onEpisodeProgressCompletionSuggested
                        )
                    }
                }
                .padding(18)
                .popupGlassPanel(cornerRadius: 24)
            } else {
                PopupDisclosureCard(
                    EntryDetailL10n.tracking,
                    systemImage: "checklist",
                    isExpanded: $isEditingDetails
                ) {
                    EntryDetailTrackingEditor(
                        entry: entry,
                        episodeProgressTrackingEnabled: episodeProgressTrackingEnabled,
                        onWatchStatusSelected: onWatchStatusSelected,
                        onEpisodeProgressCompletionSuggested: onEpisodeProgressCompletionSuggested
                    )
                }
            }
        }
    }
}

fileprivate struct EntryDetailTrackingEditor: View {
    @Bindable var entry: AnimeEntry
    let episodeProgressTrackingEnabled: Bool
    let onWatchStatusSelected: (AnimeEntry.WatchStatus) -> Void
    let onEpisodeProgressCompletionSuggested: (AnimeEntryEpisodeProgressCompletionPrompt) -> Void

    private var dateTrackingButtonLabel: LocalizedStringResource {
        entry.isDateTrackingEnabled ? EntryDetailL10n.hideDates : EntryDetailL10n.trackDates
    }

    private var isDateTrackingLocked: Bool {
        entry.watchStatus == .dropped
    }

    private var activeWatchStatusBinding: Binding<AnimeEntry.WatchStatus> {
        Binding(
            get: {
                switch entry.watchStatus {
                case .planToWatch, .watching, .watched:
                    return entry.watchStatus
                case .dropped:
                    return .watching
                }
            },
            set: {
                onWatchStatusSelected($0)
            }
        )
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            VStack(alignment: .leading, spacing: 10) {
                HStack(alignment: .center, spacing: 12) {
                    Text(EntryDetailL10n.watchStatus)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)

                    Spacer(minLength: 12)

                    Button {
                        withAnimation(.default) {
                            entry.setDateTrackingEnabled(!entry.isDateTrackingEnabled)
                        }
                    } label: {
                        Text(dateTrackingButtonLabel)
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                }
                AnimeEntryWatchedStatusPicker(
                    selection: activeWatchStatusBinding,
                    isDisabled: isDateTrackingLocked
                )
                .pickerStyle(.segmented)

                if entry.isDateTrackingEnabled {
                    AnimeEntryDatePickers(
                        dateStarted: $entry.dateStarted,
                        dateFinished: $entry.dateFinished,
                        isLocked: isDateTrackingLocked
                    )
                }
            }

            if episodeProgressTrackingEnabled, entry.watchStatus == .watching {
                EntryEpisodeProgressControl(
                    entry: entry,
                    onCompletionPromptRequested: onEpisodeProgressCompletionSuggested
                )
            }

            Divider()

            VStack(alignment: .leading, spacing: 10) {
                Text(EntryDetailL10n.notes)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                PlaceholderTextEditor(
                    text: Binding(
                        get: { entry.notes },
                        set: { entry.notes = $0 }
                    ),
                    placeholder: EntryDetailL10n.writeSomeThoughts
                )
                .frame(height: 180)
                .padding(12)
                .background(
                    .thinMaterial,
                    in: RoundedRectangle(cornerRadius: 16, style: .continuous)
                )
                .overlay {
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .stroke(.white.opacity(0.1), lineWidth: 0.5)
                }
            }
        }
        .animation(.default, value: entry.watchStatus)
    }
}

fileprivate struct EntryEpisodeProgressControl: View {
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

            VStack(alignment: .leading, spacing: 14) {
                HStack(alignment: .center, spacing: 12) {
                    Text(EntryDetailL10n.episodeProgress)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)

                    Spacer(minLength: 12)

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
                    } else {
                        Text(seasonTitle(for: selectedSeason))
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.secondary)
                    }
                }

                VStack(alignment: .leading, spacing: 4) {
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

                    if let episodeCount = summary.episodeCount, episodeCount > 0 {
                        EntryEpisodeProgressSlider(
                            episode: sliderEpisodeBinding(for: summary),
                            episodeCount: episodeCount,
                            tint: accentColor,
                            onInteractionBegan: {
                                beginSliderInteraction(for: summary)
                            },
                            onInteractionEnded: {
                                commitSliderInteraction(for: selectedSeason, summary: summary)
                            }
                        )
                        .padding(.horizontal, 18)
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
        }
    }

    private func seasonTitle(for seasonNumber: Int) -> String {
        seasonNumber == 0 ? String(localized: "Specials") : String(localized: "Season \(seasonNumber)")
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

    private func displayedWatchedThroughEpisode(for summary: AnimeEntryEpisodeProgressSummary) -> Int {
        switch progressInteractionState {
        case .idle:
            return summary.watchedThroughEpisode
        case .editing(let episode), .committing(let episode):
            return episode
        }
    }

    private func sliderEpisodeBinding(for summary: AnimeEntryEpisodeProgressSummary) -> Binding<Double> {
        Binding(
            get: { Double(displayedWatchedThroughEpisode(for: summary)) },
            set: { newValue in
                let snappedValue = min(max(Int(newValue.rounded()), 0), summary.episodeCount ?? .max)
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

        withAnimation(progressAnimation) {
            entry.setEpisodeProgress(
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
