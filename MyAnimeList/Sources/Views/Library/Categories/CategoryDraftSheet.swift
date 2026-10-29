//
//  CategoryDraftSheet.swift
//  AniShelf
//
//  Created by Claude Code on behalf of Samuel He on 2026/10/29.
//

import SwiftUI

/// "Describe a Category": the user writes what the category holds, reviews the anime the
/// model proposes, and applies the result.
///
/// The library changes only when the user taps Create Category.
struct CategoryDraftSheet: View {
    /// The visible step.
    ///
    /// Progress within a step, such as the checked count, does not change it, so only real step
    /// changes cross-fade.
    private enum Step: Hashable {
        case describing
        case working
        case review
        case failed
    }

    @Environment(LibraryStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @State private var draft: CategoryDraftModel
    @State private var showsApplyFailure = false
    private let onApplied: (LibraryCategory.ID) -> Void

    init(backend: AIBackend, onApplied: @escaping (LibraryCategory.ID) -> Void = { _ in }) {
        _draft = State(initialValue: CategoryDraftModel(backend: backend))
        self.onApplied = onApplied
    }

    var body: some View {
        NavigationStack {
            ZStack {
                switch step {
                case .describing:
                    describeStep
                        .transition(.opacity)
                case .working:
                    progressView
                        .transition(.opacity)
                case .review:
                    reviewContent
                        .transition(.opacity)
                case .failed:
                    failureView
                        .transition(.opacity)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .animation(stepAnimation, value: step)
            #if !os(macOS)
                // The Mac puts these actions in the sheet's toolbar. A bar, not an inset, so the
                // scroll edge effect keeps rows from showing through a disabled button.
                .safeAreaBar(edge: .bottom) {
                    bottomAction
                    .animation(stepAnimation, value: step)
                }
            #endif
            .navigationTitle(title)
            .inlineNavigationTitle()
            .toolbar { toolbar }
        }
        .macSheetFrame(width: 480, height: 560)
        .alert("Could Not Create the Category", isPresented: $showsApplyFailure) {
            Button("OK", role: .cancel) {}
        } message: {
            Text("The name is already taken, or the selected anime are no longer in your library.")
        }
        .onDisappear { draft.cancel() }
        .onChange(of: draft.state) { _, state in
            guard case .applied(let id) = state else { return }
            onApplied(id)
            dismiss()
        }
    }

    private var step: Step {
        switch draft.state {
        case .describing: .describing
        case .planning, .checking: .working
        // Keep the review on screen while the sheet dismisses.
        case .review, .applied: .review
        case .failed: .failed
        }
    }

    private var title: LocalizedStringResource {
        step == .review ? "New Category" : "Describe a Category"
    }

    private var stepAnimation: Animation {
        .spring(response: 0.34, dampingFraction: 0.88)
    }

    // MARK: - Describe

    private var describeStep: some View {
        @Bindable var draft = draft
        return PromptEditorStep(
            text: $draft.request,
            placeholder: "For example: fantasy anime I finished, or movies from Studio Ghibli",
            autofocus: true
        ) {
            backendNote
        } footer: {
            lengthWarning
        }
    }

    private var backendNote: some View {
        Text("\(draft.backend.displayName) checks your library. You review the result before anything changes.")
            .fixedSize(horizontal: false, vertical: true)
    }

    @ViewBuilder
    private var lengthWarning: some View {
        if draft.trimmedRequest.count > CategoryQueryPlan.maximumRequestLength {
            Text("Shorten the description to \(CategoryQueryPlan.maximumRequestLength) characters or fewer.")
                .foregroundStyle(.orange)
        }
    }

    private func start() {
        guard draft.canStart else { return }
        #if !os(macOS)
            PlaceholderTextEditor.dismissKeyboard()
        #endif
        draft.start(library: store.library)
    }

    // MARK: - Progress

    /// The description leads, since it is what the search runs on; one status line under the
    /// bar carries both the count and the total.
    private var progressView: some View {
        let checking: (done: Int, total: Int)? =
            if case .checking(let done, let total) = draft.state { (done, total) } else { nil }
        return VStack(spacing: 24) {
            Text(verbatim: draft.trimmedRequest)
                .font(.title3.weight(.semibold))
                .multilineTextAlignment(.center)
                .lineLimit(3)

            VStack(spacing: 10) {
                ZStack {
                    if let checking {
                        ProgressView(value: Double(checking.done), total: Double(max(checking.total, 1)))
                            .transition(.opacity)
                    } else {
                        ProgressView()
                            .transition(.opacity)
                    }
                }
                .frame(maxWidth: 240, minHeight: 20)

                Group {
                    if let checking {
                        // Plain digits: the count can tick faster than a numeric roll settles.
                        Text("Checking \(checking.done) of \(checking.total) anime")
                    } else {
                        Text("Reading your request…")
                    }
                }
                .font(.subheadline)
                .monospacedDigit()
                .foregroundStyle(.secondary)
            }

            Button("Edit Description") { draft.edit() }
                .buttonStyle(.bordered)
        }
        .frame(maxWidth: 400)
        .padding(24)
        .animation(.snappy, value: checking?.done)
        .animation(stepAnimation, value: checking == nil)
    }

    // MARK: - Failure

    @ViewBuilder
    private var failureView: some View {
        if case .failed(let error) = draft.state {
            ContentUnavailableView {
                Label("Could Not Finish", systemImage: "exclamationmark.triangle")
            } description: {
                Text(error.message)
            } actions: {
                Button("Try Again") { draft.retry(library: store.library) }
                    .buttonStyle(.glassProminent)
                Button("Edit Description") { draft.edit() }
            }
        }
    }

    // MARK: - Review

    @ViewBuilder
    private var reviewContent: some View {
        if let proposal = draft.proposal, !proposal.items.items.isEmpty {
            reviewList(proposal)
        } else {
            ContentUnavailableView {
                Label("No Matching Anime", systemImage: "folder.badge.questionmark")
            } description: {
                if let proposal = draft.proposal, proposal.uncheckedCount > 0 {
                    Text(
                        "\(proposal.uncheckedCount) anime could not be checked. Try again, or try a broader description."
                    )
                } else {
                    Text("Try a broader description.")
                }
                // The search ran without this constraint, so the user should still see it here.
                if let proposal = draft.proposal, !proposal.unsupportedRequest.isEmpty {
                    unsupportedWarning(proposal.unsupportedRequest)
                }
            } actions: {
                Button("Edit Description") { draft.edit() }
                    .buttonStyle(.glassProminent)
            }
        }
    }

    /// Batch Add's result list and rows.
    private func reviewList(_ proposal: CategoryDraftProposal) -> some View {
        let acceptedCount = proposal.items.items.count(where: \.isAccepted)
        let allAccepted = acceptedCount == proposal.items.items.count
        return List {
            if !proposal.unsupportedRequest.isEmpty {
                Section {
                    unsupportedWarning(proposal.unsupportedRequest)
                }
            }
            Section {
                TextField("Category Name", text: nameBinding)
                    .submitLabel(.done)
            } header: {
                Text("Name")
            } footer: {
                if !isNameValid(proposal.name) {
                    Text("Category names must not be empty, must be unique, and can have up to 40 characters.")
                        .foregroundStyle(.orange)
                }
            }
            Section {
                ForEach(proposal.items.items) { item in
                    MovieResultItem(
                        movie: item.value.metadata,
                        isSelected: item.isAccepted,
                        onSelectionChanged: { setAccepted($0, for: item.id) }
                    )
                }
            } header: {
                HStack(alignment: .firstTextBaseline) {
                    Text("\(acceptedCount) of \(proposal.items.items.count) anime")
                        .monospacedDigit()
                        .contentTransition(.numericText(value: Double(acceptedCount)))
                    Spacer()
                    Button(allAccepted ? "Deselect All" : "Select All") {
                        setAllAccepted(!allAccepted)
                    }
                    .buttonStyle(.borderless)
                    .font(.subheadline)
                    .contentTransition(.opacity)
                }
            } footer: {
                if proposal.uncheckedCount > 0 {
                    Text("\(proposal.uncheckedCount) anime could not be checked. They are not in the list.")
                }
            }
        }
        .listStyle(.inset)
        .textCase(nil)
        .scrollDismissesKeyboard(.interactively)
        .preferredNavigationBarScrollEdgeEffect()
    }

    private func unsupportedWarning(_ request: String) -> some View {
        Label {
            Text("Not applied: “\(request)”. AniShelf cannot filter by this, so the list ignores it.")
        } icon: {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.orange)
        }
        .font(.subheadline)
    }

    /// Animates only the keystroke that shows or hides the name warning, inside the change
    /// itself; the List's section footer does not reliably follow a value-keyed animation.
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

    private func setAccepted(_ isAccepted: Bool, for id: UUID) {
        guard let index = draft.proposal?.items.items.firstIndex(where: { $0.id == id }) else { return }
        withAnimation(.snappy) { draft.proposal?.items.items[index].isAccepted = isAccepted }
    }

    private func setAllAccepted(_ isAccepted: Bool) {
        guard var items = draft.proposal?.items.items else { return }
        for index in items.indices { items[index].isAccepted = isAccepted }
        withAnimation(.snappy) { draft.proposal?.items.items = items }
    }

    private func isNameValid(_ name: String) -> Bool {
        store.validatedCategoryName(name) != nil
    }

    private var canApply: Bool {
        guard draft.state == .review, let proposal = draft.proposal else { return false }
        return isNameValid(proposal.name) && proposal.items.items.contains(where: \.isAccepted)
    }

    private func apply() {
        if draft.apply(in: store) == nil { showsApplyFailure = true }
    }

    private var hasMatches: Bool {
        draft.proposal?.items.items.isEmpty == false
    }

    // MARK: - Chrome

    @ToolbarContentBuilder
    private var toolbar: some ToolbarContent {
        ToolbarItem(placement: .cancellationAction) {
            Button(action: dismiss.callAsFunction) {
                SheetCloseLabel(title: "Cancel")
            }
            .accessibilityLabel(Text("Cancel"))
        }
        if step == .review, hasMatches {
            #if os(macOS)
                ToolbarItem(placement: .destructiveAction) {
                    Button("Edit Description") { draft.edit() }
                }
            #else
                ToolbarItem(placement: .sheetTrailing) {
                    Button("Edit Description", systemImage: "square.and.pencil") { draft.edit() }
                }
            #endif
        }
        #if os(macOS)
            if step == .describing {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Find Anime", action: start)
                        .disabled(!draft.canStart)
                        .keyboardShortcut(.return, modifiers: .command)
                }
            } else if step == .review, hasMatches {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Create Category", action: apply)
                        .disabled(!canApply)
                        .keyboardShortcut(.return, modifiers: .command)
                }
            }
        #endif
    }

    #if !os(macOS)
        @ViewBuilder
        private var bottomAction: some View {
            switch step {
            case .describing:
                bottomButton("Find Anime", systemImage: "sparkles", isEnabled: draft.canStart, action: start)
            case .review where hasMatches:
                bottomButton("Create Category", systemImage: "folder.badge.plus", isEnabled: canApply, action: apply)
            case .working, .failed, .review:
                EmptyView()
            }
        }

        private func bottomButton(
            _ title: LocalizedStringKey,
            systemImage: String,
            isEnabled: Bool,
            action: @escaping () -> Void
        ) -> some View {
            Button(action: action) {
                Label(title, systemImage: systemImage)
                    .font(.headline)
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.glassProminent)
            .controlSize(.large)
            .disabled(!isEnabled)
            .padding(.horizontal, 20)
            .padding(.vertical, 8)
        }
    #endif
}

extension AIBackend: Identifiable {
    var id: Self { self }
}
