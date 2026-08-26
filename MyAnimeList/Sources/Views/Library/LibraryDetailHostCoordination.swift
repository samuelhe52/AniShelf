//
//  LibraryDetailHostCoordination.swift
//  AniShelf
//
//  Created by OpenAI Codex on behalf of Samuel He on 2026/7/25.
//

import DataProvider
import LibrarySync
import SwiftUI

struct LibraryDetailHostCoordination: ViewModifier {
    let store: LibraryStore
    let interaction: LibraryEntryInteractionState
    let detailSessionStore: EntryDetailSessionStore
    let horizontalSizeClass: UserInterfaceSizeClass?
    let isSearching: Bool
    let isShowingProfileSettings: Bool
    @Binding var workspaceState: LibraryInspectorDetailWorkspaceState
    @Binding var persistedLastInspectorDetailEntryIdentity: String?

    func body(content: Content) -> some View {
        content
            .onAppear {
                updateDetailHost()
                restorePresentedDetailIfNeeded()
            }
            .onChange(of: horizontalSizeClass) {
                updateDetailHost()
            }
            .onChange(of: detailHostMigrationBlocked) { _, isBlocked in
                guard !isBlocked else { return }
                interaction.reconcileDetailHostIfPossible(migrationBlocked: false)
            }
            .onInteractiveResizeChange { isResizing in
                interaction.interactiveResizeDidChange(
                    isResizing,
                    migrationBlocked: detailHostMigrationBlocked
                )
            }
            .onChange(of: interaction.presentedDetailEntryID, initial: true) { _, identity in
                synchronizePresentedDetail(identity)
            }
            .onChange(of: interaction.detailHostPresentation) {
                reconcileInspectorDetailPersistence()
            }
            .onChange(of: store.libraryRevision) {
                synchronizePresentedDetail(interaction.presentedDetailEntryID)
            }
    }

    static func updateDetailHost(
        interaction: LibraryEntryInteractionState,
        detailSessionStore: EntryDetailSessionStore,
        desiredHost: LibraryEntryDetailHost,
        migrationBlocked: Bool,
        rootPresentationActive: Bool
    ) {
        if !rootPresentationActive,
            let presentation = interaction.detailHostPresentation,
            presentation.host != desiredHost || !presentation.isHostPresented
        {
            detailSessionStore.session(for: interaction.presentedDetailEntryID)?
                .dismissActiveSheetForHostChange()
        }

        interaction.requestDetailHost(
            desiredHost,
            migrationBlocked: migrationBlocked,
            rootPresentationActive: rootPresentationActive
        )
    }

    static func prepareDetailSession(
        for entry: AnimeEntry,
        detailSessionStore: EntryDetailSessionStore,
        repository: LibraryRepository
    ) {
        detailSessionStore.synchronizePresentedDetail(
            identity: entry.libraryIdentity,
            repository: repository,
            resolveEntry: { identity in
                identity == entry.libraryIdentity
                    ? entry : repository.existingEntry(identity: identity)
            }
        )
    }

    private var detailHostPolicy: LibraryEntryDetailHostPolicy {
        LibraryEntryDetailHostPolicy(horizontalSizeClass: horizontalSizeClass)
    }

    private var detailHostMigrationBlocked: Bool {
        detailSessionStore.session(
            for: interaction.presentedDetailEntryID
        )?.blocksHostMigration == true
    }

    private var isRootPresentationActive: Bool {
        isSearching
            || isShowingProfileSettings
            || interaction.workflowPresentation != nil
    }

    private func updateDetailHost() {
        Self.updateDetailHost(
            interaction: interaction,
            detailSessionStore: detailSessionStore,
            desiredHost: detailHostPolicy.host,
            migrationBlocked: detailHostMigrationBlocked,
            rootPresentationActive: isRootPresentationActive
        )
    }

    private func synchronizePresentedDetail(_ identity: LibraryEntryIdentity?) {
        let didResolveDetail = detailSessionStore.synchronizePresentedDetail(
            identity: identity,
            repository: store.repository,
            resolveEntry: { store.repository.existingEntry(identity: $0) }
        )
        if identity != nil, !didResolveDetail {
            interaction.dismissDetails()
        }
    }

    private func reconcileInspectorDetailPersistence() {
        switch LibraryInspectorDetailWorkspaceState.persistenceAction(
            for: interaction.presentedDetailEntryID,
            committedHostPresentation: interaction.detailHostPresentation
        ) {
        case .clear:
            persistedLastInspectorDetailEntryIdentity = nil
        case .persist(let identity):
            persistedLastInspectorDetailEntryIdentity = identity.rawID
        case .preserve:
            break
        }
    }

    private func restorePresentedDetailIfNeeded() {
        let restorationAction = workspaceState.initialRestorationAction(
            for: interaction.desiredDetailHost,
            presentedDetailEntryIdentity: interaction.presentedDetailEntryID,
            savedIdentityRawID: persistedLastInspectorDetailEntryIdentity,
            isRestorableIdentity: { identityRawID in
                guard let entry = store.repository.existingEntry(identityRawID: identityRawID) else {
                    return false
                }
                return entry.onDisplay
            }
        )

        switch restorationAction {
        case .clearInvalidSavedIdentity:
            persistedLastInspectorDetailEntryIdentity = nil
            interaction.dismissDetails()
        case .none:
            return
        case .restore(let identityRawID):
            guard let entry = store.repository.existingEntry(identityRawID: identityRawID),
                entry.onDisplay
            else {
                persistedLastInspectorDetailEntryIdentity = nil
                interaction.dismissDetails()
                return
            }
            Self.prepareDetailSession(
                for: entry,
                detailSessionStore: detailSessionStore,
                repository: store.repository
            )
            interaction.openDetails(for: entry)
        }
    }
}

extension View {
    func libraryDetailHostCoordination(
        store: LibraryStore,
        interaction: LibraryEntryInteractionState,
        detailSessionStore: EntryDetailSessionStore,
        horizontalSizeClass: UserInterfaceSizeClass?,
        isSearching: Bool,
        isShowingProfileSettings: Bool,
        workspaceState: Binding<LibraryInspectorDetailWorkspaceState>,
        persistedLastInspectorDetailEntryIdentity: Binding<String?>
    ) -> some View {
        modifier(
            LibraryDetailHostCoordination(
                store: store,
                interaction: interaction,
                detailSessionStore: detailSessionStore,
                horizontalSizeClass: horizontalSizeClass,
                isSearching: isSearching,
                isShowingProfileSettings: isShowingProfileSettings,
                workspaceState: workspaceState,
                persistedLastInspectorDetailEntryIdentity: persistedLastInspectorDetailEntryIdentity
            )
        )
    }
}
