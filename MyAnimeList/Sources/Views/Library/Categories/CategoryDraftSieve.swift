//
//  CategoryDraftSieve.swift
//  AniShelf
//
//  Created by Claude Code on behalf of Samuel He on 2026/10/30.
//

import SwiftUI

/// The run and the review of "Describe a Category" in one view.
///
/// The plan arrives as an editable name and filter chips. Every candidate then shows as a
/// dimmed poster that each finished batch lights up or fades back, so the result forms
/// during the wait. When the check ends, matches stay in the grid and the rest leave it for
/// a collapsed Not included section, where any of them can still be added.
///
/// Posters keep their places until the check ends, so a tap during the check never misses.
struct CategoryDraftSieve: View {
    @Bindable var draft: CategoryDraftModel
    @Environment(LibraryStore.self) private var store
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var showsNotIncluded = false
    /// The characters of the suggested name shown so far, while it types in; `nil` once done.
    @State private var typedName: String?
    @State private var shownChipCount = 0
    /// Whether the plan's candidates have faded in; a state rather than a transition, so a
    /// poster the lazy grid builds later reads it as already shown.
    @State private var hasArrived = false

    private let columns = [GridItem(.adaptive(minimum: 78), spacing: 10, alignment: .top)]

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 0, pinnedViews: .sectionHeaders) {
                header
                    .padding(.horizontal, 20)
                    .padding(.top, 4)
                Section {
                    content
                } header: {
                    statusCapsule
                }
            }
            .padding(.bottom, 24)
        }
        .scrollDismissesKeyboard(.interactively)
        .preferredNavigationBarScrollEdgeEffect()
        .animation(.smooth(duration: 0.4), value: draft.proposal == nil)
        // The pause lets the last batch's ripple land before the posters move.
        .animation(settleAnimation.delay(0.4), value: isSettled)
        .animation(settleAnimation, value: listedCount)
        .task(id: draft.proposal == nil) { await revealPlan() }
        .onChange(of: isSettled) { _, isSettled in
            // With nothing matched, the only useful posters are the ones left out.
            if isSettled, listedCount == 0 { showsNotIncluded = true }
        }
    }

    private var items: [AIProposal<CategoryDraftCandidate>.Item] {
        draft.proposal?.items.items ?? []
    }

    private var isSettled: Bool {
        switch draft.state {
        case .review, .applied: true
        default: false
        }
    }

    private var listedCount: Int {
        items.count { $0.value.isListed }
    }

    /// The settle is the one large movement in the flow; Reduce Motion turns it into a cross-fade.
    private var settleAnimation: Animation {
        reduceMotion ? .easeInOut(duration: 0.3) : .spring(response: 0.55, dampingFraction: 0.86)
    }

    // MARK: - Header

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("“\(draft.trimmedRequest)”")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .lineLimit(2)

            if let proposal = draft.proposal {
                ZStack(alignment: .leading) {
                    TextField("Category Name", text: nameBinding)
                        .submitLabel(.done)
                        .opacity(typedName == nil ? 1 : 0)
                    if let typedName {
                        Text(verbatim: typedName)
                    }
                }
                .font(.title.bold())

                if !isNameValid(proposal.name), typedName == nil {
                    Text("Category names must not be empty, must be unique, and can have up to 40 characters.")
                        .font(.footnote)
                        .foregroundStyle(.orange)
                }

                let chips = Self.chips(for: proposal.plan)
                FlowLayout(spacing: 7, lineSpacing: 7) {
                    ForEach(chips) { chip in
                        chipView(chip)
                            .opacity(chip.id < shownChipCount ? 1 : 0)
                            .scaleEffect(chip.id < shownChipCount ? 1 : 0.6)
                    }
                }
                .padding(.top, 4)

                if !proposal.unsupportedRequest.isEmpty {
                    Label {
                        Text("Not applied. AniShelf cannot filter by this, so the list ignores it.")
                    } icon: {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundStyle(.orange)
                    }
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .padding(.top, 4)
                }
            } else {
                planPlaceholder
            }
        }
    }

    private var planPlaceholder: some View {
        VStack(alignment: .leading, spacing: 12) {
            placeholderShape(width: 210, height: 30, cornerRadius: 8)
            HStack(spacing: 7) {
                ForEach([72.0, 96, 128], id: \.self) { width in
                    placeholderShape(width: width, height: 30, cornerRadius: 15)
                }
            }
        }
        .padding(.vertical, 4)
    }

    private func placeholderShape(width: CGFloat, height: CGFloat, cornerRadius: CGFloat) -> some View {
        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
            .fill(.fill.tertiary)
            .overlay { CategoryDraftShimmer() }
            .clipShape(.rect(cornerRadius: cornerRadius, style: .continuous))
            .frame(width: width, height: height)
    }

    /// Types the suggested name in and pops the chips in after it.
    private func revealPlan() async {
        guard let proposal = draft.proposal else {
            typedName = nil
            shownChipCount = 0
            hasArrived = false
            return
        }
        // The posters have drawn hidden; each cell animates in with its own delay.
        hasArrived = true
        let chipCount = Self.chips(for: proposal.plan).count
        let name = Array(proposal.name)
        for length in 0...name.count {
            typedName = String(name.prefix(length))
            let revealed = min(chipCount, length / 3)
            if revealed > shownChipCount {
                withAnimation(.spring(response: 0.36, dampingFraction: 0.62)) { shownChipCount = revealed }
            }
            try? await Task.sleep(for: .milliseconds(32))
            guard !Task.isCancelled else { break }
        }
        typedName = nil
        withAnimation(.spring(response: 0.36, dampingFraction: 0.62)) { shownChipCount = chipCount }
    }

    // MARK: - Chips

    struct Chip: Identifiable {
        enum Style {
            case filter, criterion, unsupported
        }

        let id: Int
        let systemImage: String
        let text: Text
        var style = Style.filter
    }

    /// What the plan read out of the request, one chip per filter.
    static func chips(for plan: CategoryQueryPlan) -> [Chip] {
        var parts: [(String, Text, Chip.Style)] = []
        for kind in CategoryEntryKind.allCases where plan.kinds.contains(kind) {
            switch kind {
            case .movie: parts.append(("film", Text("Movies"), .filter))
            case .series: parts.append(("tv", Text("TV Series"), .filter))
            case .season: parts.append(("square.stack", Text("Seasons"), .filter))
            }
        }
        for status in CategoryWatchStatus.allCases where plan.watchStatuses.contains(status) {
            switch status {
            case .planToWatch: parts.append(("clock", Text("Plan to Watch"), .filter))
            case .watching: parts.append(("play.circle", Text("Watching"), .filter))
            case .watched: parts.append(("checkmark.circle", Text("Watched"), .filter))
            case .dropped: parts.append(("xmark.circle", Text("Dropped"), .filter))
            }
        }
        if plan.favoritesOnly {
            parts.append(("heart", Text("Favorites"), .filter))
        }
        let low = plan.minimumScore > 0 ? plan.minimumScore.formatted() : nil
        let high = plan.maximumScore > 0 ? plan.maximumScore.formatted() : nil
        switch (low, high) {
        case (let low?, let high?): parts.append(("star", Text(verbatim: "\(low)–\(high)★"), .filter))
        case (let low?, nil): parts.append(("star", Text("\(low)★ or higher"), .filter))
        case (nil, let high?): parts.append(("star", Text("\(high)★ or lower"), .filter))
        case (nil, nil): break
        }
        if let years = yearRange(plan.earliestYear, plan.latestYear) {
            parts.append(("calendar", Text(verbatim: years), .filter))
        }
        if let years = yearRange(plan.earliestFinishYear, plan.latestFinishYear) {
            parts.append(("flag.checkered", Text("Finished \(years)"), .filter))
        }
        if plan.needsCheck {
            let label = plan.trimmedCriterionLabel.isEmpty ? plan.trimmedCriterion : plan.trimmedCriterionLabel
            parts.append(("sparkles", Text(verbatim: label), .criterion))
        }
        if !plan.trimmedUnsupportedRequest.isEmpty {
            parts.append(
                (
                    "exclamationmark.triangle.fill", Text(verbatim: plan.trimmedUnsupportedRequest).strikethrough(),
                    .unsupported
                ))
        }
        return parts.enumerated().map { Chip(id: $0, systemImage: $1.0, text: $1.1, style: $1.2) }
    }

    /// "2010–2019", "2010–", or "–2019"; plain digits, so no locale groups a year.
    private static func yearRange(_ earliest: Int, _ latest: Int) -> String? {
        switch (earliest > 0, latest > 0) {
        case (true, true): earliest == latest ? String(earliest) : "\(earliest)–\(latest)"
        case (true, false): "\(earliest)–"
        case (false, true): "–\(latest)"
        case (false, false): nil
        }
    }

    private func chipView(_ chip: Chip) -> some View {
        Label {
            chip.text
                .lineLimit(1)
        } icon: {
            Image(systemName: chip.systemImage)
                .imageScale(.small)
        }
        .font(.subheadline.weight(.medium))
        .padding(.horizontal, 11)
        .frame(height: 30)
        .foregroundStyle(chipForeground(chip.style))
        .background(chipBackground(chip.style), in: .capsule)
    }

    private func chipForeground(_ style: Chip.Style) -> AnyShapeStyle {
        switch style {
        case .filter: AnyShapeStyle(.primary)
        case .criterion: AnyShapeStyle(.tint)
        case .unsupported: AnyShapeStyle(.orange)
        }
    }

    private func chipBackground(_ style: Chip.Style) -> AnyShapeStyle {
        switch style {
        case .filter: AnyShapeStyle(.fill.tertiary)
        case .criterion: AnyShapeStyle(Color.accentColor.opacity(0.15))
        case .unsupported: AnyShapeStyle(Color.orange.opacity(0.15))
        }
    }

    // MARK: - Status

    /// Pinned under the navigation bar while the plan or the check runs.
    @ViewBuilder
    private var statusCapsule: some View {
        if draft.state == .planning || draft.state == .checking {
            let found = items.count { $0.value.verdict == .match }
            let checked = items.count { $0.value.verdict.isResolved }
            let fraction = items.isEmpty ? 0 : Double(checked) / Double(items.count)
            HStack(spacing: 8) {
                if draft.state == .planning || items.isEmpty {
                    ProgressView()
                        .controlSize(.small)
                    Text("Reading your request…")
                } else {
                    Circle()
                        .fill(.tint)
                        .frame(width: 7, height: 7)
                        .phaseAnimator([1.0, 0.3]) { dot, opacity in
                            dot.opacity(opacity)
                        } animation: { _ in
                            .easeInOut(duration: 0.6)
                        }
                    Text(
                        "\(Text("\(found)").fontWeight(.bold).foregroundStyle(.tint)) found"
                    )
                    .contentTransition(.numericText(value: Double(found)))
                    Text(verbatim: "·")
                        .foregroundStyle(.tertiary)
                    Text("\(checked) of \(items.count) checked")
                }
            }
            // Blur, not a plain cross-fade, so the two lines never read as one garbled line.
            .id(draft.state == .planning || items.isEmpty)
            .transition(.blurReplace)
            .font(.subheadline)
            .monospacedDigit()
            .foregroundStyle(.secondary)
            .padding(.horizontal, 16)
            .frame(height: 34)
            .background(alignment: .leading) {
                GeometryReader { proxy in
                    Capsule()
                        .fill(Color.accentColor.opacity(0.14))
                        .frame(width: proxy.size.width * fraction)
                }
            }
            .clipShape(.capsule)
            .glassEffect(.regular, in: .capsule)
            .animation(.snappy, value: found)
            .animation(.smooth, value: fraction)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 10)
            // Gone before the review's header fades in at the same place.
            .transition(.opacity.animation(.easeOut(duration: 0.15)))
        }
    }

    // MARK: - Content

    @ViewBuilder
    private var content: some View {
        if isSettled, items.isEmpty {
            ContentUnavailableView {
                Label("No Matching Anime", systemImage: "folder.badge.questionmark")
            } description: {
                Text("Try a broader description.")
            } actions: {
                Button("Edit Description") { draft.edit() }
                    .buttonStyle(.glassProminent)
            }
            .padding(.top, 24)
        } else if !items.isEmpty {
            VStack(alignment: .leading, spacing: 0) {
                if isSettled {
                    listedHeader
                    if listedCount == 0 {
                        Text("No matches. Pick from Not included below, or edit the description.")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                            .frame(maxWidth: .infinity)
                            .padding(16)
                            .background(.fill.quaternary, in: .rect(cornerRadius: 16))
                            .padding(.horizontal, 16)
                    }
                }
                mainGrid
                if isSettled, items.contains(where: { !$0.value.isListed }) {
                    notIncludedSection
                        .transition(.opacity)
                }
            }
        }
    }

    private var listedHeader: some View {
        let accepted = items.count(where: \.isAccepted)
        return HStack(alignment: .firstTextBaseline) {
            Text("In this category")
                .font(.headline)
            Spacer()
            Text("\(accepted) selected")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .monospacedDigit()
                .contentTransition(.numericText(value: Double(accepted)))
                .animation(.snappy, value: accepted)
        }
        .padding(.horizontal, 20)
        .padding(.top, 14)
        .padding(.bottom, 10)
        .transition(.opacity)
    }

    /// Every candidate while checking; only the listed ones once the check settles.
    ///
    /// One grid in both phases, so the posters that stay slide into place while the rest
    /// shrink away.
    private var mainGrid: some View {
        let shown = isSettled ? items.filter(\.value.isListed) : items
        return LazyVGrid(columns: columns, alignment: .leading, spacing: 14) {
            ForEach(Array(shown.enumerated()), id: \.element.id) { index, item in
                // The plan's candidates spread in from the top when they arrive.
                cell(item, isNotIncluded: false)
                    .opacity(hasArrived ? 1 : 0)
                    .scaleEffect(hasArrived ? 1 : 0.92)
                    .animation(.smooth(duration: 0.4).delay(min(Double(index) * 0.015, 0.45)), value: hasArrived)
                    .transition(gridCellTransition)
            }
        }
        .padding(.horizontal, 16)
        .padding(.top, 4)
        // Reduce Motion swaps the whole grid instead of moving its posters.
        .id(reduceMotion ? isSettled : false)
        .transition(.opacity)
    }

    private var notIncludedSection: some View {
        let rest = items.filter { !$0.value.isListed }
        return VStack(alignment: .leading, spacing: 12) {
            Button {
                withAnimation(.snappy) { showsNotIncluded.toggle() }
            } label: {
                HStack(spacing: 12) {
                    if !showsNotIncluded {
                        pile(of: rest)
                    }
                    Text("Not included")
                        .foregroundStyle(.primary)
                    Spacer()
                    Text("\(rest.count)")
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                    Image(systemName: "chevron.right")
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(.tertiary)
                        .rotationEffect(.degrees(showsNotIncluded ? 90 : 0))
                }
                .padding(.horizontal, 14)
                .frame(minHeight: 50)
                .background(.fill.quaternary, in: .rect(cornerRadius: 14, style: .continuous))
                .contentShape(.rect)
            }
            .buttonStyle(.plain)
            .padding(.horizontal, 16)

            if showsNotIncluded {
                uncheckedRow(rest)
                Text("The model left these out. Tap a poster to add it.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 20)
                LazyVGrid(columns: columns, alignment: .leading, spacing: 14) {
                    ForEach(rest) { item in
                        cell(item, isNotIncluded: true)
                            .transition(gridCellTransition)
                    }
                }
                .padding(.horizontal, 16)
            }
        }
        .padding(.top, 24)
    }

    /// No insertion transition: during the settle, the lazy grid builds cells for posters
    /// that move into view, and those posters should simply be there.
    private var gridCellTransition: AnyTransition {
        .asymmetric(insertion: .identity, removal: .opacity.combined(with: .scale(scale: 0.6)))
    }

    /// A small fanned stack of the last three left-out posters.
    private func pile(of rest: [AIProposal<CategoryDraftCandidate>.Item]) -> some View {
        ZStack {
            ForEach(Array(rest.suffix(3).reversed().enumerated()), id: \.element.id) { fromTop, item in
                KFImageView(
                    url: item.value.metadata.posterURL(for: .grid),
                    targetSize: TMDbPosterDisplayType.grid.targetSize,
                    diskCacheExpiration: .shortTerm
                )
                .scaledToFill()
                .frame(width: 20, height: 30)
                .clipShape(.rect(cornerRadius: 3))
                .rotationEffect(.degrees([7.0, -5, 0][fromTop]))
                .zIndex(Double(-fromTop))
            }
        }
        .frame(width: 26, height: 34)
        .transition(.opacity)
    }

    @ViewBuilder
    private func uncheckedRow(_ rest: [AIProposal<CategoryDraftCandidate>.Item]) -> some View {
        let waiting = rest.count { $0.value.verdict != .match && $0.value.verdict != .rejected }
        if waiting > 0 {
            HStack(spacing: 8) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(.orange)
                Group {
                    if draft.isRechecking {
                        Text("Checking \(waiting) again…")
                    } else {
                        Text("\(waiting) could not be checked")
                    }
                }
                .monospacedDigit()
                Spacer()
                Button("Check Again", systemImage: "arrow.clockwise") { draft.recheck() }
                    .fontWeight(.semibold)
                    .buttonStyle(.borderless)
                    .disabled(!draft.canRecheck)
            }
            .font(.subheadline)
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .background(Color.orange.opacity(0.12), in: .rect(cornerRadius: 12, style: .continuous))
            .padding(.horizontal, 16)
        }
    }

    private func cell(_ item: AIProposal<CategoryDraftCandidate>.Item, isNotIncluded: Bool) -> some View {
        CategoryDraftPosterCell(candidate: item.value, isAccepted: item.isAccepted, isNotIncluded: isNotIncluded) {
            guard let index = draft.proposal?.items.items.firstIndex(where: { $0.id == item.id }) else { return }
            draft.proposal?.items.items[index].isAccepted.toggle()
        }
        .equatable()
    }

    // MARK: - Name

    private func isNameValid(_ name: String) -> Bool {
        store.validatedCategoryName(name) != nil
    }

    /// Animates only the keystroke that shows or hides the name warning.
    private var nameBinding: Binding<String> {
        Binding(
            get: { draft.proposal?.name ?? "" },
            set: { name in
                guard isNameValid(name) != isNameValid(draft.proposal?.name ?? "") else {
                    draft.proposal?.name = name
                    return
                }
                withAnimation(.snappy) { draft.proposal?.name = name }
            }
        )
    }
}
