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
/// The library changes only when the user taps Apply.
struct CategoryDraftSheet: View {
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
            content
                .navigationTitle(title)
                .inlineNavigationTitle()
                .toolbar { toolbar }
        }
        #if os(macOS)
            .frame(width: 480, height: 540)
        #endif
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

    private var title: LocalizedStringResource {
        draft.state == .review ? "New Category" : "Describe a Category"
    }

    @ViewBuilder
    private var content: some View {
        switch draft.state {
        case .describing:
            describeForm
        case .planning:
            progress {
                ProgressView()
                Text("Reading your request…")
            }
        case .checking(let done, let total):
            progress {
                ProgressView(value: Double(done), total: Double(max(total, 1)))
                    .frame(maxWidth: 260)
                Text("Checking \(total) anime")
                Text("\(done) of \(total)")
                    .font(.subheadline)
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
            }
        case .review:
            reviewForm
        case .failed(let error):
            ContentUnavailableView {
                Label("Could Not Finish", systemImage: "exclamationmark.triangle")
            } description: {
                Text(error.message)
            } actions: {
                Button("Try Again") { draft.retry(library: store.library) }
                    .buttonStyle(.borderedProminent)
                Button("Edit Description") { draft.edit() }
            }
        case .applied:
            Color.clear
        }
    }

    // MARK: - Describe

    private var describeForm: some View {
        @Bindable var draft = draft
        return Form {
            Section {
                TextField(
                    "For example: fantasy anime I finished, or movies from Studio Ghibli",
                    text: $draft.request, axis: .vertical
                )
                .lineLimit(3...6)
            } footer: {
                VStack(alignment: .leading, spacing: 6) {
                    if draft.trimmedRequest.count > CategoryQueryPlan.maximumRequestLength {
                        Text(
                            "Shorten the description to \(CategoryQueryPlan.maximumRequestLength) characters or fewer."
                        )
                        .foregroundStyle(.orange)
                    }
                    Text(
                        "\(draft.backend.displayName) checks your library. You review the result before anything changes."
                    )
                }
            }
        }
        .formStyle(.grouped)
    }

    // MARK: - Review

    @ViewBuilder
    private var reviewForm: some View {
        if let proposal = draft.proposal, !proposal.items.items.isEmpty {
            Form {
                if !proposal.unsupportedRequest.isEmpty {
                    Section {
                        unsupportedWarning(proposal.unsupportedRequest)
                    }
                }
                Section {
                    TextField("Category Name", text: nameBinding)
                } header: {
                    Text("Name")
                } footer: {
                    if !isNameValid(proposal.name) {
                        Text("Category names must not be empty, must be unique, and can have up to 40 characters.")
                            .foregroundStyle(.orange)
                    }
                }
                Section {
                    ForEach(proposal.items.items.indices, id: \.self) { index in
                        candidateRow(proposal.items.items[index], index: index)
                    }
                } header: {
                    Text("\(proposal.items.acceptedValues.count) of \(proposal.items.items.count) anime")
                        .monospacedDigit()
                } footer: {
                    if proposal.uncheckedCount > 0 {
                        Text("\(proposal.uncheckedCount) anime could not be checked. They are not in the list.")
                    }
                }
            }
            .formStyle(.grouped)
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
            }
        }
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

    private func candidateRow(_ item: AIProposal<CategoryDraftCandidate>.Item, index: Int) -> some View {
        Toggle(isOn: acceptedBinding(index)) {
            VStack(alignment: .leading, spacing: 2) {
                Text(verbatim: item.value.title)
                    .lineLimit(2)
                HStack(spacing: 4) {
                    if let year = item.value.year {
                        Text(verbatim: String(year))
                        Text(verbatim: "·")
                    }
                    Text(kindLabel(item.value.kind))
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }
        }
    }

    private func kindLabel(_ kind: CategoryEntryKind) -> LocalizedStringResource {
        switch kind {
        case .movie: "Movie"
        case .series: "TV Series"
        case .season: "Season"
        }
    }

    private var nameBinding: Binding<String> {
        Binding(
            get: { draft.proposal?.name ?? "" },
            set: { draft.proposal?.name = $0 }
        )
    }

    private func acceptedBinding(_ index: Int) -> Binding<Bool> {
        Binding(
            get: {
                guard let items = draft.proposal?.items.items, items.indices.contains(index) else { return false }
                return items[index].isAccepted
            },
            set: { isAccepted in
                guard let count = draft.proposal?.items.items.count, index < count else { return }
                draft.proposal?.items.items[index].isAccepted = isAccepted
            }
        )
    }

    private func isNameValid(_ name: String) -> Bool {
        store.validatedCategoryName(name) != nil
    }

    private var canApply: Bool {
        guard let proposal = draft.proposal else { return false }
        return isNameValid(proposal.name) && !proposal.items.acceptedValues.isEmpty
    }

    // MARK: - Chrome

    @ToolbarContentBuilder
    private var toolbar: some ToolbarContent {
        switch draft.state {
        case .describing, .failed, .applied:
            ToolbarItem(placement: .cancellationAction) {
                Button("Cancel") { dismiss() }
            }
            if draft.state == .describing {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Continue") { draft.start(library: store.library) }
                        .disabled(!draft.canStart)
                }
            }
        case .planning, .checking:
            ToolbarItem(placement: .cancellationAction) {
                Button("Cancel") { draft.cancel() }
            }
        case .review:
            ToolbarItem(placement: .cancellationAction) {
                Button("Edit") { draft.edit() }
            }
            ToolbarItem(placement: .confirmationAction) {
                Button("Apply") {
                    if draft.apply(in: store) == nil { showsApplyFailure = true }
                }
                .disabled(!canApply)
            }
        }
    }

    private func progress<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
        VStack(spacing: 12, content: content)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .padding()
    }
}

extension AIBackend: Identifiable {
    var id: Self { self }
}
