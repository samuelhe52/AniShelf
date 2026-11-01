//
//  LibraryCategoryDialogs.swift
//  AniShelf
//
//  Created by Claude Code on behalf of Samuel He on 2026/10/13.
//

import SwiftUI

/// A request to ask the user for a category name.
struct LibraryCategoryNamePrompt: Identifiable, Equatable {
    enum Purpose: Equatable {
        /// Creates a category. `memberCount` is the number of selected anime that join it.
        case create(memberCount: Int)
        case rename(LibraryCategory)
    }

    let id = UUID()
    let purpose: Purpose

    var excludedCategoryID: LibraryCategory.ID? {
        if case .rename(let category) = purpose { category.id } else { nil }
    }
}

extension View {
    /// Asks for a category name and passes a validated name to `onSubmit`.
    ///
    /// Empty, overlong, and duplicate names show an explanation instead of calling `onSubmit`.
    func libraryCategoryNamePrompt(
        _ prompt: Binding<LibraryCategoryNamePrompt?>,
        onSubmit: @escaping (LibraryCategoryNamePrompt, String) -> Void
    ) -> some View {
        modifier(LibraryCategoryNamePromptModifier(prompt: prompt, onSubmit: onSubmit))
    }

    /// Confirms deletion of a category.
    ///
    /// The anime in it stay in the library.
    func libraryCategoryDeleteConfirmation(_ category: Binding<LibraryCategory?>) -> some View {
        modifier(LibraryCategoryDeleteConfirmationModifier(category: category))
    }
}

fileprivate struct LibraryCategoryNamePromptModifier: ViewModifier {
    @Environment(LibraryStore.self) private var store
    @Binding var prompt: LibraryCategoryNamePrompt?
    let onSubmit: (LibraryCategoryNamePrompt, String) -> Void

    @State private var name = ""
    @State private var isShowingInvalidName = false

    func body(content: Content) -> some View {
        content
            .alert(
                title,
                isPresented: Binding(
                    get: { prompt != nil },
                    set: { if !$0 { prompt = nil } }
                ),
                presenting: prompt
            ) { prompt in
                TextField("Category Name", text: $name)
                Button("Cancel", role: .cancel) {}
                Button(confirmTitle(for: prompt)) {
                    submit(prompt)
                }
            } message: { prompt in
                if case .create(let memberCount) = prompt.purpose, memberCount > 0 {
                    Text("\(memberCount) selected anime will be added to it.")
                }
            }
            .alert("Choose Another Name", isPresented: $isShowingInvalidName) {
                Button("OK", role: .cancel) {}
            } message: {
                Text("Category names must not be empty, must be unique, and can have up to 40 characters.")
            }
            .onChange(of: prompt?.id, initial: true) {
                if case .rename(let category) = prompt?.purpose {
                    name = category.name
                } else {
                    name = ""
                }
            }
    }

    private var title: LocalizedStringResource {
        switch prompt?.purpose {
        case .rename: "Rename Category"
        default: "New Category"
        }
    }

    private func confirmTitle(for prompt: LibraryCategoryNamePrompt) -> LocalizedStringResource {
        switch prompt.purpose {
        case .create: "Create"
        case .rename: "Rename"
        }
    }

    private func submit(_ prompt: LibraryCategoryNamePrompt) {
        guard let validated = store.validatedCategoryName(name, excluding: prompt.excludedCategoryID) else {
            isShowingInvalidName = true
            return
        }
        onSubmit(prompt, validated)
    }
}

fileprivate struct LibraryCategoryDeleteConfirmationModifier: ViewModifier {
    @Environment(LibraryStore.self) private var store
    @Binding var category: LibraryCategory?

    func body(content: Content) -> some View {
        content
            .confirmationDialog(
                Text("Delete “\(category?.name ?? "")”?"),
                isPresented: Binding(
                    get: { category != nil },
                    set: { if !$0 { category = nil } }
                ),
                titleVisibility: .visible,
                presenting: category
            ) { category in
                Button("Delete Category", role: .destructive) {
                    withAnimation(.snappy) {
                        store.deleteCategory(category.id)
                    }
                }
                Button("Cancel", role: .cancel) {}
            } message: { _ in
                Text("The anime in this category stay in your library.")
            }
    }
}
