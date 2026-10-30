//
//  CategoryDraftSheet.swift
//  AniShelf
//
//  Created by Claude Code on behalf of Samuel He on 2026/10/29.
//

import SwiftUI

/// "Describe a Category": the user writes what the category holds, watches the model sort
/// the library into it, adjusts the result, and applies it.
///
/// The library changes only when the user taps Create Category.
struct CategoryDraftSheet: View {
    /// The visible step.
    ///
    /// The plan, the check, and the review share the sieve, so only real step changes
    /// cross-fade.
    private enum Step: Hashable {
        case describing
        case sieve
        case failed
    }

    /// The iOS bottom bar's button, or the Mac's confirmation action.
    private enum PrimaryAction: Hashable {
        case find
        case stop
        case create
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
                case .sieve:
                    CategoryDraftSieve(draft: draft)
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
                // scroll edge effect keeps posters from showing through the button.
                .safeAreaBar(edge: .bottom) {
                    bottomAction
                    .animation(stepAnimation, value: primaryAction)
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
        // Keep the sieve on screen while the sheet dismisses.
        case .planning, .checking, .review, .applied: .sieve
        case .failed: .failed
        }
    }

    private var title: LocalizedStringResource {
        step == .sieve && draft.proposal != nil ? "New Category" : "Describe a Category"
    }

    private var stepAnimation: Animation {
        .spring(response: 0.34, dampingFraction: 0.88)
    }

    private var primaryAction: PrimaryAction? {
        switch draft.state {
        case .describing: .find
        case .checking: .stop
        case .review where hasCandidates: .create
        default: nil
        }
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

    // MARK: - Apply

    private var hasCandidates: Bool {
        draft.proposal?.items.items.isEmpty == false
    }

    private var canApply: Bool {
        guard draft.state == .review, let proposal = draft.proposal else { return false }
        return store.validatedCategoryName(proposal.name) != nil && proposal.items.items.contains(where: \.isAccepted)
    }

    private func apply() {
        if draft.apply(in: store) == nil { showsApplyFailure = true }
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
        if step == .sieve {
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
            if primaryAction == .find {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Find Anime", action: start)
                        .disabled(!draft.canStart)
                        .keyboardShortcut(.return, modifiers: .command)
                }
            } else if primaryAction == .stop {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Stop and Review") { draft.stop() }
                }
            } else if primaryAction == .create {
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
            switch primaryAction {
            case .find:
                bottomButton("Find Anime", systemImage: "sparkles", isEnabled: draft.canStart, action: start)
            case .stop:
                Button {
                    draft.stop()
                } label: {
                    bottomLabel("Stop and Review", systemImage: "stop.fill")
                }
                .buttonStyle(.glass)
                .modifier(BottomButtonLayout())
            case .create:
                bottomButton("Create Category", systemImage: "folder.badge.plus", isEnabled: canApply, action: apply)
            case nil:
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
                bottomLabel(title, systemImage: systemImage)
            }
            .buttonStyle(.glassProminent)
            .disabled(!isEnabled)
            .animation(.spring(response: 0.32, dampingFraction: 0.86), value: isEnabled)
            .modifier(BottomButtonLayout())
        }

        private func bottomLabel(_ title: LocalizedStringKey, systemImage: String) -> some View {
            Label(title, systemImage: systemImage)
                .font(.headline)
                .frame(maxWidth: .infinity)
        }

        private struct BottomButtonLayout: ViewModifier {
            func body(content: Content) -> some View {
                content
                    .controlSize(.large)
                    .padding(.horizontal, 20)
                    .padding(.vertical, 8)
            }
        }
    #endif
}

extension AIBackend: Identifiable {
    var id: Self { self }
}
