//
//  LibraryWindowBehaviors.swift
//  AniShelf
//
//  Created by Claude Code on behalf of samuelhe52 on 2026/10/17.
//

import AppIntents
import DataProvider
import SwiftUI

extension View {
    /// Window-level library behavior both library roots share.
    ///
    /// `openRoutedEntry` shows the
    /// entry an airing-reminder notification or, on iOS, an Open Entry intent opened in this
    /// window, after the root dismisses whatever covers the library. Selection pruning stays with each root, since only the root
    /// knows which entries its window shows.
    func libraryWindowBehaviors(
        store: LibraryStore,
        browse: LibraryBrowseState,
        openRoutedEntry: @escaping (AnimeEntry) -> Void
    ) -> some View {
        modifier(
            LibraryWindowBehaviors(
                store: store,
                browse: browse,
                openRoutedEntry: openRoutedEntry
            )
        )
    }
}

fileprivate struct LibraryWindowBehaviors: ViewModifier {
    let store: LibraryStore
    let browse: LibraryBrowseState
    let openRoutedEntry: (AnimeEntry) -> Void

    @Environment(\.windowSceneIdentifier) private var windowSceneIdentifier
    private let airingReminders = AiringReminderCoordinator.shared
    private let windows = AppWindowCoordinator.shared

    func body(content: Content) -> some View {
        content
            .task(id: browse.highlightRequest?.token) {
                // Expire the request so rows recreated later by scrolling or filtering do not pulse again.
                guard browse.highlightRequest != nil,
                    (try? await Task.sleep(for: LibraryHighlightRequest.lifetime)) != nil
                else { return }
                browse.highlightRequest = nil
            }
            .onChange(of: airingReminders.pendingRoute, initial: true) {
                handleAiringReminderRoute()
            }
            .onChange(of: windowSceneIdentifier) {
                handleAiringReminderRoute()
            }
            // A route targeting a closed window falls back to the remaining windows. Deferring
            // lets a disconnected iOS scene leave `connectedScenes` first.
            .onChange(of: windows.registeredWindowIDs) {
                Task { @MainActor in handleAiringReminderRoute() }
            }
            #if !os(macOS)
                .onAppIntentExecution(OpenLibraryEntryIntent.self) { intent in
                    // The system delivers the intent to one scene, so only this window opens the detail.
                    guard let identity = LibraryEntryIdentity(rawID: intent.target.id),
                        let entry = store.repository.existingEntry(identity: identity),
                        entry.onDisplay
                    else { return }
                    browse.isSearching = false
                    openRoutedEntry(entry)
                }
            #endif
            // The warning is app-wide, so only the most recently active library window shows it;
            // Settings and Support have no presenter for it.
            .alert(
                airingReminderWarningTitle,
                isPresented: Binding(
                    get: {
                        airingReminders.presentedWarning != nil
                            && windows.isFrontmostLibraryWindow(windowSceneIdentifier)
                    },
                    set: { isPresented in
                        if !isPresented {
                            airingReminders.dismissPresentedWarning()
                        }
                    }
                )
            ) {
                Button("OK") { airingReminders.dismissPresentedWarning() }
            } message: {
                Text(airingReminderWarningMessage)
            }
            .sheet(isPresented: duplicateRepairPresented) {
                LibraryDuplicateRepairSheet(store: store)
                    .presentationDetents([.large])
                    .presentationSizing(.page)
                    .macSheetFrame(width: 760, height: 640)
            }
    }

    private var duplicateRepairPresented: Binding<Bool> {
        Binding(
            get: { store.requiresDuplicateRepair },
            set: { _ in }
        )
    }

    private func handleAiringReminderRoute() {
        // A window whose scene is already disconnected is being torn down and must not consume the route.
        if let windowSceneIdentifier, !WindowScenes.canReceiveRoute(windowSceneIdentifier) {
            return
        }
        guard
            let entryIdentityRawID = airingReminders.claimPendingRoute(
                forSceneIdentifier: windowSceneIdentifier,
                isSceneConnected: WindowScenes.canReceiveRoute
            )
        else { return }
        guard let entry = store.repository.existingEntry(identityRawID: entryIdentityRawID) else {
            return
        }
        browse.isSearching = false
        openRoutedEntry(entry)
    }

    private var airingReminderWarningMessage: LocalizedStringResource {
        airingReminders.presentedWarning?.localizedMessage
            ?? "Some reminders could not be scheduled."
    }

    private var airingReminderWarningTitle: LocalizedStringResource {
        airingReminders.presentedWarning?.localizedTitle
            ?? "Reminder Scheduling Issue"
    }
}
