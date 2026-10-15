//
//  MacLibraryCommands.swift
//  AniShelf
//
//  Created by Claude Code on behalf of samuelhe52 on 2026/10/15.
//

#if os(macOS)
    import DataProvider
    import SwiftUI

    /// Actions the key window's library publishes for the menu bar.
    ///
    /// Menu commands act on whichever window is key, so each `LibraryView` publishes its own
    /// actions through `focusedSceneValue`.
    struct MacLibraryCommandActions {
        var addAnime: () -> Void
        var findInLibrary: () -> Void
        var viewStyle: Binding<LibraryView.LibraryViewStyle>
        var isInspectorPresented: Bool
        var toggleInspector: () -> Void
        var isMultiSelecting: Bool
        var selectAll: () -> Void
        var clearSelection: () -> Void
        var openCategoryManager: () -> Void
        var refreshAllMetadata: () -> Void
        /// The entry that entry commands act on: the inspected or last-clicked entry.
        var targetEntry: AnimeEntry?
        var openDetails: (AnimeEntry) -> Void
        var editEntry: (AnimeEntry) -> Void
        var toggleFavorite: (AnimeEntry) -> Void
        var shareEntry: (AnimeEntry) -> Void
        var switchPoster: (AnimeEntry) -> Void
        var deleteEntry: (AnimeEntry) -> Void
        /// Asks to delete the batch selection.
        var deleteSelection: () -> Void
    }

    extension FocusedValues {
        @Entry var macLibraryCommands: MacLibraryCommandActions?
    }

    struct MacLibraryCommands: Commands {
        @FocusedValue(\.macLibraryCommands) private var library
        @Environment(\.openWindow) private var openWindow

        var body: some Commands {
            CommandGroup(replacing: .newItem) {
                Button("Add Anime…") { library?.addAnime() }
                    .keyboardShortcut("n")
                    .disabled(library == nil)
                Button("New Window") { openWindow(id: MacWindowID.library) }
                    .keyboardShortcut("n", modifiers: [.command, .option])
            }

            CommandGroup(after: .textEditing) {
                Divider()
                Button("Find in Library…") { library?.findInLibrary() }
                    .keyboardShortcut("f")
                    .disabled(library == nil)
                Button("Select All Anime") { library?.selectAll() }
                    .keyboardShortcut("a", modifiers: [.command, .shift])
                    .disabled(library == nil)
                Button("Deselect All") { library?.clearSelection() }
                    .disabled(library?.isMultiSelecting != true)
            }

            CommandGroup(before: .sidebar) {
                if let library {
                    Picker("View As", selection: library.viewStyle) {
                        ForEach(Array(LibraryView.LibraryViewStyle.allCases.enumerated()), id: \.element) {
                            index, style in
                            Text(style.nameKey)
                                .tag(style)
                                .keyboardShortcut(KeyEquivalent(Character("\(index + 1)")))
                        }
                    }
                    .pickerStyle(.inline)
                } else {
                    // Keeps the menu's layout stable while no library window is key.
                    ForEach(LibraryView.LibraryViewStyle.allCases, id: \.self) { style in
                        Button(style.nameKey) {}.disabled(true)
                    }
                }
                Divider()
            }

            CommandGroup(after: .sidebar) {
                Button(library?.isInspectorPresented == true ? "Hide Inspector" : "Show Inspector") {
                    library?.toggleInspector()
                }
                .keyboardShortcut("i", modifiers: [.command, .option])
                .disabled(library == nil)
            }

            // AniShelf has no Help Book; point Help at the website and its guides.
            CommandGroup(replacing: .help) {
                Link("AniShelf Website", destination: URL(string: "https://anishelf.konakona.dev")!)
                Link("Privacy Policy", destination: URL(string: "https://anishelf.konakona.dev/privacy/")!)
            }

            CommandMenu("Anime") {
                let entry = library?.targetEntry
                Button("Show Details") { if let entry { library?.openDetails(entry) } }
                    .keyboardShortcut(.return, modifiers: .command)
                    .disabled(entry == nil)
                Button("Edit…") { if let entry { library?.editEntry(entry) } }
                    .keyboardShortcut("e")
                    .disabled(entry == nil)
                Button(entry?.favorite == true ? "Remove from Favorites" : "Add to Favorites") {
                    if let entry { library?.toggleFavorite(entry) }
                }
                .keyboardShortcut("l")
                .disabled(entry == nil)
                Divider()
                Button("Switch Poster…") { if let entry { library?.switchPoster(entry) } }
                    .disabled(entry == nil)
                Button("Share…") { if let entry { library?.shareEntry(entry) } }
                    .disabled(entry == nil)
                Divider()
                Button("Delete…") {
                    if library?.isMultiSelecting == true {
                        library?.deleteSelection()
                    } else if let entry {
                        library?.deleteEntry(entry)
                    }
                }
                .keyboardShortcut(.delete)
                .disabled(entry == nil && library?.isMultiSelecting != true)
                Divider()
                Button("Edit Categories…") { library?.openCategoryManager() }
                    .disabled(library == nil)
                Button("Refresh All Metadata…") { library?.refreshAllMetadata() }
                    .disabled(library == nil)
            }
        }
    }

    enum MacWindowID {
        static let library = "library"
    }
#endif
